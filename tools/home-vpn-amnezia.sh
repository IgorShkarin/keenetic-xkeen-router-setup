#!/bin/sh
# Supervise a loopback-only AWG SOCKS bridge; do not touch system routes.
PATH=/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin
BIN=/opt/bin/home-awg-socks
CONFIG=/opt/etc/home-vpn/amnezia.conf
PID=/opt/var/run/home-vpn-amnezia.pid
LOG=/opt/var/log/home-vpn-amnezia.log
LOCK=/tmp/home-vpn-amnezia.lock
umask 077
mkdir -p /opt/var/run
running() {
    p=$(cat "$PID" 2>/dev/null) || return 1
    case "$p" in ''|*[!0-9]*) return 1;; esac
    [ -r "/proc/$p/cmdline" ] && tr '\000' ' ' < "/proc/$p/cmdline" | grep -q "^$BIN "
}
case "${1:-ensure}" in
status) if running; then echo "running pid=$p listener=127.0.0.1:10932"; else echo stopped; exit 1; fi; exit 0;;
stop) if running; then kill "$p"; fi; rm -f "$PID"; exit 0;;
ensure|start) ;;
*) exit 2;;
esac
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
[ -x "$BIN" ] && [ -r "$CONFIG" ] || exit 1
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 32768 ]; then
    tail -c 16384 "$LOG" > "$LOG.tmp" && cat "$LOG.tmp" > "$LOG"; rm -f "$LOG.tmp"
fi
running && exit 0
GOMAXPROCS=2 GOMEMLIMIT=64MiB nohup "$BIN" -config "$CONFIG" -listen 127.0.0.1:10932 >> "$LOG" 2>&1 < /dev/null &
echo $! > "$PID"
sleep 1
running
