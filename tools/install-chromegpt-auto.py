#!/usr/bin/env python3
import pathlib
import plistlib
import subprocess
import shutil

home = pathlib.Path.home()
label = 'com.igor.chromegpt-auto'
plist = home / 'Library/LaunchAgents' / (label + '.plist')
logs = home / 'Library/Logs/ChromeGPT-Auto'
logs.mkdir(parents=True, exist_ok=True)
plist.parent.mkdir(parents=True, exist_ok=True)
runtime = home / 'Library/Application Support/ChromeGPT-Auto'
runtime.mkdir(parents=True, exist_ok=True)
for name in ('chromegpt_auto_proxy.py', 'chromegpt-auto-service.sh'):
    shutil.copy2(pathlib.Path(__file__).parent / name, runtime / name)
if plist.exists():
    subprocess.run(['/bin/launchctl', 'bootout', f'gui/{__import__("os").getuid()}', str(plist)], check=False)
plist.write_bytes(plistlib.dumps({
    'Label': label,
    'ProgramArguments': ['/bin/zsh', str(runtime / 'chromegpt-auto-service.sh')],
    'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 5,
    'StandardOutPath': str(logs / 'mode.log'),
    'StandardErrorPath': str(logs / 'error.log'),
}))
# Release only the dedicated old ChromeGPT forward, preserving the running browser.
socket = home / 'Library/Caches/com.igor.chromegpt-vless/ssh-control'
subprocess.run(['/usr/bin/ssh', '-S', str(socket), '-O', 'exit', 'root@192.168.1.1'], check=False)
subprocess.run(['/bin/launchctl', 'bootstrap', f'gui/{__import__("os").getuid()}', str(plist)], check=True)
print(plist)
