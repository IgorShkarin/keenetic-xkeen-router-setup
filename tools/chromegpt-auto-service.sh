#!/bin/zsh
set -eu
base="${0:A:h}"
# Router tunnel has its own supervisor; desktop mode works even if router is down.
(
  while true; do
    /usr/bin/ssh -N -o BatchMode=yes -o ConnectTimeout=5 -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=2 -L 127.0.0.1:10819:127.0.0.1:10809 root@192.168.1.1 || true
    sleep 5
  done
) &
tunnel_pid=$!
trap 'pkill -P $tunnel_pid 2>/dev/null || true; kill $tunnel_pid 2>/dev/null || true' EXIT TERM INT
/Users/igor/.pyenv/versions/3.10.13/bin/python3 "$base/chromegpt_auto_proxy.py"
