#!/bin/sh
set -eu
router=${XKEEN_ROUTER:-192.168.1.1}
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
stamp=$(date -u +%Y%m%dT%H%M%SZ)
stage=/tmp/home-vpn-monitor-$stamp
ssh -o BatchMode=yes "root@$router" "umask 077; mkdir '$stage'"
scp -O -q "$source_dir/home-vpn-auto.sh" "$source_dir/home-vpn-log.sh" "root@$router:$stage/"
ssh -o BatchMode=yes "root@$router" sh -s -- "$stage" "$stamp" <<'REMOTE'
set -eu
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
stage=$1; stamp=$2
backup=/opt/var/backups/home-vpn-monitor-$stamp
for utility in curl xray xkeen gzip tail head sha256sum awk sort nohup; do
    command -v "$utility" >/dev/null || { echo "Missing utility: $utility; nothing installed"; exit 1; }
done
sh -n "$stage/home-vpn-auto.sh"
sh -n "$stage/home-vpn-log.sh"
tries=0
while ! mkdir /tmp/home-vpn-auto.lock 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 90 ] || { echo 'Manager busy; nothing installed'; exit 1; }
    sleep 1
done
trap 'rmdir /tmp/home-vpn-auto.lock 2>/dev/null || true; rm -rf "$stage"' EXIT
[ ! -d /tmp/blanc-auto.lock ] || { echo 'Blanc manager busy; nothing installed'; exit 1; }
umask 077
mkdir -p "$backup"
cp -p /opt/sbin/home-vpn-auto "$backup/home-vpn-auto"
if [ -f /opt/sbin/home-vpn-log ]; then cp -p /opt/sbin/home-vpn-log "$backup/home-vpn-log"; fi
cp -a /opt/var/lib/home-vpn-auto "$backup/state"
cp -p /opt/etc/xray/configs/04_outbounds.json "$backup/04_outbounds.json"
cp -p /opt/var/spool/cron/crontabs/root "$backup/root.crontab"
cp -p /opt/etc/xray/configs/01_log.json "$backup/01_log.json"
# Validate the complete active config; installing monitoring needs no restart.
XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray run -test -confdir /opt/etc/xray/configs > "$backup/validation.log" 2>&1
cp "$stage/home-vpn-log.sh" /opt/sbin/home-vpn-log.new
chmod 755 /opt/sbin/home-vpn-log.new
mv /opt/sbin/home-vpn-log.new /opt/sbin/home-vpn-log
cp "$stage/home-vpn-auto.sh" /opt/sbin/home-vpn-auto.new
chmod 755 /opt/sbin/home-vpn-auto.new
mv /opt/sbin/home-vpn-auto.new /opt/sbin/home-vpn-auto
printf '0\n' > /opt/var/lib/home-vpn-auto/recovery-successes
/opt/sbin/home-vpn-log event "monitor_installed backup=$backup"
/opt/sbin/home-vpn-log sample
echo "Backup: $backup"
/opt/sbin/home-vpn-auto status
REMOTE
