#!/bin/sh
# Bounded private diagnostics; no configuration files or credentials are copied.
PATH=${HOME_VPN_PATH:-/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin}
ROOT=${HOME_VPN_ROOT:-/opt}
BASE=$ROOT/var/log/home-vpn
STATE=$ROOT/var/lib/home-vpn-auto
RING=$BASE/rolling
SAVED=$BASE/incidents
umask 077
mkdir -p "$RING" "$SAVED"
now=$(date +%s)
minute=$((now / 60))

prune() {
    for file in "$RING"/*; do
        [ -f "$file" ] || continue
        stamp=${file##*/}; stamp=${stamp%%.*}
        case "$stamp" in ''|*[!0-9]*) continue;; esac
        [ "$stamp" -gt "$((minute - 15))" ] || rm -f "$file"
    done
    # At most eight archives, plus a hard 8 MiB aggregate archive limit.
    count=0; bytes=0
    for file in $(ls -1 "$SAVED"/*.log.gz 2>/dev/null | sort -r); do
        size=$(wc -c < "$file")
        result=${file%.log.gz}.result
        if [ -f "$result" ]; then size=$((size + $(wc -c < "$result"))); fi
        count=$((count + 1)); bytes=$((bytes + size))
        if [ "$count" -gt 8 ] || [ "$bytes" -gt 8388608 ]; then
            rm -f "$file" "$result"
        fi
    done
}

cap_live() {
    file=$1; limit=$2
    [ -f "$file" ] || return 0
    size=$(wc -c < "$file")
    if [ "$size" -gt "$limit" ]; then
        # Preserve the inode used by Xray; do not rotate it out from under its FD.
        tail -c "$limit" "$file" > "$BASE/live-tail.$$"
        cat "$BASE/live-tail.$$" > "$file"
        rm -f "$BASE/live-tail.$$"
    fi
}

sample() {
    {
        printf 'time=%s epoch=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$now"
        for key in mode selected health fails recovery-successes last-recovery last-check last-fallback last-reserve-check home-h1-reserve reserve-blanc reserve-amnezia active-signature; do
            printf '%s=' "$key"; cat "$STATE/$key" 2>/dev/null || printf 'unknown\n'
        done
        printf 'load='; cat /proc/loadavg 2>/dev/null
        sed -n '1,3p' /proc/meminfo 2>/dev/null
    } > "$RING/$minute.state"
    tail -c 49152 "$ROOT/var/log/xray/error.log" > "$RING/$minute.error" 2>/dev/null || :
    tail -c 16384 "$ROOT/var/log/xray/access.log" > "$RING/$minute.access" 2>/dev/null || :
    tail -c 8192 "$STATE/probe.log" > "$RING/$minute.probe" 2>/dev/null || :
    tail -c 4096 "$ROOT/var/log/home-vpn-amnezia.log" > "$RING/$minute.amnezia" 2>/dev/null || :
    cap_live "$ROOT/var/log/xray/error.log" 262144
    cap_live "$ROOT/var/log/xray/access.log" 131072
    prune
}

event() {
    printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$RING/$minute.health"
    size=$(wc -c < "$RING/$minute.health")
    if [ "$size" -gt 8192 ]; then
        tail -c 8192 "$RING/$minute.health" > "$BASE/event-tail.$$"
        mv "$BASE/event-tail.$$" "$RING/$minute.health"
    fi
    prune
}

case "${1:-sample}" in
sample) sample;;
event) shift; event "$*";;
incident)
    shift
    event "incident reason=$*"
    sample
    name=$(date -u '+%Y%m%dT%H%M%SZ')-$$
    archive=$SAVED/$name.log.gz
    {
        printf 'reason=%s\nwindow=preceding 15 minutes, available samples only\n' "$*"
        for file in "$RING"/*; do
            [ -f "$file" ] || continue
            printf '\n--- %s ---\n' "${file##*/}"
            cat "$file"
        done
    } | gzip -c > "$archive"
    prune
    printf '%s\n' "$archive"
    ;;
result)
    archive=$2; shift 2
    case "$archive" in "$SAVED"/*.log.gz)
        [ -f "$archive" ] && printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "${archive%.log.gz}.result"
        ;;
    esac
    event "$*"
    sample
    ;;
status)
    printf 'Rolling window: 15 minutes; archives: 8 max / 8 MiB max\n'
    du -sk "$BASE"
    ls -lt "$SAVED"/*.log.gz 2>/dev/null || :
    ;;
*) exit 2;;
esac
