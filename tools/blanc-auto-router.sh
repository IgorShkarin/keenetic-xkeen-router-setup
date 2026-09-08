#!/bin/sh

ACTIVE=/opt/etc/xray/configs/04_outbounds.json
POOL=/opt/etc/xray/blanc-pool
STATE=/opt/var/lib/blanc-auto
LOG=/opt/var/log/blanc-auto.log
ENABLED="$STATE/enabled"
HEALTH="$STATE/health"
NEEDS_REFRESH="$STATE/needs-refresh"
LOCK=/tmp/blanc-auto.lock
ORDER="ee ch se fi pl lt nl"
COOLDOWN_SECONDS=1200

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

mark_healthy() {
    printf 'healthy\n' > "$HEALTH"
    printf '0\n' > "$STATE/fails"
    write_now "$STATE/last-check"
    write_now "$STATE/last-ok"
    rm -f "$NEEDS_REFRESH"
    cp -p "$ACTIVE" "$STATE/last-good.json"
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
    start_xkeen
}

try_country() {
    code=$1
    candidate="$POOL/$code.json"
    [ -f "$candidate" ] || return 1

    cp -p "$ACTIVE" "$STATE/pre-switch.json"
    xkeen -stop >/dev/null 2>&1 || true
    sleep 2
    cp -p "$candidate" "$ACTIVE"

    if ! XRAY_LOCATION_ASSET=/opt/etc/xray/dat xray convert pb \
        -outpbfile /tmp/blanc-auto-check.pb /opt/etc/xray/configs/*.json \
        >/tmp/blanc-auto-check.log 2>&1; then
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
    [ -f "$ENABLED" ] || [ "$force" = "1" ] || return 0
    if ! mkdir "$LOCK" 2>/dev/null; then
        log "check_skipped lock_busy"
        return 75
    fi
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

    now=$(date '+%s')
    cooldown=$(cat "$STATE/cooldown-until" 2>/dev/null || echo 0)
    if [ "$force" != "1" ] && [ "$now" -lt "$cooldown" ]; then
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
    if [ "$force" != "1" ] && [ "$fails" -lt 2 ]; then
        return 1
    fi

    try_pool "$force" && return 0

    if restore_last_good; then
        restored=up
    else
        restored=failed
    fi
    if [ "$restored" = "up" ] && probe; then
        mark_healthy
        log "all_candidates_failed restored_last_good=healthy"
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
        if probe; then echo "Blanc VLESS: OK"; else echo "Blanc VLESS: FAIL"; exit 1; fi
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
    recover)
        if restore_last_good && probe; then
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
        fails=$(cat "$STATE/fails" 2>/dev/null || echo 0)
        health=$(cat "$HEALTH" 2>/dev/null || echo unknown)
        last_check=$(cat "$STATE/last-check" 2>/dev/null || echo never)
        last_ok=$(cat "$STATE/last-ok" 2>/dev/null || echo never)
        if [ -f "$NEEDS_REFRESH" ]; then refresh=required; else refresh=no; fi
        if xkeen_up; then xstatus=UP; else xstatus=DOWN; fi
        echo "Blanc auto: $enabled; XKeen: $xstatus; country: $current; health: $health; failures: $fails; refresh: $refresh; last_check: $last_check; last_ok: $last_ok"
        tail -n 5 "$LOG" 2>/dev/null || true
        ;;
    *)
        echo "Usage: blanc-auto on|off|status|test|run|force|adopt CODE|needs-refresh|recover"
        exit 2
        ;;
esac
