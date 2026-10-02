#!/bin/sh
# Explicit primary -> Blanc -> Amnezia; changes only new-request routing via API.
PATH=${HOME_VPN_PATH:-/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin}
ROOT=${HOME_VPN_ROOT:-/opt}
TMP=${HOME_VPN_TMP:-/tmp}
STATE=$ROOT/var/lib/home-vpn-auto
DIAG=$ROOT/sbin/home-vpn-log
API=127.0.0.1:10085
LOCK=$TMP/home-vpn-auto.lock
umask 077
mkdir -p "$STATE"
event() { "$DIAG" event "$*"; }
number() { value=$(cat "$STATE/$1" 2>/dev/null); case "$value" in ''|*[!0-9]*) echo 0;; *) echo "$value";; esac; }
port_for() { case "$1" in vless-reality) echo 10821;; home-h1-reserve) echo 10824;; reserve-blanc) echo 10822;; reserve-amnezia) echo 10823;; *) return 1;; esac; }
expected_for() { case "$1" in vless-reality|home-h1-reserve) echo 185.234.9.26;; esac; }
healthy() {
    label=$1; port=$2; expected=$3; strict=${4:-no}
    yt=0; cf=0; ip=unknown
    yt_metrics=$(curl --proxy "socks5h://127.0.0.1:$port" -sS --connect-timeout 5 --max-time 8 \
        -o /dev/null -w '%{http_code} %{time_appconnect} %{time_total}' https://www.youtube.com/generate_204 2>"$STATE/http-error.$$")
    yt_rc=$?; code=${yt_metrics%% *}
    yt_error=$(head -c 160 "$STATE/http-error.$$" | tr '\n' ' ')
    [ "$yt_rc" != 0 ] || [ "$code" != 204 ] || yt=1
    cf_metrics=$(curl --proxy "socks5h://127.0.0.1:$port" -sS --connect-timeout 5 --max-time 8 \
        -o "$STATE/trace.$$" -w '%{http_code} %{time_appconnect} %{time_total}' https://www.cloudflare.com/cdn-cgi/trace 2>"$STATE/http-error.$$")
    cf_rc=$?; code=${cf_metrics%% *}
    cf_error=$(head -c 160 "$STATE/http-error.$$" | tr '\n' ' ')
    if [ "$cf_rc" = 0 ] && [ "$code" = 200 ]; then cf=1; ip=$(sed -n 's/^ip=//p' "$STATE/trace.$$"); fi
    event "check=$label port=$port youtube_ok=$yt cloudflare_ok=$cf egress=$ip yt_rc=$yt_rc yt_http_tls_total=$yt_metrics yt_error=$yt_error cf_rc=$cf_rc cf_http_tls_total=$cf_metrics cf_error=$cf_error"
    [ -z "$expected" ] || [ "$cf" != 1 ] || [ "$ip" = "$expected" ] || return 1
    if [ "$strict" = yes ]; then [ "$yt" = 1 ] && [ "$cf" = 1 ]; else [ "$yt" = 1 ] || [ "$cf" = 1 ]; fi
}
select_target() {
    target=$1
    xray api bo --server="$API" -b home-priority "$target" >"$STATE/api.log" 2>&1
}
switch_to() {
    target=$1; reason=$2; prior=$selected
    expected=$(expected_for "$target")
    healthy "candidate-$target" "$(port_for "$target")" "$expected" yes || return 1
    archive=$("$DIAG" incident "$reason target=$target")
    if select_target "$target" && healthy "post-switch-$target" 10809 "$expected" yes; then
        selected=$target; echo "$selected" > "$STATE/selected"
        case "$selected" in vless-reality|home-h1-reserve) echo home > "$STATE/mode";; *) echo fallback > "$STATE/mode";; esac
        [ "$selected" = vless-reality ] || date +%s > "$STATE/last-fallback"
        echo 0 > "$STATE/fails"; echo 0 > "$STATE/recovery-successes"
        echo healthy > "$STATE/health"
        "$DIAG" result "$archive" "api_switch_success target=$target no_restart=yes"
        return 0
    fi
    select_target "$prior"
    "$DIAG" result "$archive" "api_switch_failed target=$target rolled_back=$prior"
    return 1
}
case "${1:-run}" in
status)
    for key in mode selected health fails recovery-successes last-check home-h1-reserve reserve-blanc reserve-amnezia; do
        printf '%s=' "$key"; cat "$STATE/$key" 2>/dev/null || echo unknown
    done
    "$DIAG" status; exit 0;;
run|recover) ;;
*) exit 2;;
esac
mkdir "$LOCK" 2>/dev/null || exit 0
cleanup() { "$DIAG" sample; rm -f "$STATE/http-error.$$" "$STATE/trace.$$"; rmdir "$LOCK" 2>/dev/null || :; }
trap cleanup EXIT INT TERM
[ ! -d "$TMP/blanc-auto.lock" ] || { event skipped_blanc_lock; exit 0; }
rm -f "$ROOT/var/lib/blanc-auto/enabled"
now=$(date +%s); echo "$now" > "$STATE/last-check"
selected=$(cat "$STATE/selected" 2>/dev/null || echo vless-reality)
case "$selected" in vless-reality|home-h1-reserve|reserve-blanc|reserve-amnezia) ;; *) selected=vless-reality;; esac
# Reapply persisted selection after an unrelated Xray restart. No connection kill.
select_target "$selected" || { event api_unavailable_no_route_change; echo api-error > "$STATE/health"; exit 1; }
expected=$(expected_for "$selected")
if healthy "active-$selected" 10809 "$expected"; then
    echo healthy > "$STATE/health"; echo 0 > "$STATE/fails"
else
    fails=$(number fails); fails=$((fails + 1)); echo "$fails" > "$STATE/fails"
    echo degraded > "$STATE/health"
    if [ "$fails" -ge 2 ]; then
        changed=0
        for target in vless-reality home-h1-reserve reserve-blanc reserve-amnezia; do
            [ "$target" != "$selected" ] || continue
            if switch_to "$target" active_path_failed; then changed=1; break; fi
        done
        [ "$changed" = 1 ] || { event all_paths_unhealthy_keep_current_no_restart; echo all-paths-down > "$STATE/health"; }
    fi
fi
if [ "$selected" != vless-reality ]; then
    last=$(number last-recovery)
    [ $((now - last)) -ge 55 ] || exit 0
    [ $((now - last)) -le 180 ] || echo 0 > "$STATE/recovery-successes"
    echo "$now" > "$STATE/last-recovery"
    if healthy primary-recovery 10821 185.234.9.26 yes; then
        successes=$(number recovery-successes); successes=$((successes + 1)); echo "$successes" > "$STATE/recovery-successes"
        [ "$successes" -lt 3 ] || [ $((now - $(number last-fallback))) -lt 180 ] || switch_to vless-reality stable_primary_recovery
    else echo 0 > "$STATE/recovery-successes"; fi
fi
# Check reserves in advance, not by restarting production to discover dead nodes.
if [ $((now - $(number last-reserve-check))) -ge 300 ]; then
    echo "$now" > "$STATE/last-reserve-check"
    for target in home-h1-reserve reserve-blanc reserve-amnezia; do
        if healthy "$target" "$(port_for "$target")" "$(expected_for "$target")" yes; then value=healthy; else value=unavailable; fi
        echo "$value" > "$STATE/$target"
    done
fi
