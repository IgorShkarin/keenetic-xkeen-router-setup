#!/bin/zsh
set -euo pipefail
app_path="/Users/igor/Applications/ChromeGPT.app"
profile_path="/Users/igor/Library/Application Support/ChromeGPT"
# Automatic loopback proxy is supervised by the ChromeGPT LaunchAgent.
/bin/launchctl kickstart "gui/$(id -u)/com.igor.chromegpt-auto"
/usr/bin/open -na "$app_path" --args \
  "--user-data-dir=$profile_path" \
  "--proxy-server=socks5://127.0.0.1:10809" \
  "--host-resolver-rules=MAP * 0.0.0.0 , EXCLUDE 127.0.0.1" \
  "--proxy-bypass-list=localhost;127.0.0.1;[::1]" \
  --disable-quic \
  --force-webrtc-ip-handling-policy=disable_non_proxied_udp
