#!/bin/sh

ACTIVE=/opt/etc/xray/configs/04_outbounds.json
POOL=/opt/etc/xray/blanc-pool
STATE=/opt/var/lib/blanc-auto
LOG=/opt/var/log/blanc-auto.log
ENABLED="$STATE/enabled"
LOCK=/tmp/blanc-auto.lock
ORDER="ch se fi pl lt nl"
COOLDOWN_SECONDS=1200

mkdir -p "$STATE"

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
    size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    if [ "$size" -gt 65536 ]; then
        tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
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
    xkeen -start >/dev/null 2>&1 || true
    wait_xkeen
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
        xkeen -start >/dev/null 2>&1 || true
        wait_xkeen || true
        return 1
    fi

    xkeen -start >/dev/null 2>&1 || true
    if wait_xkeen && probe; then
        cp -p "$ACTIVE" "$STATE/last-good.json"
        printf '%s\n' "$code" > "$STATE/current"
        printf '0\n' > "$STATE/fails"
        date '+%s' | awk -v add="$COOLDOWN_SECONDS" '{print $1 + add}' > "$STATE/cooldown-until"
        log "country=$code healthy switched"
        return 0
    fi

    log "country=$code unhealthy"
    xkeen -stop >/dev/null 2>&1 || true
    sleep 2
    cp -p "$STATE/pre-switch.json" "$ACTIVE"
    xkeen -start >/dev/null 2>&1 || true
    wait_xkeen || true
    return 1
}

run_check() {
    [ -f "$ENABLED" ] || return 0
    mkdir "$LOCK" 2>/dev/null || return 0
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT INT TERM

    now=$(date '+%s')
    cooldown=$(cat "$STATE/cooldown-until" 2>/dev/null || echo 0)
    [ "$now" -ge "$cooldown" ] || return 0

    if probe; then
        printf '0\n' > "$STATE/fails"
        cp -p "$ACTIVE" "$STATE/last-good.json"
        return 0
    fi

    fails=$(cat "$STATE/fails" 2>/dev/null || echo 0)
    fails=$((fails + 1))
    printf '%s\n' "$fails" > "$STATE/fails"
    log "probe_failed count=$fails"
    [ "$fails" -ge 2 ] || return 1

    current=$(cat "$STATE/current" 2>/dev/null || true)
    for code in $ORDER; do
        [ "$code" = "$current" ] && continue
        if try_country "$code"; then
            return 0
        fi
    done

    restore_last_good || true
    printf '0\n' > "$STATE/fails"
    date '+%s' | awk -v add="$COOLDOWN_SECONDS" '{print $1 + add}' > "$STATE/cooldown-until"
    log "all_candidates_failed restored_last_good"
    return 1
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
        run_check
        ;;
    status)
        if [ -f "$ENABLED" ]; then enabled=ON; else enabled=OFF; fi
        current=$(cat "$STATE/current" 2>/dev/null || echo unknown)
        fails=$(cat "$STATE/fails" 2>/dev/null || echo 0)
        if xkeen_up; then xstatus=UP; else xstatus=DOWN; fi
        echo "Blanc auto: $enabled; XKeen: $xstatus; country: $current; failures: $fails"
        tail -n 5 "$LOG" 2>/dev/null || true
        ;;
    *)
        echo "Usage: blanc-auto on|off|status|test|run"
        exit 2
        ;;
esac
