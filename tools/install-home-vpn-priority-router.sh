#!/bin/sh
# Run on router with private generated JSON and scripts in /tmp/priority-stage.
set -eu
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
stage=/tmp/priority-stage
state=/opt/var/lib/home-vpn-auto
lock=/tmp/home-vpn-auto.lock
if [ -d "$lock" ]; then
    [ "$(cat "$lock/owner" 2>/dev/null)" = codex-hardening ] || exit 1
else
    mkdir "$lock"
fi
trap 'rm -f "$lock/owner"; rmdir "$lock" 2>/dev/null || true' EXIT
[ ! -d /tmp/blanc-auto.lock ] || exit 1
umask 077
backup=/opt/var/backups/home-vpn-priority-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$backup/configs" "$stage/check"
cp /opt/etc/xray/configs/*.json "$backup/configs/"
cp -a "$state" "$backup/state"
cp -p /opt/sbin/home-vpn-auto "$backup/home-vpn-auto"
cp -p /opt/etc/xray/home-vpn.json "$backup/home-vpn.json"
cp -p /opt/etc/xray/home-vpn-probe.json "$backup/home-vpn-probe.json"
if [ -f /opt/sbin/home-vpn-priority ]; then cp -p /opt/sbin/home-vpn-priority "$backup/home-vpn-priority"; fi
cp -p /opt/var/spool/cron/crontabs/root "$backup/root.crontab"
cp /opt/etc/xray/configs/*.json "$stage/check/"
cp "$stage"/04_outbounds.json "$stage"/05_routing.json "$stage"/07_home_api.json "$stage/check/"
XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray run -test -confdir "$stage/check" > "$backup/validation.log" 2>&1
sh -n "$stage/home-vpn-auto.sh"
sh -n "$stage/home-vpn-priority.sh"
xray run -test -config "$stage/home-vpn-probe.json" > "$backup/probe-validation.log" 2>&1
cp "$stage/home-vpn.json" /opt/etc/xray/home-vpn.json
cp "$stage/home-vpn-probe.json" /opt/etc/xray/home-vpn-probe.json
cp "$stage"/04_outbounds.json "$stage"/05_routing.json "$stage"/07_home_api.json /opt/etc/xray/configs/
cp "$stage/home-vpn-auto.sh" /opt/sbin/home-vpn-auto
cp "$stage/home-vpn-priority.sh" /opt/sbin/home-vpn-priority
chmod 755 /opt/sbin/home-vpn-auto /opt/sbin/home-vpn-priority
echo vless-reality > "$state/selected"
echo home > "$state/mode"
echo 0 > "$state/fails"
echo 0 > "$state/recovery-successes"
date +%s > "$state/last-reserve-check"
echo unavailable > "$state/reserve-blanc"
echo unavailable > "$state/reserve-amnezia"
home-vpn-log incident priority_api_install > "$backup/incident-path"
rc=0
XKEEN_DETACHED=1 xkeen -restart >/dev/null 2>&1 || rc=$?
sleep 3
if [ "$rc" = 0 ] && xray api bo --server=127.0.0.1:10085 -b home-priority vless-reality > "$backup/api-check.log" 2>&1; then
    ip=$(curl --proxy socks5h://127.0.0.1:10809 -sS --connect-timeout 8 --max-time 12 \
        https://www.cloudflare.com/cdn-cgi/trace | sed -n 's/^ip=//p') || ip=failed
    code=$(curl --proxy socks5h://127.0.0.1:10809 -sS --connect-timeout 8 --max-time 12 \
        -o /dev/null -w '%{http_code}' https://www.youtube.com/) || code=failed
else ip=failed; code=failed; fi
if [ "$ip" = 185.234.9.26 ] && [ "$code" = 200 ]; then
    touch "$state/api-enabled"
    home-vpn-log result "$(cat "$backup/incident-path")" "priority_api_installed ip=$ip youtube=$code backup=$backup"
    echo "Installed with backup=$backup; egress=$ip youtube=$code"
else
    rm -f /opt/etc/xray/configs/07_home_api.json
    cp "$backup/configs/"*.json /opt/etc/xray/configs/
    cp "$backup/home-vpn-auto" /opt/sbin/home-vpn-auto
    cp "$backup/home-vpn.json" /opt/etc/xray/home-vpn.json
    cp "$backup/home-vpn-probe.json" /opt/etc/xray/home-vpn-probe.json
    if [ -f "$backup/home-vpn-priority" ]; then cp "$backup/home-vpn-priority" /opt/sbin/home-vpn-priority; else rm -f /opt/sbin/home-vpn-priority; fi
    rm -f "$state/api-enabled"
    cp -a "$backup/state/." "$state/"
    XKEEN_DETACHED=1 xkeen -restart >/dev/null 2>&1
    home-vpn-log result "$(cat "$backup/incident-path")" 'priority_api_install_failed restored_backup'
    exit 1
fi
