#!/bin/zsh
set -euo pipefail

router="root@192.168.1.1"
app_path="/Users/igor/Applications/ChromeGPT.app"
profile_path="/Users/igor/Library/Application Support/ChromeGPT"
local_port=10809
remote_port=10809
control_dir="/Users/igor/Library/Caches/com.igor.chromegpt-vless"
control_socket="$control_dir/ssh-control"
proxy_url="socks5h://127.0.0.1:$local_port"
access_log="/opt/var/log/xray/access.log"

fail() {
  print -u2 -- "$1"
  exit 1
}

[[ -d "$app_path" ]] || fail "ChromeGPT не найден: $app_path"
mkdir -p "$control_dir"
chmod 700 "$control_dir"

# A live ChromeGPT process would keep its original proxy settings. Stop rather
# than letting Chrome silently reuse that process with different arguments.
lock_target=$(readlink "$profile_path/SingletonLock" 2>/dev/null || true)
if [[ -n "$lock_target" ]]; then
  lock_pid=${lock_target##*-}
  if [[ "$lock_pid" == <-> ]] && kill -0 "$lock_pid" 2>/dev/null; then
    fail "ChromeGPT уже запущен. Закрой его и повтори запуск через этот файл."
  fi
fi

ssh_args=(-S "$control_socket" -o BatchMode=yes -o ConnectTimeout=5)
if ! /usr/bin/ssh "${ssh_args[@]}" -O check "$router" >/dev/null 2>&1; then
  [[ ! -e "$control_socket" ]] || rm -f "$control_socket"
  /usr/bin/ssh -M -S "$control_socket" -fN \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -L "127.0.0.1:$local_port:127.0.0.1:$remote_port" \
    "$router" || fail "Не удалось поднять SSH-туннель к VLESS. ChromeGPT не запущен."
fi

# Prove the tunneled SOCKS request reached the dedicated VLESS route before
# starting the browser. Any failure is closed: there is no DIRECT fallback.
before_lines=$(/usr/bin/ssh "${ssh_args[@]}" "$router" "wc -l < $access_log" | tr -d '[:space:]')
[[ "$before_lines" == <-> ]] || fail "Не удалось прочитать журнал Xray. ChromeGPT не запущен."
exit_ip=$(/usr/bin/curl --fail --silent --show-error --connect-timeout 5 --max-time 10 \
  --proxy "$proxy_url" https://api.ipify.org) || fail "VLESS не отвечает через SOCKS. ChromeGPT не запущен."
new_log=$(/usr/bin/ssh "${ssh_args[@]}" "$router" \
  "tail -n +$((before_lines + 1)) $access_log") || fail "Не удалось проверить маршрут Xray. ChromeGPT не запущен."
print -r -- "$new_log" | /usr/bin/grep -Fq \
  'accepted tcp:api.ipify.org:443 [job-search-socks -> vless-reality]' || \
  fail "Запрос не подтверждён в журнале как VLESS. ChromeGPT не запущен."

print -- "VLESS проверен. Выходной IP: $exit_ip"
/usr/bin/open -na "$app_path" --args \
  "--user-data-dir=$profile_path" \
  "--proxy-server=socks5://127.0.0.1:$local_port" \
  "--host-resolver-rules=MAP * 0.0.0.0 , EXCLUDE 127.0.0.1" \
  "--proxy-bypass-list=localhost;127.0.0.1;[::1]" \
  --disable-quic \
  --force-webrtc-ip-handling-policy=disable_non_proxied_udp
