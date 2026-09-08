#!/usr/bin/env bash
set -euo pipefail

ROUTER="${XKEEN_ROUTER:-192.168.1.1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${BLANC_REFRESH_STATE_DIR:-${HOME}/Library/Application Support/Blanc Router Monitor}"
STATE_FILE="$STATE_DIR/state"
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=6 "root@$ROUTER")

mkdir -p "$STATE_DIR"

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"VPN на роутере\"" \
    >/dev/null 2>&1 || true
}

read_state() {
  if [[ -f "$STATE_FILE" ]]; then
    tr -d '\r\n' < "$STATE_FILE"
  fi
}

write_state() {
  printf '%s\n' "$1" > "$STATE_FILE"
}

mark_failure() {
  local next="$1" message="$2" previous
  previous="$(read_state)"
  write_state "$next"
  if [[ "$previous" != "$next" ]]; then
    notify "$message"
  fi
}

mark_healthy() {
  write_state healthy
}

if ! "${SSH[@]}" true >/dev/null 2>&1; then
  echo "Router is unreachable over SSH."
  mark_failure router-unreachable "Роутер недоступен по SSH; автоматическая проверка VPN не выполнена."
  exit 1
fi

if "${SSH[@]}" '/opt/sbin/blanc-auto test' >/dev/null 2>&1; then
  mark_healthy
  echo "Router VLESS is healthy; refresh is not needed."
  exit 0
fi

echo "Router VLESS probe failed; handing the first retry to router failover."
"${SSH[@]}" '/opt/sbin/blanc-auto run' >/dev/null 2>&1 || true
if "${SSH[@]}" '/opt/sbin/blanc-auto test' >/dev/null 2>&1; then
  mark_healthy
  notify "VPN автоматически восстановлен через резервный сохранённый узел."
  echo "Router VLESS recovered from the saved pool."
  exit 0
fi

if ! "${SSH[@]}" '/opt/sbin/blanc-auto needs-refresh' >/dev/null 2>&1; then
  write_state warning
  echo "Waiting for the second router-side failure before switching nodes."
  exit 1
fi

echo "Saved nodes are exhausted; refreshing the private Blanc subscription from Keychain."
if "$SCRIPT_DIR/install-blanc-auto.sh" && \
    "${SSH[@]}" '/opt/sbin/blanc-auto test' >/dev/null 2>&1; then
  mark_healthy
  notify "VPN автоматически восстановлен после обновления подписки Blanc."
  echo "Router VLESS recovered after subscription refresh."
  exit 0
fi

mark_failure degraded "VPN на роутере не восстановлен: свежие узлы Blanc не прошли проверку."
echo "Router VLESS remains degraded after subscription refresh." >&2
exit 1
