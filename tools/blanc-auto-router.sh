#!/bin/sh

ACTIVE=/opt/etc/xray/configs/04_outbounds.json
POOL=/opt/etc/xray/blanc-pool
STATE=/opt/var/lib/blanc-auto
LOG=/opt/var/log/blanc-auto.log
AMNEZIA=/opt/etc/xray/amnezia-vless.json
ENABLED="$STATE/enabled"
HEALTH="$STATE/health"
NEEDS_REFRESH="$STATE/needs-refresh"
MODE="$STATE/mode"
NEXT_RECOVERY="$STATE/next-blanc-recovery"
LOCK=/tmp/blanc-auto.lock
ORDER="ee ch se fi pl lt nl"
COOLDOWN_SECONDS=1200
RECOVERY_INTERVAL_SECONDS=900
FAILOVER_OPEN_UNTIL="$STATE/failover-open-until"
FAILOVER_FAILURES="$STATE/failover-failures"
FAILOVER_BACKOFF_BASE_SECONDS=1800
FAILOVER_BACKOFF_MAX_SECONDS=21600

mkdir -p "$STATE"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
    size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    if [ "$size" -gt 65536 ]; then
        tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
}

write_now() {
    date '+%s' > "$1"
}

mode_value() {
    value=$(cat "$MODE" 2>/dev/null || true)
    case "$value" in
        blanc|amnezia) printf '%s\n' "$value" ;;
        *) printf 'blanc\n' ;;
    esac
}

set_mode() {
    printf '%s\n' "$1" > "$MODE"
}

read_number() {
    value=$(cat "$1" 2>/dev/null || true)
    case "$value" in
        ''|*[!0-9]*) printf '0\n' ;;
        *) printf '%s\n' "$value" ;;
    esac
}

failover_circuit_open() {
    now=$1
    until=$(read_number "$FAILOVER_OPEN_UNTIL")
    [ "$until" -gt "$now" ]
}

clear_failover_circuit() {
    rm -f "$FAILOVER_OPEN_UNTIL" "$FAILOVER_FAILURES"
}

open_failover_circuit() {
    failures=$(read_number "$FAILOVER_FAILURES")
    failures=$((failures + 1))
    delay=$FAILOVER_BACKOFF_BASE_SECONDS
    i=1
    while [ "$i" -lt "$failures" ]; do
        delay=$((delay * 2))
        if [ "$delay" -ge "$FAILOVER_BACKOFF_MAX_SECONDS" ]; then
            delay=$FAILOVER_BACKOFF_MAX_SECONDS
            break
        fi
        i=$((i + 1))
    done
    printf '%s\n' "$failures" > "$FAILOVER_FAILURES"
    date '+%s' | awk -v add="$delay" '{print $1 + add}' > "$FAILOVER_OPEN_UNTIL"
    log "failover_circuit=open failures=$failures backoff=${delay}s"
}

mark_healthy() {
    printf 'healthy\n' > "$HEALTH"
    printf '0\n' > "$STATE/fails"
    write_now "$STATE/last-check"
    write_now "$STATE/last-ok"
    rm -f "$NEEDS_REFRESH"
    rm -f "$NEXT_RECOVERY"
    clear_failover_circuit
    set_mode blanc
    cp -p "$ACTIVE" "$STATE/last-good.json"
}

mark_fallback_healthy() {
    printf 'fallback\n' > "$HEALTH"
    printf '0\n' > "$STATE/fails"
    write_now "$STATE/last-check"
    write_now "$STATE/last-ok"
    set_mode amnezia
}

mark_warning() {
    printf 'warning\n' > "$HEALTH"
    write_now "$STATE/last-check"
}

mark_degraded() {
    printf 'degraded\n' > "$HEALTH"
    write_now "$STATE/last-check"
    touch "$NEEDS_REFRESH"
}

xkeen_up() {
    xkeen -status 2>/dev/null | grep -q 'в режиме'
}

wait_xkeen() {
    i=0
    while [ "$i" -lt 10 ]; do
        sleep 1
        xkeen_up && return 0
        i=$((i + 1))
    done
    return 1
}

start_xkeen() {
    xkeen -start >/dev/null 2>&1 || true
    wait_xkeen && return 0
    xkeen -stop >/dev/null 2>&1 || true
    sleep 3
    xkeen -start >/dev/null 2>&1 || true
    wait_xkeen
}

probe() {
    xkeen_up || return 1
    yt=$(curl --proxy socks5h://127.0.0.1:10808 -sS -o /dev/null \
        --connect-timeout 5 --max-time 10 -w '%{http_code}' \
        https://www.youtube.com/generate_204 2>/dev/null || true)
    gpt=$(curl --proxy socks5h://127.0.0.1:10808 -sS -o /dev/null \
        --connect-timeout 5 --max-time 10 -w '%{http_code}' \
        https://chatgpt.com/cdn-cgi/trace 2>/dev/null || true)
    case "$yt:$gpt" in
        2??:2??) return 0 ;;
        *) return 1 ;;
    esac
}

restore_last_good() {
    [ -f "$STATE/last-good.json" ] || return 1
    xkeen -stop >/dev/null 2>&1 || true
    sleep 2
    cp -p "$STATE/last-good.json" "$ACTIVE"
    if start_xkeen; then
        set_mode blanc
        return 0
    fi
    return 1
}

restore_amnezia() {
    [ -s "$AMNEZIA" ] || return 1
    xkeen -stop >/dev/null 2>&1 || true
    sleep 2
    cp -p "$AMNEZIA" "$ACTIVE"
    start_xkeen
}

validate_candidate() {
    candidate=$1
    check_dir="/tmp/blanc-auto-validate-$$"
    rm -rf "$check_dir"
    mkdir -p "$check_dir"
    cp -a /opt/etc/xray/configs/. "$check_dir/"
    cp -p "$candidate" "$check_dir/04_outbounds.json"
    if XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray convert pb \
        -outpbfile /tmp/blanc-auto-check-$$.pb "$check_dir"/*.json \
        >/tmp/blanc-auto-check-$$.log 2>&1; then
        rm -rf "$check_dir" /tmp/blanc-auto-check-$$.pb /tmp/blanc-auto-check-$$.log
        return 0
    fi
    rm -rf "$check_dir"
    return 1
}

activate_amnezia() {
    [ -s "$AMNEZIA" ] || return 1
    [ "$(mode_value)" = "amnezia" ] || cp -p "$ACTIVE" "$STATE/blanc-last-good.json"
    if ! validate_candidate "$AMNEZIA"; then
        log "amnezia config_invalid"
        return 1
    fi
    xkeen -stop >/dev/null 2>&1 || true
    sleep 2
    cp -p "$AMNEZIA" "$ACTIVE"
    if start_xkeen && probe; then
        touch "$NEEDS_REFRESH"
        date '+%s' | awk -v add="$RECOVERY_INTERVAL_SECONDS" '{print $1 + add}' > "$NEXT_RECOVERY"
        mark_fallback_healthy
        log "amnezia healthy fallback activated"
        return 0
    fi

    if [ -f "$STATE/blanc-last-good.json" ]; then
        xkeen -stop >/dev/null 2>&1 || true
        sleep 2
        cp -p "$STATE/blanc-last-good.json" "$ACTIVE"
        start_xkeen || true
    fi
    return 1
}

try_blanc_recovery() {
    force=$1
    now=$(date '+%s')
    fresh_pool=${BLANC_AUTO_FRESH_POOL:-0}
    next=$(cat "$NEXT_RECOVERY" 2>/dev/null || echo 0)
    if [ "$fresh_pool" != "1" ] && failover_circuit_open "$now"; then
        log "blanc_recovery_skipped circuit_open"
        return 1
    fi
    if [ "$fresh_pool" != "1" ] && [ "$now" -lt "$next" ]; then
        return 0
    fi
    date '+%s' | awk -v add="$RECOVERY_INTERVAL_SECONDS" '{print $1 + add}' > "$NEXT_RECOVERY"

    current=$(cat "$STATE/current" 2>/dev/null || true)
    if [ -n "$current" ] && try_country "$current"; then
        log "blanc recovered country=$current"
        return 0
    fi
    if try_pool 0; then
        log "blanc recovered from pool"
        return 0
    fi

    if restore_amnezia && probe; then
        mark_fallback_healthy
        log "blanc recovery failed; amnezia remains healthy"
        return 0
    fi
    mark_degraded
    log "blanc recovery failed; amnezia restore failed"
    return 1
}

try_country() {
    code=$1
    candidate="$POOL/$code.json"
    [ -f "$candidate" ] || return 1

    cp -p "$ACTIVE" "$STATE/pre-switch.json"
    xkeen -stop >/dev/null 2>&1 || true
    sleep 2
    cp -p "$candidate" "$ACTIVE"

    if ! validate_candidate "$candidate"; then
        log "country=$code config_invalid"
        cp -p "$STATE/pre-switch.json" "$ACTIVE"
        start_xkeen || true
        return 1
    fi

    if start_xkeen && probe; then
        printf '%s\n' "$code" > "$STATE/current"
        mark_healthy
        date '+%s' | awk -v add="$COOLDOWN_SECONDS" '{print $1 + add}' > "$STATE/cooldown-until"
        log "country=$code healthy switched"
        return 0
    fi

    log "country=$code unhealthy"
    xkeen -stop >/dev/null 2>&1 || true
    sleep 2
    cp -p "$STATE/pre-switch.json" "$ACTIVE"
    start_xkeen || true
    return 1
}

try_pool() {
    include_current=${1:-0}
    current=$(cat "$STATE/current" 2>/dev/null || true)
    for code in $ORDER; do
        if [ "$include_current" != "1" ] && [ "$code" = "$current" ]; then
            continue
        fi
        if try_country "$code"; then
            return 0
        fi
    done
    return 1
}

run_check() {
    force=${1:-0}
    fresh_pool=${BLANC_AUTO_FRESH_POOL:-0}
    [ -f "$ENABLED" ] || [ "$force" = "1" ] || return 0
    if ! mkdir "$LOCK" 2>/dev/null; then
        log "check_skipped lock_busy"
        return 75
    fi
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

    mode=$(mode_value)
    if [ "$mode" = "amnezia" ]; then
        if ! probe; then
            log "amnezia_probe_failed"
            if ! restore_amnezia || ! probe; then
                mark_degraded
                log "amnezia_failed health=degraded"
                return 1
            fi
            mark_fallback_healthy
        fi
        try_blanc_recovery "$force"
        return $?
    fi

    now=$(date '+%s')
    cooldown=$(cat "$STATE/cooldown-until" 2>/dev/null || echo 0)
    if [ "$fresh_pool" != "1" ] && failover_circuit_open "$now"; then
        if probe; then
            mark_healthy
            return 0
        fi
        mark_warning
        log "probe_failed circuit_open; failover_skipped"
        return 1
    fi
    if [ "$fresh_pool" != "1" ] && [ "$now" -lt "$cooldown" ]; then
        return 0
    fi

    if probe; then
        mark_healthy
        return 0
    fi

    fails=$(cat "$STATE/fails" 2>/dev/null || echo 0)
    fails=$((fails + 1))
    printf '%s\n' "$fails" > "$STATE/fails"
    mark_warning
    log "probe_failed count=$fails"
    if [ "$fresh_pool" != "1" ] && [ "$fails" -lt 2 ]; then
        return 1
    fi

    try_pool "$force" && return 0

    if restore_last_good && probe; then
        restored=up
    else
        restored=failed
    fi
    if [ "$restored" = "up" ]; then
        mark_healthy
        log "all_candidates_failed restored_last_good=healthy"
        return 0
    fi

    open_failover_circuit
    if activate_amnezia; then
        return 0
    fi

    mark_degraded
    date '+%s' | awk -v add="$COOLDOWN_SECONDS" '{print $1 + add}' > "$STATE/cooldown-until"
    log "all_candidates_failed restored_last_good=$restored health=degraded needs_refresh=1"
    return 1
}

adopt_active() {
    code=${1:-}
    case "$code" in
        ee|ch|se|fi|pl|lt|nl) ;;
        *) echo "Unknown country code: $code"; return 2 ;;
    esac
    if ! probe; then
        mark_degraded
        log "adopt_failed country=$code probe_failed"
        return 1
    fi
    mkdir -p "$POOL"
    cp -p "$ACTIVE" "$POOL/$code.json"
    printf '%s\n' "$code" > "$STATE/current"
    mark_healthy
    date '+%s' | awk -v add="$COOLDOWN_SECONDS" '{print $1 + add}' > "$STATE/cooldown-until"
    log "country=$code healthy adopted"
}

case "${1:-status}" in
    on)
        touch "$ENABLED"
        printf '0\n' > "$STATE/fails"
        echo "Blanc auto: ON"
        ;;
    off)
        rm -f "$ENABLED"
        echo "Blanc auto: OFF (XKeen state unchanged)"
        ;;
    test)
        if probe; then
            if [ "$(mode_value)" = "amnezia" ]; then
                echo "Amnezia fallback: OK"
            else
                echo "Blanc VLESS: OK"
            fi
        else
            if [ "$(mode_value)" = "amnezia" ]; then
                echo "Amnezia fallback: FAIL"
            else
                echo "Blanc VLESS: FAIL"
            fi
            exit 1
        fi
        ;;
    run)
        run_check 0
        ;;
    force)
        run_check 1
        ;;
    adopt)
        adopt_active "${2:-}"
        ;;
    needs-refresh)
        if [ -f "$NEEDS_REFRESH" ]; then
            echo "Blanc refresh: REQUIRED"
            exit 0
        fi
        echo "Blanc refresh: not required"
        exit 1
        ;;
    mode)
        mode_value
        ;;
    recover)
        if [ "$(mode_value)" = "amnezia" ]; then
            if BLANC_AUTO_FRESH_POOL=1 try_blanc_recovery 1; then
                echo "Blanc recovery check finished; mode=$(mode_value)"
            else
                echo "Blanc recovery failed; mode=$(mode_value)"
                exit 1
            fi
        elif restore_last_good && probe; then
            mark_healthy
            echo "Last-good restored; XKeen: UP"
        else
            mark_degraded
            echo "Last-good restore failed"
            exit 1
        fi
        ;;
    status)
        if [ -f "$ENABLED" ]; then enabled=ON; else enabled=OFF; fi
        current=$(cat "$STATE/current" 2>/dev/null || echo unknown)
        mode=$(mode_value)
        fails=$(cat "$STATE/fails" 2>/dev/null || echo 0)
        health=$(cat "$HEALTH" 2>/dev/null || echo unknown)
        last_check=$(cat "$STATE/last-check" 2>/dev/null || echo never)
        last_ok=$(cat "$STATE/last-ok" 2>/dev/null || echo never)
        if [ -f "$NEEDS_REFRESH" ]; then refresh=required; else refresh=no; fi
        if xkeen_up; then xstatus=UP; else xstatus=DOWN; fi
        now=$(date '+%s')
        if failover_circuit_open "$now"; then breaker=OPEN; else breaker=CLOSED; fi
        echo "Blanc auto: $enabled; XKeen: $xstatus; mode: $mode; country: $current; health: $health; failures: $fails; refresh: $refresh; breaker: $breaker; last_check: $last_check; last_ok: $last_ok"
        tail -n 5 "$LOG" 2>/dev/null || true
        ;;
    *)
        echo "Usage: blanc-auto on|off|status|test|run|force|adopt CODE|needs-refresh|mode|recover"
        exit 2
        ;;
esac
