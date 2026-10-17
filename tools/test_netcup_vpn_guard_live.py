#!/usr/bin/env python3
"""Run on the VPS: exercise recovery against a disposable service only."""
import json
import os
from pathlib import Path
import subprocess
import tempfile


def command(args, timeout=90):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(result.stdout[-2000:] + result.stderr[-2000:])
    return result.stdout


def production_pids():
    return {u: command(['systemctl', 'show', u, '--property=MainPID', '--value']).strip()
            for u in ['nginx', 'xray', 'home-vpn-xhttp', 'home-vpn-h2']}


def main():
    if os.geteuid() != 0 or not Path('/usr/local/libexec/netcup-vpn-guard.py').is_file():
        raise SystemExit('Run as root on the VPS with the guard installed')
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='vpn-guard-test-', dir='/run') as folder:
        base = Path(folder)
        target = base.name + '-target.service'
        runner_unit = base.name + '-runner.service'
        before = production_pids()
        try:
            command(['systemd-run', '--quiet', '--collect', '--unit=' + target,
                     '--property=Type=exec', '--property=RuntimeMaxSec=120',
                     '/usr/bin/sleep', '120'])
            target_before = command(['systemctl', 'show', target, '--property=MainPID', '--value']).strip()
            runner = base / 'runner.py'
            runner.write_text('BASE=' + repr(folder) + '\nTARGET=' + repr(target) + '\n' + r'''
import importlib.util,json,time
from pathlib import Path
spec=importlib.util.spec_from_file_location('guard','/usr/local/libexec/netcup-vpn-guard.py')
guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
guard.STATE_DIR=Path(BASE)/'state';guard.RUNTIME_DIR=Path(BASE)/'runtime'
guard.STATE_DIR.mkdir(mode=0o700);guard.RUNTIME_DIR.mkdir(mode=0o700)
now=time.time()
guard.save({'health':'local_path_failed','failures':2,'checked_at':now-61,'first_failure':now-125})
original_run=guard.run;original_requests=guard.requests
proxy_calls=0;attempts=[]
def safe_run(args,timeout=15):
    if len(args)>1 and args[0]=='systemctl' and args[1] in ['restart','try-restart','start','stop','reload','reload-or-restart']:
        # A production mutation is impossible through this test wrapper.
        if args[1]!='try-restart' or args[2] not in ['xray.service','nginx.service']:
            raise RuntimeError('Unexpected mutation request')
        attempts.append(args[2]);args=['systemctl','try-restart',TARGET]
    return original_run(args,timeout)
def requests(proxy=None):
    global proxy_calls
    if proxy:
        proxy_calls+=1
        if proxy_calls<=2:return {'google':False,'cloudflare':False}
    return original_requests(proxy)
guard.run=safe_run;guard.requests=requests
result=guard.check()
print(json.dumps({'health':result['health'],'requested_recovery':attempts,
                  'recovery_count':result.get('recovery_count'),
                  'post_recovery':result.get('post_recovery'),
                  'action':result['action']}))
if result['health']!='recovered' or attempts!=['xray.service'] or result.get('recovery_count')!=1:
    raise SystemExit(1)
''')
            properties = [
                'Type=oneshot', 'TimeoutStartSec=75s', 'UMask=0077',
                'MemoryMax=150M', 'TasksMax=64', 'Nice=10', 'CPUQuota=20%',
                'NoNewPrivileges=true', 'PrivateTmp=true', 'PrivateDevices=true',
                'ProtectSystem=strict',
                'ReadWritePaths=/var/log/nginx /var/log/xray ' + folder,
                'ProtectHome=true', 'ProtectKernelTunables=true',
                'ProtectKernelModules=true', 'ProtectControlGroups=true',
                'LockPersonality=true', 'RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6',
                'CapabilityBoundingSet=',
            ]
            args = ['systemd-run', '--quiet', '--wait', '--pipe', '--collect', '--unit=' + runner_unit]
            for prop in properties:
                args.append('--property=' + prop)
            output = command(args + ['/usr/bin/python3', str(runner)], timeout=95)
            result = json.loads(output.strip().splitlines()[-1])
            target_after = command(['systemctl', 'show', target, '--property=MainPID', '--value']).strip()
            result.update(disposable_service_restarted=target_before != target_after and target_after != '0',
                          production_pids_unchanged=before == production_pids())
            print(json.dumps(result, sort_keys=True))
            if not result['disposable_service_restarted'] or not result['production_pids_unchanged']:
                raise SystemExit(1)
        finally:
            for unit in [runner_unit, target]:
                subprocess.run(['systemctl', 'stop', unit], capture_output=True)
                subprocess.run(['systemctl', 'reset-failed', unit], capture_output=True)


if __name__ == '__main__':
    main()
