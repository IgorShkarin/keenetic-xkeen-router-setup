#!/usr/bin/env bash
set -euo pipefail

ROUTER="${XKEEN_ROUTER:-192.168.1.1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="${BLANC_REFRESH_STATE_DIR:-${HOME}/Library/Application Support/Blanc Router Monitor}"
STATE_FILE="$STATE_DIR/state"
AMNEZIA_REFRESH_STAMP="$STATE_DIR/amnezia-last-refresh"
AMNEZIA_REFRESH_COOLDOWN=1800
BLANC_REFRESH_ATTEMPT_STAMP="$STATE_DIR/blanc-last-refresh-attempt"
BLANC_REFRESH_SUCCESS_STAMP="$STATE_DIR/blanc-last-refresh"
BLANC_REFRESH_RETRY_COOLDOWN=1800
BLANC_REFRESH_SUCCESS_COOLDOWN=21600
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

refresh_gate() {
  local stamp_file="$1" cooldown="$2" now last
  now="$(date +%s)"
  last="$(cat "$stamp_file" 2>/dev/null || echo 0)"
  if [[ "$last" =~ ^[0-9]+$ ]] && (( now - last < cooldown )); then
    return 1
  fi
  return 0
}

mark_refresh_attempt() {
  local stamp_file="$1"
  date +%s > "$stamp_file"
}

check_personal_certificate() {
  local stamp="$STATE_DIR/certificate-last-check" expiry expiry_epoch remaining previous server_host certificate_name
  server_host="${HOME_VPN_SSH_HOST:-$(cat "$STATE_DIR/home-vpn-server-host" 2>/dev/null || true)}"
  [[ -n "$server_host" ]] || return 0
  [[ "$server_host" != *[!a-zA-Z0-9.@_-]* ]] || return 0
  certificate_name="${HOME_VPN_CERT_NAME:-${server_host#*@}}"
  [[ "$certificate_name" != *[!a-zA-Z0-9._-]* ]] || return 0
  refresh_gate "$stamp" 3600 || return 0
  mark_refresh_attempt "$stamp"
  expiry="$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$server_host" \
    "openssl x509 -in /etc/letsencrypt/live/$certificate_name/fullchain.pem -noout -enddate" \
    2>/dev/null)" || { echo "Certificate expiry check unavailable."; return 0; }
  expiry_epoch="$(TZ=UTC date -j -f '%b %e %T %Y %Z' "${expiry#notAfter=}" +%s 2>/dev/null)" || return 0
  remaining=$((expiry_epoch - $(date +%s)))
  previous="$(cat "$STATE_DIR/certificate-health" 2>/dev/null || true)"
  if (( remaining < 172800 )); then
    printf 'expiry-warning\n' > "$STATE_DIR/certificate-health"
    [[ "$previous" == expiry-warning ]] || notify "Сертификат нашего VPN истекает менее чем через 48 часов; нужно проверить продление."
  else
    printf 'healthy\n' > "$STATE_DIR/certificate-health"
  fi
  echo "Personal VPN certificate remaining_seconds=$remaining"
}

if ! "${SSH[@]}" true >/dev/null 2>&1; then
  echo "Router is unreachable over SSH."
  mark_failure router-unreachable "Роутер недоступен по SSH; автоматическая проверка VPN не выполнена."
  exit 1
fi

# The personal-VPN manager owns active routing. Refresh reserves only; never
# invoke the legacy selector or treat a healthy primary as healthy Blanc.
if "${SSH[@]}" 'test -x /opt/sbin/home-vpn-auto' >/dev/null 2>&1; then
  check_personal_certificate
  reserve_health="$("${SSH[@]}" '/opt/sbin/home-vpn-auto status' 2>/dev/null | sed -n 's/^reserve-blanc=//p')"
  case "$reserve_health" in
    healthy)
      mark_healthy
      echo "Blanc reserve is healthy; no subscription refresh needed."
      exit 0
      ;;
    unavailable) ;;
    *)
      mark_failure warning "Не удалось прочитать здоровье резерва Blanc; обновление не запускалось."
      echo "Blanc reserve status unavailable; no subscription refresh attempted." >&2
      exit 1
      ;;
  esac

  if ! refresh_gate "$BLANC_REFRESH_SUCCESS_STAMP" "$BLANC_REFRESH_SUCCESS_COOLDOWN"; then
    mark_failure degraded "Резерв Blanc недоступен; свежая подписка уже проверялась, работает резервный маршрут."
    echo "Blanc reserve is unavailable, but a verified refresh is still within its cooldown."
    exit 0
  fi
  if ! refresh_gate "$BLANC_REFRESH_ATTEMPT_STAMP" "$BLANC_REFRESH_RETRY_COOLDOWN"; then
    mark_failure degraded "Резерв Blanc недоступен; действует пауза перед повторным обновлением."
    echo "Blanc refresh retry cooldown is active."
    exit 0
  fi

  mark_refresh_attempt "$BLANC_REFRESH_ATTEMPT_STAMP"
  if "$SCRIPT_DIR/install-blanc-auto.sh"; then
    date +%s > "$BLANC_REFRESH_SUCCESS_STAMP"
    mark_healthy
    echo "Blanc reserve refreshed and verified; personal VPN routing preserved."
  else
    mark_failure degraded "Blanc не прошёл проверку после обновления; основной и текущий резервный маршруты сохранены."
    echo "Blanc reserve refresh did not pass live verification; existing routes were preserved." >&2
    exit 1
  fi
  exit 0
fi

mode="$("${SSH[@]}" '/opt/sbin/blanc-auto mode' 2>/dev/null || echo blanc)"
if [[ "$mode" == "amnezia" ]] && "${SSH[@]}" '/opt/sbin/blanc-auto needs-refresh' >/dev/null 2>&1; then
  if ! refresh_gate "$AMNEZIA_REFRESH_STAMP" "$AMNEZIA_REFRESH_COOLDOWN"; then
    echo "Amnezia fallback is healthy; Blanc refresh cooldown is active."
    exit 0
  fi

  mark_refresh_attempt "$AMNEZIA_REFRESH_STAMP"
  echo "Amnezia fallback is active; refreshing the Blanc pool in the background."
  if "$SCRIPT_DIR/install-blanc-auto.sh"; then
    mode_after="$("${SSH[@]}" '/opt/sbin/blanc-auto mode' 2>/dev/null || echo amnezia)"
    if [[ "$mode_after" == "blanc" ]] && "${SSH[@]}" '/opt/sbin/blanc-auto test' >/dev/null 2>&1; then
      mark_healthy
      notify "VPN вернулся с Amnezia на Blanc после обновления узлов."
      echo "Blanc recovered after the background refresh."
      exit 0
    fi
  fi

  mark_failure fallback "Blanc пока недоступен; роутер продолжает работать через Amnezia."
  echo "Blanc remains unavailable; Amnezia fallback stays active."
  exit 0
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
if ! refresh_gate "$BLANC_REFRESH_ATTEMPT_STAMP" "$BLANC_REFRESH_RETRY_COOLDOWN"; then
  mark_failure degraded "VPN на роутере не восстановлен: backoff автообновления ещё активен."
  echo "Blanc refresh retry backoff is active; no router restart will be attempted." >&2
  exit 1
fi
mark_refresh_attempt "$BLANC_REFRESH_ATTEMPT_STAMP"
if "$SCRIPT_DIR/install-blanc-auto.sh" && \
    "${SSH[@]}" '/opt/sbin/blanc-auto test' >/dev/null 2>&1; then
  date +%s > "$BLANC_REFRESH_SUCCESS_STAMP"
  mark_healthy
  notify "VPN автоматически восстановлен после обновления подписки Blanc."
  echo "Router VLESS recovered after subscription refresh."
  exit 0
fi

mark_failure degraded "VPN на роутере не восстановлен: свежие узлы Blanc не прошли проверку."
echo "Router VLESS remains degraded after subscription refresh." >&2
exit 1
