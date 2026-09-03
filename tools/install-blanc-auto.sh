#!/usr/bin/env bash
set -euo pipefail

ROUTER="${XKEEN_ROUTER:-192.168.1.1}"
SERVICE=codex-blancvpn-subscription
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUB_URL="$(security find-generic-password -a "$USER" -s "$SERVICE" -w)"

tmp="$(mktemp -d /tmp/blanc-auto-install.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/pool"

curl -fsSL --connect-timeout 10 --max-time 30 "$SUB_URL" -o "$tmp/sub"
if base64 -D -i "$tmp/sub" > "$tmp/list" 2>/dev/null && rg -q '^vless://' "$tmp/list"; then
  :
else
  cp "$tmp/sub" "$tmp/list"
fi

for code in ch se fi pl lt nl; do
  python3 "$SCRIPT_DIR/blanc_vless_to_xray.py" "$tmp/list" "$tmp/pool/$code.json" "$code"
done

scp -O -q "$SCRIPT_DIR/blanc-auto-router.sh" "root@$ROUTER:/tmp/blanc-auto"
scp -O -q "$tmp/pool/"*.json "root@$ROUTER:/tmp/"

ssh "root@$ROUTER" 'set -e
stamp=$(date +%Y%m%d-%H%M%S)
mkdir -p /opt/etc/xray/blanc-pool /opt/var/lib/blanc-auto
if [ -f /opt/sbin/blanc-auto ]; then cp -p /opt/sbin/blanc-auto "/opt/sbin/blanc-auto.bak-$stamp"; fi
cp /tmp/blanc-auto /opt/sbin/blanc-auto
chmod 755 /opt/sbin/blanc-auto
for code in ch se fi pl lt nl; do mv "/tmp/$code.json" "/opt/etc/xray/blanc-pool/$code.json"; done
cp -p /opt/etc/xray/configs/04_outbounds.json /opt/var/lib/blanc-auto/last-good.json
printf "ch\n" > /opt/var/lib/blanc-auto/current
printf "0\n" > /opt/var/lib/blanc-auto/fails
touch /opt/var/lib/blanc-auto/enabled
cron=/opt/var/spool/cron/crontabs/root
cp -p "$cron" "$cron.bak-blanc-auto-$stamp"
grep -v "/opt/sbin/blanc-auto run" "$cron" > "$cron.tmp"
printf "*/3 * * * * /opt/sbin/blanc-auto run >/dev/null 2>&1\n" >> "$cron.tmp"
mv "$cron.tmp" "$cron"
chmod 600 "$cron"
/opt/sbin/blanc-auto status'
