#!/usr/bin/env python3
"""Read-only external check using a forced-command SSH key and TLS validation."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def command(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=25)
    except (OSError, subprocess.TimeoutExpired):
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    settings = json.loads(Path(args.config).read_text())
    os.umask(0o077)
    previous_path = Path(settings['previous_result'])
    previous = json.loads(previous_path.read_text()) if previous_path.exists() else {}
    ssh = None
    if settings.get('ssh_key'):
        ssh = command(['ssh', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes',
                       '-o', 'ControlPath=none', '-o', 'ControlMaster=no',
                       '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=8',
                       '-i', settings['ssh_key'], 'root@' + settings['host'], 'status'])
    state = None
    if ssh and ssh.returncode == 0:
        try:
            state = json.loads(ssh.stdout)
        except json.JSONDecodeError:
            pass
    tls = command(['/usr/bin/curl', '--silent', '--output', '/dev/null', '--head',
                   '--write-out', '%{http_code}', '--connect-timeout', '5', '--max-time', '15',
                   '--proxy', '', '--noproxy', '', 'https://' + settings['host'] + '/'])
    tls_ok = bool(tls and tls.returncode == 0 and tls.stdout in ['200', '301', '302', '307', '308'])
    result = {'checked_at': time.time(), 'status_accessible': state is not None,
              'external_https_ok': tls_ok, 'scope': 'server VPN path and external HTTPS; no remote iPhone measurement'}
    if state is not None:
        result['server'] = state
        result['healthy'] = (state.get('health') in ['healthy', 'recovered'] and
                             state.get('age_seconds', 9999) < 180 and
                             state.get('timer_active') and not state.get('maintenance') and tls_ok)
        old = previous.get('server', {})
        result['new_incidents'] = max(0, state.get('incident_count', 0) - old.get('incident_count', 0))
        result['new_recoveries'] = max(0, state.get('recovery_count', 0) - old.get('recovery_count', 0))
        result['new_native_restarts'] = {u: max(0, int(v or 0) - int(old.get('native_restarts', {}).get(u, 0) or 0))
                                         for u, v in state.get('native_restarts', {}).items()}
    else:
        result['healthy'] = None if not settings.get('ssh_key') else False
        result['scope'] = 'external HTTPS only; VPN authentication and iPhone traffic unmeasured'
        result['assessment'] = 'public_https_reachable' if tls_ok else 'public_https_unavailable'
    temporary = previous_path.with_suffix('.new')
    temporary.write_text(json.dumps(result, sort_keys=True) + '\n')
    temporary.chmod(0o600)
    temporary.replace(previous_path)
    print(json.dumps(result, sort_keys=True))
    raise SystemExit(0 if result['healthy'] or (not settings.get('ssh_key') and tls_ok) else 1)


if __name__ == '__main__':
    main()
