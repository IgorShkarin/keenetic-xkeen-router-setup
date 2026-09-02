#!/usr/bin/env bash
set -euo pipefail

ROUTER="${XKEEN_ROUTER:-192.168.1.1}"
COUNTRY="${1:-}"
SERVICE="codex-blancvpn-subscription"
[[ -n "$COUNTRY" ]] || { echo "Использование: $0 ee|se|fi|pl|lt|ch|nl"; exit 2; }

if [[ "$COUNTRY" == "near" || "$COUNTRY" == "nearby" ]]; then
  for country in ee se fi pl lt; do
    if "$0" "$country"; then exit 0; fi
  done
  echo "Близкие узлы не прошли тест." >&2
  exit 1
fi

SUB_URL="$(security find-generic-password -a "$USER" -s "$SERVICE" -w 2>/dev/null || true)"
if [[ -z "$SUB_URL" ]]; then
  echo "Первый запуск: вставь ссылку BlancVPN в запрос Keychain." >&2
  security add-generic-password -U -a "$USER" -s "$SERVICE" -w
  SUB_URL="$(security find-generic-password -a "$USER" -s "$SERVICE" -w)"
fi

tmp="$(mktemp -d /tmp/blanc-country.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --connect-timeout 10 --max-time 30 "$SUB_URL" -o "$tmp/sub"
if base64 -D -i "$tmp/sub" > "$tmp/list" 2>/dev/null && rg -q '^vless://' "$tmp/list"; then :; else cp "$tmp/sub" "$tmp/list"; fi
python3 "$(dirname "$0")/blanc_vless_to_xray.py" "$tmp/list" "$tmp/out.json" "$COUNTRY"

remote_file=/opt/etc/xray/configs/04_outbounds.json
stamp="$(date +%Y%m%d-%H%M%S)"
backup="${remote_file}.bak-codex-country-$stamp"
scp -O -q "$tmp/out.json" "root@$ROUTER:/tmp/04_outbounds.codex-country.json"
if ! ssh root@$ROUTER "set -e; cp -p '$remote_file' '$backup'; xkeen -stop >/dev/null 2>&1 || true; mv /tmp/04_outbounds.codex-country.json '$remote_file'; XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray convert pb -outpbfile /tmp/check-country.pb /opt/etc/xray/configs/*.json >/tmp/check-country.log 2>&1; xkeen -start >/dev/null 2>&1; sleep 2; xkeen -status | grep -q 'запущен'"; then
  echo "Не удалось запустить новый узел; откатываю." >&2
  ssh root@$ROUTER "cp -p '$backup' '$remote_file'; xkeen -stop >/dev/null 2>&1 || true"
  exit 1
fi

set +e
result="$(ssh root@$ROUTER 'curl --proxy socks5h://127.0.0.1:10808 -sS -o /dev/null --connect-timeout 10 --max-time 20 -w "YouTube HTTP %{http_code} total=%{time_total}s\n" https://www.youtube.com/generate_204; y=$?; curl --proxy socks5h://127.0.0.1:10808 -sS -o /dev/null --connect-timeout 10 --max-time 20 -w "ChatGPT HTTP %{http_code} total=%{time_total}s\n" https://chatgpt.com/cdn-cgi/trace; c=$?; echo "exit youtube=$y chatgpt=$c"; tail -n 160 /opt/var/log/xray/error.log | grep -Ei "proxy/socks.*(youtube|chatgpt)|proxy/vless/outbound.*tunneling" | tail -n 10')"
status=$?
set -e
echo "$result"
if [[ "$status" -ne 0 ]] || ! grep -Eq 'YouTube HTTP 2(00|04)' <<<"$result" || ! grep -Eq 'ChatGPT HTTP 2[0-9][0-9]' <<<"$result"; then
  echo "Тест не пройден; откатываю предыдущий outbound." >&2
  ssh root@$ROUTER "cp -p '$backup' '$remote_file'; xkeen -stop >/dev/null 2>&1 || true"
  exit 1
fi
echo "Готово: узел переключён и тест пройден. Backup: $backup"
