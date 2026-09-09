#!/usr/bin/env bash
set -euo pipefail

ROUTER="${XKEEN_ROUTER:-192.168.1.1}"
SERVICE="codex-blancvpn-subscription"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUB_URL="$(security find-generic-password -a "$USER" -s "$SERVICE" -w)"

tmp="$(mktemp -d /tmp/blanc-auto-install.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/pool"

case "$SUB_URL" in
  https://*) ;;
  *) echo "Keychain содержит некорректную ссылку подписки." >&2; exit 1 ;;
esac
[[ "$SUB_URL" != *$'\n'* && "$SUB_URL" != *'"'* ]] || {
  echo "Ссылка подписки содержит недопустимые символы." >&2
  exit 1
}

umask 077
printf 'url = "%s"\n' "$SUB_URL" > "$tmp/curl.conf"
curl -fsSL --connect-timeout 10 --max-time 30 \
  --config "$tmp/curl.conf" -o "$tmp/sub"
rm -f "$tmp/curl.conf"
unset SUB_URL

if base64 -D -i "$tmp/sub" > "$tmp/list" 2>/dev/null && rg -q '^vless://' "$tmp/list"; then
  :
else
  cp "$tmp/sub" "$tmp/list"
fi

generated=0
for code in ee ch se fi pl lt nl; do
  if python3 "$SCRIPT_DIR/blanc_vless_to_xray.py" \
      "$tmp/list" "$tmp/pool/$code.json" "$code"; then
    generated=$((generated + 1))
  else
    rm -f "$tmp/pool/$code.json"
  fi
done
[[ "$generated" -ge 2 ]] || {
  echo "В подписке найдено меньше двух VLESS-узлов." >&2
  exit 1
}

stamp="$(date +%Y%m%d-%H%M%S)"
remote_stage="/tmp/blanc-auto-install-$stamp"
ssh "root@$ROUTER" "mkdir -p '$remote_stage'"
scp -O -q "$SCRIPT_DIR/blanc-auto-router.sh" \
  "root@$ROUTER:$remote_stage/blanc-auto"
scp -O -q "$tmp/pool/"*.json "root@$ROUTER:$remote_stage/"

ssh "root@$ROUTER" sh -s -- "$remote_stage" "$stamp" <<'REMOTE'
set -e
stage=$1
stamp=$2
backup=/opt/var/backups/blanc-auto-install-$stamp
check_dir=/tmp/blanc-auto-validate-$stamp
mkdir -p "$backup" "$check_dir" /opt/etc/xray/blanc-pool /opt/var/lib/blanc-auto
cp -a /opt/etc/xray/blanc-pool "$backup/" 2>/dev/null || true
cp -a /opt/var/lib/blanc-auto "$backup/" 2>/dev/null || true
cp -p /opt/etc/xray/configs/04_outbounds.json "$backup/04_outbounds.json"
cp -p /opt/sbin/blanc-auto "$backup/blanc-auto.sh" 2>/dev/null || true
cp -p /opt/var/spool/cron/crontabs/root "$backup/root.crontab" 2>/dev/null || true
cp -a /opt/etc/xray/configs/. "$check_dir/"
for candidate in "$stage"/*.json; do
  cp -p "$candidate" "$check_dir/04_outbounds.json"
  XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray convert pb \
    -outpbfile /tmp/blanc-auto-install-check.pb "$check_dir"/*.json \
    >/tmp/blanc-auto-install-check.log 2>&1
done
cp "$stage/blanc-auto" /opt/sbin/blanc-auto
chmod 755 /opt/sbin/blanc-auto
for code in ee ch se fi pl lt nl; do
  rm -f "/opt/etc/xray/blanc-pool/$code.json"
done
cp -p "$stage"/*.json /opt/etc/xray/blanc-pool/
touch /opt/var/lib/blanc-auto/enabled
cron=/opt/var/spool/cron/crontabs/root
grep -v "/opt/sbin/blanc-auto run" "$cron" > "$cron.tmp" || true
printf '*/3 * * * * /opt/sbin/blanc-auto run >/dev/null 2>&1\n' >> "$cron.tmp"
mv "$cron.tmp" "$cron"
chmod 600 "$cron"
current=$(cat /opt/var/lib/blanc-auto/current 2>/dev/null || true)
mode=$(/opt/sbin/blanc-auto mode 2>/dev/null || echo blanc)
if [ "$mode" = "blanc" ] && /opt/sbin/blanc-auto test >/dev/null 2>&1; then
  case "$current" in
    ee|ch|se|fi|pl|lt|nl) /opt/sbin/blanc-auto adopt "$current" ;;
    *)
      cp -p /opt/etc/xray/configs/04_outbounds.json /opt/var/lib/blanc-auto/last-good.json
      printf 'unknown\n' > /opt/var/lib/blanc-auto/current
      printf 'healthy\n' > /opt/var/lib/blanc-auto/health
      printf '0\n' > /opt/var/lib/blanc-auto/fails
      date +%s > /opt/var/lib/blanc-auto/last-check
      date +%s > /opt/var/lib/blanc-auto/last-ok
      rm -f /opt/var/lib/blanc-auto/needs-refresh
      ;;
  esac
else
  touch /opt/var/lib/blanc-auto/needs-refresh
  /opt/sbin/blanc-auto force
fi
rm -rf "$stage" "$check_dir"
/opt/sbin/blanc-auto status
echo "Backup: $backup"
REMOTE
