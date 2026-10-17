#!/usr/bin/env python3
"""Bounded server-side Reality/443 checks; no production changes while healthy."""
import argparse
import base64
import concurrent.futures
import copy
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

CONFIG = Path('/etc/netcup-vpn-guard/config.json')
STATE_DIR = Path('/var/lib/netcup-vpn-guard')
RUNTIME_DIR = Path('/run/netcup-vpn-guard')
ENDPOINTS = {
    'google': 'https://www.gstatic.com/generate_204',
    'cloudflare': 'https://cp.cloudflare.com/generate_204',
}
COOLDOWN = 1800


def decision(previous, observation, now):
    """Require consecutive, spaced failures with a working direct control."""
    state = copy.deepcopy(previous)
    state.update(checked_at=now, checks=observation, action='none')
    if observation.get('maintenance'):
        health = 'maintenance'
    elif not observation.get('probe_ready'):
        health = 'monitor_error'
    elif any(observation['proxy'].values()):
        health = 'healthy' if all(observation['proxy'].values()) else 'degraded'
    elif not any(observation.get('direct', {}).values()):
        health = 'upstream_unavailable'
    elif not all(observation['services'].values()):
        health = 'service_down'
    else:
        health = 'local_path_failed'
    state['health'] = health
    if health != 'local_path_failed':
        state.update(failures=0, first_failure=0)
        return state
    continuous = previous.get('health') == health and 0 < now - previous.get('checked_at', 0) <= 180
    state['failures'] = previous.get('failures', 0) + 1 if continuous else 1
    state['first_failure'] = previous.get('first_failure', now) if continuous else now
    if state['failures'] < 3 or now - state['first_failure'] < 120:
        return state
    if now - previous.get('last_recovery', 0) < COOLDOWN:
        state['action'] = 'cooldown'
        return state
    state['action'] = 'nginx' if not observation['listeners']['nginx'] else 'xray'
    return state


def run(args, timeout=15):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)


def service_active(unit):
    return run(['systemctl', 'is-active', '--quiet', unit]).returncode == 0


def listening(port):
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=1):
            return True
    except OSError:
        return False


def requests(proxy=None):
    def check(item):
        name, url = item
        args = ['/usr/bin/curl', '--silent', '--output', '/dev/null',
                '--write-out', '%{http_code}', '--max-time', '10',
                '--connect-timeout', '5', '--noproxy', '']
        args += ['--socks5-hostname', proxy] if proxy else ['--proxy', '']
        try:
            result = run(args + [url], timeout=12)
            return name, result.returncode == 0 and result.stdout == '204'
        except (OSError, subprocess.TimeoutExpired):
            return name, False
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        return dict(pool.map(check, ENDPOINTS.items()))


def probe_config(settings, port):
    source = json.loads(Path(settings['xray_config']).read_text())
    inbound = next(i for i in source['inbounds'] if i['tag'] == settings['inbound_tag'])
    identity = next(c for c in inbound['settings']['clients'] if c.get('email') == settings['probe_identity'])
    reality = inbound['streamSettings']['realitySettings']
    # Derive the public key locally from the current server key. No secret is
    # placed in argv, stdout, status, or an extra permanent configuration copy.
    raw = base64.urlsafe_b64decode(reality['privateKey'] + '=' * (-len(reality['privateKey']) % 4))
    if len(raw) != 32:
        raise ValueError('Invalid key length')
    key = subprocess.run(['/usr/bin/openssl', 'pkey', '-inform', 'DER', '-pubout', '-outform', 'DER'],
                         input=bytes.fromhex('302e020100300506032b656e04220420') + raw,
                         capture_output=True, timeout=5)
    if key.returncode or not key.stdout.startswith(bytes.fromhex('302a300506032b656e032100')) or len(key.stdout) != 44:
        raise ValueError('Public key derivation failed')
    public_key = base64.urlsafe_b64encode(key.stdout[-32:]).decode().rstrip('=')
    # Reuse the selected existing identity to follow its routing rules.
    # Never attribute these synthetic loopback checks to a physical phone.
    return {
        'log': {'loglevel': 'none'},
        'inbounds': [{'listen': '127.0.0.1', 'port': port, 'protocol': 'socks',
                      'settings': {'auth': 'noauth', 'udp': False}}],
        'outbounds': [{'protocol': 'vless', 'settings': {'vnext': [{
            'address': '127.0.0.1', 'port': 443, 'users': [{
                'id': identity['id'], 'encryption': 'none', 'flow': identity.get('flow', '')}]}]},
            'streamSettings': {'network': 'tcp', 'security': 'reality', 'realitySettings': {
                'serverName': reality['serverNames'][0], 'fingerprint': 'firefox',
                'publicKey': public_key, 'shortId': reality['shortIds'][0],
                'spiderX': '/'}}, 'mux': {'enabled': False}}],
    }


def read_state():
    try:
        return json.loads((STATE_DIR / 'status.json').read_text())
    except FileNotFoundError:
        return {}


def save(state):
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = STATE_DIR / 'status.json.new'
    tmp.write_text(json.dumps(state, sort_keys=True) + '\n')
    tmp.chmod(0o600)
    tmp.replace(STATE_DIR / 'status.json')
    # A small, bounded event history contains only synthetic health metadata.
    events = STATE_DIR / 'events.jsonl'
    previous = events.read_text().splitlines()[-99:] if events.exists() else []
    event = {k: state.get(k) for k in ['checked_at', 'health', 'action', 'failures', 'recovery_count']}
    events.write_text('\n'.join(previous + [json.dumps(event, sort_keys=True)]) + '\n')
    events.chmod(0o600)


def valid_xray_configuration(settings):
    # Keep all transport/routing fields, but avoid touching production log files
    # from the restricted guard. The original configuration is never modified.
    source = json.loads(Path(settings['xray_config']).read_text())
    source['log'] = {'loglevel': 'none'}
    with tempfile.TemporaryDirectory(prefix='validate-', dir=RUNTIME_DIR) as directory:
        path = Path(directory) / 'config.json'
        path.write_text(json.dumps(source))
        path.chmod(0o600)
        return run(['/usr/local/bin/xray', 'run', '-test', '-config', str(path)]).returncode == 0


def check():
    started = time.monotonic()
    os.umask(0o077)
    previous = read_state()
    if (CONFIG.parent / 'maintenance').exists():
        state = decision(previous, {'maintenance': True}, time.time())
        save(state)
        return state
    settings = json.loads(CONFIG.read_text())
    RUNTIME_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix='probe-', dir=RUNTIME_DIR) as directory:
        config_path = Path(directory) / 'client.json'
        config_path.write_text(json.dumps(probe_config(settings, port)))
        config_path.chmod(0o600)
        with subprocess.Popen(['/usr/local/bin/xray', 'run', '-config', str(config_path)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as process:
            try:
                ready = False
                for _ in range(30):
                    if process.poll() is not None:
                        break
                    if listening(port):
                        ready = True
                        break
                    time.sleep(0.1)
                proxy = requests('127.0.0.1:' + str(port)) if ready else {}
                observation = {'probe_ready': ready, 'proxy': proxy,
                               'services': {u: service_active(u) for u in ['nginx', 'xray']},
                               'listeners': {'nginx': listening(443), 'xray': listening(settings['backend_port'])}}
                if ready and not any(proxy.values()):
                    observation['direct'] = requests()
                state = decision(previous, observation, time.time())
                action = state['action']
                if action in ['nginx', 'xray']:
                    if action == 'xray' and not valid_xray_configuration(settings):
                        state['action'] = 'configuration_invalid_no_restart'
                    elif any(requests('127.0.0.1:' + str(port)).values()):
                        state.update(action='recovered_before_restart', health='degraded', failures=0, first_failure=0)
                    else:
                        # Record the cooldown before attempting a recovery, even if it fails.
                        state.update(last_recovery=time.time(), recovery_count=previous.get('recovery_count', 0) + 1)
                        save(state)
                        # nginx validates its own configuration during native reload;
                        # a failed reload preserves the running master and workers.
                        operation = 'reload' if action == 'nginx' else 'try-restart'
                        result = run(['systemctl', operation, action + '.service'], timeout=20)
                        post = requests('127.0.0.1:' + str(port))
                        state['post_recovery'] = post
                        if result.returncode == 0 and any(post.values()):
                            state.update(health='recovered', failures=0, first_failure=0)
                        else:
                            state['health'] = 'recovery_failed'
                if state['health'] not in ['healthy', 'recovered']:
                    state['last_problem'] = {'at': time.time(), 'health': state['health'], 'checks': observation}
                    if previous.get('health') != state['health']:
                        state['incident_count'] = previous.get('incident_count', 0) + 1
                state['duration_seconds'] = round(time.monotonic() - started, 3)
                state['native_restarts'] = {u: run(['systemctl', 'show', u, '--property=NRestarts', '--value']).stdout.strip()
                                            for u in ['nginx', 'xray']}
                save(state)
                return state
            finally:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--status', action='store_true')
    args = parser.parse_args()
    if args.status:
        state = read_state()
        state['age_seconds'] = round(time.time() - state.get('checked_at', 0), 1)
        state['timer_active'] = service_active('netcup-vpn-guard.timer')
        state['maintenance'] = (CONFIG.parent / 'maintenance').exists()
        print(json.dumps(state, sort_keys=True))
        return
    try:
        state = check()
    except Exception as error:
        # Never log exception text, generated configuration, or connection credentials.
        state = read_state()
        state.update(checked_at=time.time(), health='monitor_error', error_type=type(error).__name__)
        save(state)
    print(json.dumps(state, sort_keys=True))
    if state['health'] == 'monitor_error':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
