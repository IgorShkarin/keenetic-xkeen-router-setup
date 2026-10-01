#!/bin/sh
# Priority: personal VPS -> existing Blanc/Amnezia recovery.
PATH=${HOME_VPN_PATH:-/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin}
ROOT=${HOME_VPN_ROOT:-/opt}
TMP=${HOME_VPN_TMP:-/tmp}
STATE=$ROOT/var/lib/home-vpn-auto
ACTIVE=$ROOT/etc/xray/configs/04_outbounds.json
PERSONAL=$ROOT/etc/xray/home-vpn.json
DIAG=$ROOT/sbin/home-vpn-log
LOCK=$TMP/home-vpn-auto.lock
EXPECTED_IP=185.234.9.26
umask 077
mkdir -p "$STATE"
event() { "$DIAG" event "$*"; }
number() {
    value=$(cat "$1" 2>/dev/null)
    case "$value" in ''|*[!0-9]*) echo 0;; *) echo "$value";; esac
}
cleanup() {
    if [ -n "${probe_pid:-}" ]; then kill "$probe_pid" 2>/dev/null; wait "$probe_pid" 2>/dev/null; fi
    if [ -f "$ACTIVE" ]; then sha256sum "$ACTIVE" | awk '{print $1}' > "$STATE/active-signature"; fi
    "$DIAG" sample
    rm -f "$STATE/http-error.$$" "$STATE/trace.$$"
    rmdir "$LOCK" 2>/dev/null || :
}

request() {
    request_port=$1; request_label=$2; request_url=$3; request_body=$4
    metrics=$(curl --proxy "socks5h://127.0.0.1:$request_port" -sS \
        --connect-timeout 8 --max-time 12 -o "$request_body" \
        -w '%{http_code} %{time_connect} %{time_appconnect} %{time_total}' \
        "$request_url" 2>"$STATE/http-error.$$")
    request_rc=$?
    code=${metrics%% *}
    detail=$(head -c 240 "$STATE/http-error.$$" | tr '\n' ' ')
    event "check=$check_label target=$request_label port=$request_port rc=$request_rc http_connect_tls_total=$metrics error=$detail"
    [ "$request_rc" = 0 ] && case "$code" in 2??) return 0;; esac
    return 1
}

healthy() {
    check_label=$1; port=$2; expected=$3; require_both=${4:-no}
    yt=0; cf=0; ip=unknown
    request "$port" youtube https://www.youtube.com/generate_204 /dev/null && yt=1
    request "$port" cloudflare https://www.cloudflare.com/cdn-cgi/trace "$STATE/trace.$$" && cf=1
    if [ "$cf" = 1 ]; then ip=$(sed -n 's/^ip=//p' "$STATE/trace.$$"); fi
    event "check=$check_label youtube_ok=$yt cloudflare_ok=$cf egress=$ip expected=${expected:-any}"
    # A reachable individual site does not justify switching the whole VPN off.
    # A successful trace with a wrong egress, however, is not our private VPN.
    if [ -n "$expected" ] && [ "$cf" = 1 ] && [ "$ip" != "$expected" ]; then return 1; fi
    if [ "$require_both" = yes ]; then
        [ "$yt" = 1 ] && [ "$cf" = 1 ] && [ "$ip" = "$expected" ]
    else
        [ "$yt" = 1 ] || [ "$cf" = 1 ]
    fi
}

switch_to() {
    candidate=$1; target_mode=$2; reason=$3
    check=$TMP/home-vpn-check-$$
    mkdir -p "$check" || return 1
    cp "$ROOT"/etc/xray/configs/*.json "$check/"
    cp "$candidate" "$check/04_outbounds.json" || { rm -rf "$check"; return 1; }
    XRAY_LOCATION_ASSET=$ROOT/etc/xray/dat xray run -test -confdir "$check" >"$STATE/validation.log" 2>&1
    result=$?; rm -rf "$check"
    if [ "$result" != 0 ]; then event "switch_validation_failed target=$target_mode rc=$result"; return 1; fi
    cp -p "$ACTIVE" "$STATE/pre-switch.json" || return 1
    archive=$("$DIAG" incident "$reason target=$target_mode")
    cp -p "$candidate" "$ACTIVE" || return 1
    XKEEN_DETACHED=1 xkeen -restart >/dev/null 2>&1
    restart_rc=$?
    sleep 3
    expected=
    [ "$target_mode" != home ] || expected=$EXPECTED_IP
    if [ "$restart_rc" = 0 ] && healthy "post-switch-$target_mode" 10809 "$expected"; then
        printf '%s\n' "$target_mode" > "$STATE/mode"
        printf '0\n' > "$STATE/fails"
        "$DIAG" result "$archive" "switch_success target=$target_mode reason=$reason"
        logger -t home-vpn-auto "switch_success target=$target_mode reason=$reason"
        return 0
    fi
    # Save post-switch diagnostics before the rollback restart truncates Xray logs.
    "$DIAG" sample
    failure_archive=$("$DIAG" incident "post_switch_failed target=$target_mode restart_rc=$restart_rc")
    if [ "$target_mode" = fallback ]; then
        # Keep the validated fallback as the starting point for Blanc/Amnezia
        # recovery; rolling back to a failed private server would trap us there.
        printf 'fallback\n' > "$STATE/mode"
        "$DIAG" result "$archive" 'fallback_applied_unhealthy continue_pool_recovery'
        "$DIAG" result "$failure_archive" 'continue_pool_recovery'
        return 2
    fi
    cp -p "$STATE/pre-switch.json" "$ACTIVE"
    XKEEN_DETACHED=1 xkeen -restart >/dev/null 2>&1
    rollback_rc=$?
    "$DIAG" result "$archive" "switch_failed target=$target_mode rollback_rc=$rollback_rc"
    "$DIAG" result "$failure_archive" "rolled_back target=$target_mode rollback_rc=$rollback_rc"
    return 1
}

probe_home() {
    nohup xray run -config "$ROOT/etc/xray/home-vpn-probe.json" >"$STATE/probe.log" 2>&1 </dev/null &
    probe_pid=$!
    sleep 1
    if kill -0 "$probe_pid" 2>/dev/null; then
        healthy private-probe 10818 "$EXPECTED_IP" yes
        probe_rc=$?
    else
        event 'private-probe startup_failed'
        probe_rc=1
    fi
    kill "$probe_pid" 2>/dev/null; wait "$probe_pid" 2>/dev/null
    probe_pid=
    return "$probe_rc"
}

case "${1:-run}" in
status)
    printf 'Home VPN mode: '; cat "$STATE/mode" 2>/dev/null || echo unknown
    printf 'Failed checks: '; number "$STATE/fails"
    printf 'Private recovery successes: '; number "$STATE/recovery-successes"
    printf 'Last check epoch: '; number "$STATE/last-check"
    "$DIAG" status
    exit 0;;
run|recover) ;;
*) exit 2;;
esac
mkdir "$LOCK" 2>/dev/null || exit 0
trap cleanup EXIT INT TERM
"$DIAG" sample
[ ! -d "$TMP/blanc-auto.lock" ] || { event skipped_blanc_lock; exit 0; }
# Never run two independent route managers concurrently.
rm -f "$ROOT/var/lib/blanc-auto/enabled"
now=$(date +%s)
printf '%s\n' "$now" > "$STATE/last-check"
mode=$(cat "$STATE/mode" 2>/dev/null || echo fallback)
event "cycle mode=$mode"
previous_signature=$(cat "$STATE/active-signature" 2>/dev/null)
current_signature=$(sha256sum "$ACTIVE" | awk '{print $1}')
if [ -n "$previous_signature" ] && [ "$previous_signature" != "$current_signature" ]; then
    archive=$("$DIAG" incident "external_outbound_change mode=$mode")
    "$DIAG" result "$archive" 'observed_external_outbound_change'
fi
if [ "$mode" = home ]; then
    if ! cmp -s "$ACTIVE" "$PERSONAL"; then
        archive=$("$DIAG" incident external_active_replacement)
        printf 'fallback\n' > "$STATE/mode"
        printf '0\n' > "$STATE/recovery-successes"
        "$DIAG" result "$archive" 'mode=fallback reason=external_active_replacement'
        mode=fallback
    elif healthy active-home 10809 "$EXPECTED_IP"; then
        printf '0\n' > "$STATE/fails"
        exit 0
    else
        fails=$(number "$STATE/fails"); fails=$((fails + 1))
        echo "$fails" > "$STATE/fails"
        event "active_home_failed consecutive=$fails"
        [ "$fails" -ge 2 ] || exit 0
        if switch_to "$STATE/fallback.json" fallback consecutive_primary_failures; then
            mode=fallback
        else
            switch_rc=$?
            if [ "$switch_rc" = 2 ]; then
                mode=fallback
            else
                event 'fallback_switch_failed retry_next_cycle'
                exit 1
            fi
        fi
        date +%s > "$STATE/last-fallback"
        printf '0\n' > "$STATE/recovery-successes"
    fi
fi
if [ "$mode" = fallback ]; then
    if healthy active-fallback 10809 ''; then
        cp -p "$ACTIVE" "$STATE/fallback.json"
    else
        archive=$("$DIAG" incident fallback_pool_recovery)
        XKEEN_DETACHED=1 "$ROOT/sbin/blanc-auto" force
        recovery_rc=$?
        "$DIAG" result "$archive" "fallback_pool_recovery rc=$recovery_rc"
        # Save only an actually working fallback configuration.
        if healthy recovered-fallback 10809 ''; then cp -p "$ACTIVE" "$STATE/fallback.json"; fi
    fi
    # Check the private path once a minute, without touching production routing.
    last=$(number "$STATE/last-recovery")
    [ $((now - last)) -ge 55 ] || { event 'private_probe_skipped same_minute'; exit 0; }
    [ $((now - last)) -le 180 ] || printf '0\n' > "$STATE/recovery-successes"
    echo "$now" > "$STATE/last-recovery"
    if probe_home; then
        successes=$(number "$STATE/recovery-successes"); successes=$((successes + 1))
        echo "$successes" > "$STATE/recovery-successes"
        event "private_recovery_success consecutive=$successes"
        # Two separate cycles and a two-minute cooldown avoid immediate flapping.
        last_fallback=$(number "$STATE/last-fallback")
        if [ "$successes" -ge 2 ] && [ $((now - last_fallback)) -ge 120 ]; then
            switch_to "$PERSONAL" home private_recovered
            printf '0\n' > "$STATE/recovery-successes"
        fi
    else
        printf '0\n' > "$STATE/recovery-successes"
        event 'private_probe_failed stay_on_fallback'
    fi
fi
