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
umask 077
stage=$1
stamp=$2
backup=/opt/var/backups/blanc-auto-install-$stamp
check_dir=/tmp/blanc-auto-validate-$stamp
priority=0
if [ -x /opt/sbin/home-vpn-auto ]; then
  priority=1
  tries=0
  until mkdir /tmp/home-vpn-auto.lock 2>/dev/null; do
    tries=$((tries + 1))
    [ "$tries" -lt 90 ] || { echo 'Personal VPN manager busy; no changes'; exit 1; }
    sleep 1
  done
  trap 'rmdir /tmp/home-vpn-auto.lock 2>/dev/null || true; rm -rf "$stage" "$check_dir"' EXIT
  [ ! -d /tmp/blanc-auto.lock ] || { echo 'Reserve selector busy; no changes'; exit 1; }
fi
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
if [ "$priority" = 1 ]; then
  # Update the private pool, then promote only a separately probed node into
  # the reserve-blanc outbound. Keep the current priority selection unchanged.
  expected_ip=$(cat /opt/var/lib/home-vpn-auto/expected-egress 2>/dev/null || true)
  [ -n "$expected_ip" ] || { echo 'Private expected-egress is missing; reserve update aborted.'; exit 1; }
  for code in ee ch se fi pl lt nl; do rm -f "/opt/etc/xray/blanc-pool/$code.json"; done
  cp -p "$stage"/*.json /opt/etc/xray/blanc-pool/
  date +%s > /opt/var/lib/blanc-auto/pool-updated

  probe_candidate() {
    probe_candidate_file=$1
    probe_candidate_code=$2
    probe_port=38122
    while [ "$probe_port" -lt 38140 ]; do
      probe_port_hex=$(printf '%04X' "$probe_port")
      if ! awk -v p="$probe_port_hex" 'NR>1 { split($2,a,":"); if (a[2]==p && $4=="0A") found=1 } END { exit !found }' /proc/net/tcp; then
        break
      fi
      probe_port=$((probe_port + 1))
    done
    [ "$probe_port" -lt 38140 ] || return 1
    probe_dir="$stage/probe-$probe_candidate_code"
    mkdir -m 700 "$probe_dir"
    jq --argjson port "$probe_port" --slurpfile c "$probe_candidate_file" -n \
      '{log:{loglevel:"warning"},
        inbounds:[{tag:"blanc-health-probe",listen:"127.0.0.1",port:$port,protocol:"socks",settings:{auth:"noauth",udp:false}}],
        outbounds:[($c[0].outbounds[] | select(.tag=="vless-reality" and .protocol=="vless"))],
        routing:{domainStrategy:"AsIs",rules:[{type:"field",inboundTag:["blanc-health-probe"],outboundTag:"vless-reality"}]}}' \
      > "$probe_dir/config.json"
    if ! XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -test -config "$probe_dir/config.json" >/dev/null 2>&1; then
      rm -rf "$probe_dir"
      return 1
    fi
    XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -config "$probe_dir/config.json" >"$probe_dir/xray.log" 2>&1 &
    probe_pid=$!
    sleep 1
    probe_youtube=$(curl --proxy "socks5h://127.0.0.1:$probe_port" -sS --connect-timeout 3 --max-time 6 \
      -o /dev/null -w '%{http_code}' https://www.youtube.com/generate_204 2>/dev/null || true)
    probe_cloudflare=$(curl --proxy "socks5h://127.0.0.1:$probe_port" -sS --connect-timeout 3 --max-time 6 \
      -o "$probe_dir/trace" -w '%{http_code}' https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
    probe_egress=$(sed -n 's/^ip=//p' "$probe_dir/trace" 2>/dev/null | head -n 1)
    kill "$probe_pid" 2>/dev/null || true
    wait "$probe_pid" 2>/dev/null || true
    rm -rf "$probe_dir"
    [ "$probe_youtube" = 204 ] && [ "$probe_cloudflare" = 200 ] && \
      [ -n "$probe_egress" ] && [ "$probe_egress" != "$expected_ip" ]
  }

  healthy_candidate=
  healthy_code=
  for code in ch nl se fi pl lt ee; do
    candidate="$stage/$code.json"
    [ -s "$candidate" ] || continue
    if probe_candidate "$candidate" "$code"; then
      healthy_candidate=$candidate
      healthy_code=$code
      break
    fi
  done
  [ -n "$healthy_candidate" ] || {
    echo 'Fresh Blanc nodes did not pass isolated YouTube and Cloudflare probes; active routing preserved.'
    exit 1
  }

  selected=$(cat /opt/var/lib/home-vpn-auto/selected 2>/dev/null || echo vless-reality)
  case "$selected" in vless-reality|home-h1-reserve|reserve-blanc|reserve-amnezia) ;; *) selected=vless-reality;; esac
  reserve_count=$(jq '[.outbounds[] | select(.tag=="reserve-blanc")] | length' /opt/etc/xray/configs/04_outbounds.json)
  [ "$reserve_count" = 1 ] || { echo 'Expected exactly one reserve-blanc outbound.'; exit 1; }
  fresh_outbound=$(jq -c '[.outbounds[] | select(.tag=="vless-reality" and .protocol=="vless")][0] // empty' "$healthy_candidate")
  [ -n "$fresh_outbound" ] || { echo 'Verified Blanc candidate has no VLESS outbound.'; exit 1; }
  jq --argjson fresh "$fresh_outbound" \
    '(.outbounds[] | select(.tag=="reserve-blanc")) = ($fresh | .tag="reserve-blanc")' \
    /opt/etc/xray/configs/04_outbounds.json > "$stage/04_outbounds.updated.json"
  cp /opt/etc/xray/configs/*.json "$check_dir/"
  cp "$stage/04_outbounds.updated.json" "$check_dir/04_outbounds.json"
  XRAY_LOCATION_ASSET=/opt/etc/xray/dat /opt/sbin/xray run -test -confdir "$check_dir" \
    >/tmp/blanc-reserve-validate-$stamp.log 2>&1

  primary_expected=
  case "$selected" in vless-reality|home-h1-reserve) primary_expected=$expected_ip;; esac
  check_socks() {
    check_port=$1
    check_expected=$2
    check_distinct=$3
    check_youtube=$(curl --proxy "socks5h://127.0.0.1:$check_port" -sS --connect-timeout 5 --max-time 8 \
      -o /dev/null -w '%{http_code}' https://www.youtube.com/generate_204 2>/dev/null || true)
    check_cloudflare=$(curl --proxy "socks5h://127.0.0.1:$check_port" -sS --connect-timeout 5 --max-time 8 \
      -o "$stage/check-trace" -w '%{http_code}' https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
    check_egress=$(sed -n 's/^ip=//p' "$stage/check-trace" 2>/dev/null | head -n 1)
    [ "$check_youtube" = 204 ] && [ "$check_cloudflare" = 200 ] && [ -n "$check_egress" ] || return 1
    [ -z "$check_expected" ] || [ "$check_egress" = "$check_expected" ] || return 1
    [ "$check_distinct" != yes ] || [ "$check_egress" != "$expected_ip" ]
  }

  cp -p "$stage/04_outbounds.updated.json" /opt/etc/xray/configs/04_outbounds.json.next
  mv /opt/etc/xray/configs/04_outbounds.json.next /opt/etc/xray/configs/04_outbounds.json
  restart_rc=0
  XKEEN_DETACHED=1 xkeen -restart >/dev/null 2>&1 || restart_rc=1
  if [ "$restart_rc" = 0 ]; then
    selector_rc=1
    tries=0
    while [ "$tries" -lt 10 ]; do
      if /opt/sbin/xray api bo --server=127.0.0.1:10085 -b home-priority "$selected" >/dev/null 2>&1; then
        selector_rc=0
        break
      fi
      sleep 1
      tries=$((tries + 1))
    done
    [ "$selector_rc" = 0 ] || restart_rc=1
  fi
  sleep 2
  if [ "$restart_rc" != 0 ] || ! check_socks 10809 "$primary_expected" no || ! check_socks 10822 '' yes; then
    cp -p "$backup/04_outbounds.json" /opt/etc/xray/configs/04_outbounds.json.restore
    mv /opt/etc/xray/configs/04_outbounds.json.restore /opt/etc/xray/configs/04_outbounds.json
    XKEEN_DETACHED=1 xkeen -restart >/dev/null 2>&1 || true
    sleep 3
    /opt/sbin/xray api bo --server=127.0.0.1:10085 -b home-priority "$selected" >/dev/null 2>&1 || true
    echo 'Post-update checks failed; restored the previous outbound and selected route.'
    exit 1
  fi

  rm -f /opt/var/lib/blanc-auto/enabled /opt/var/lib/blanc-auto/needs-refresh
  date +%s > /opt/var/lib/blanc-auto/pool-updated
  echo healthy > /opt/var/lib/home-vpn-auto/reserve-blanc
  date +%s > /opt/var/lib/home-vpn-auto/last-reserve-check
  echo "Installed and verified Blanc reserve country=$healthy_code; selected route preserved=$selected; backup=$backup"
  exit 0
fi
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
  BLANC_AUTO_FRESH_POOL=1 /opt/sbin/blanc-auto force
fi
rm -rf "$stage" "$check_dir"
/opt/sbin/blanc-auto status
echo "Backup: $backup"
REMOTE
