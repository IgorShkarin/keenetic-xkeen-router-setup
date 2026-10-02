#!/bin/sh
# Run on router after independent XHTTP validation. Candidate JSON stays private.
set -eu
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
lock=/tmp/home-vpn-auto.lock
state=/opt/var/lib/home-vpn-auto
backup=/opt/var/backups/home-vpn-xhttp-20261002
attempt=0
until mkdir "$lock" 2>/dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 90 ] || exit 1
    sleep 2
done
trap 'rmdir "$lock"' EXIT INT TERM
[ ! -d /tmp/blanc-auto.lock ] || exit 1
[ ! -e "$backup" ] || { echo 'Backup exists: refusing to overwrite'; exit 1; }
umask 077
mkdir -p "$backup"
cp -p /opt/etc/xray/home-vpn.json "$backup/home-vpn.json"
cp -p /opt/etc/xray/home-vpn-probe.json "$backup/home-vpn-probe.json"
cp -p /opt/etc/xray/configs/04_outbounds.json "$backup/04_outbounds.json"
cp -p "$state/mode" "$backup/mode"
archive=$(home-vpn-log incident transport_repair_xhttp)
cp /tmp/home-vpn.json.xhttp /opt/etc/xray/home-vpn.json
cp /tmp/home-vpn-probe-xhttp.json /opt/etc/xray/home-vpn-probe.json
cp /opt/etc/xray/home-vpn.json /opt/etc/xray/configs/04_outbounds.json
restart_rc=0
XKEEN_DETACHED=1 xkeen -restart >/dev/null 2>&1 || restart_rc=$?
sleep 3
ip=$(curl --proxy socks5h://127.0.0.1:10809 -sS --connect-timeout 8 --max-time 12 \
    https://www.cloudflare.com/cdn-cgi/trace | sed -n 's/^ip=//p') || ip=failed
code=$(curl --proxy socks5h://127.0.0.1:10809 -sS --connect-timeout 8 --max-time 12 \
    -o /dev/null -w '%{http_code}' https://www.youtube.com/) || code=failed
if [ "$restart_rc" = 0 ] && [ "$ip" = 185.234.9.26 ] && [ "$code" = 200 ]; then
    echo home > "$state/mode"
    echo 0 > "$state/fails"
    echo 0 > "$state/recovery-successes"
    sha256sum /opt/etc/xray/configs/04_outbounds.json | awk '{print $1}' > "$state/active-signature"
    home-vpn-log result "$archive" "xhttp_repair_success ip=$ip youtube=$code"
    echo "home restored: ip=$ip youtube=$code backup=$backup"
else
    cp -p "$backup/home-vpn.json" /opt/etc/xray/home-vpn.json
    cp -p "$backup/home-vpn-probe.json" /opt/etc/xray/home-vpn-probe.json
    cp -p "$backup/04_outbounds.json" /opt/etc/xray/configs/04_outbounds.json
    cp -p "$backup/mode" "$state/mode"
    XKEEN_DETACHED=1 xkeen -restart >/dev/null 2>&1
    home-vpn-log result "$archive" "xhttp_repair_rolled_back ip=$ip youtube=$code"
    exit 1
fi
