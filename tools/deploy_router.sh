#!/bin/sh
set -eu

ROUTER_HOST="${ROUTER_HOST:-192.168.1.1}"
ROUTER_USER="${ROUTER_USER:-root}"
APPLY="0"

if [ "${1:-}" = "--apply" ]; then
  APPLY="1"
  shift
fi

LOCAL_CONFIG_DIR="${1:-router-backup/public/xkeen-configs}"
REMOTE_CONFIG_DIR="${REMOTE_CONFIG_DIR:-/opt/etc/xray/configs}"

echo "Local config dir: $LOCAL_CONFIG_DIR"
echo "Router: $ROUTER_USER@$ROUTER_HOST"
echo "Remote config dir: $REMOTE_CONFIG_DIR"
echo "Mode: $([ "$APPLY" = "1" ] && echo apply || echo dry-run)"

if [ ! -d "$LOCAL_CONFIG_DIR" ]; then
  echo "Config dir not found: $LOCAL_CONFIG_DIR" >&2
  exit 1
fi

tools/validate_xray_bundle.sh "$LOCAL_CONFIG_DIR"

if [ "$APPLY" != "1" ]; then
  echo
  echo "Dry-run only. Nothing was uploaded and XKeen was not restarted."
  echo "For real deploy, pass a private config directory explicitly:"
  echo "$0 --apply router-backup/private/xkeen-configs"
  exit 0
fi

case "$LOCAL_CONFIG_DIR" in
  router-backup/private/*|*/private/*) ;;
  *)
    echo "Refusing to apply from a non-private config directory: $LOCAL_CONFIG_DIR" >&2
    echo "Use a private config directory, for example: router-backup/private/xkeen-configs" >&2
    exit 1
    ;;
esac

STAMP="$(date +%Y%m%d-%H%M%S)"
REMOTE_BACKUP="/opt/backups/xray-configs-$STAMP"

ssh "$ROUTER_USER@$ROUTER_HOST" "mkdir -p /opt/backups && cp -a '$REMOTE_CONFIG_DIR' '$REMOTE_BACKUP'"
echo "Router backup: $REMOTE_BACKUP"

for src in "$LOCAL_CONFIG_DIR"/*.json; do
  [ -f "$src" ] || continue
  base="$(basename "$src")"
  dest="$base"
  [ "$base" = "05_routing.fixed-no-v2fly.json" ] && dest="05_routing.json"
  [ "$base" = "04_outbounds.template.json" ] && {
    echo "Refusing to deploy public outbound template: $src" >&2
    exit 1
  }
  echo "Uploading $src -> $REMOTE_CONFIG_DIR/$dest"
  ssh "$ROUTER_USER@$ROUTER_HOST" "cat > '$REMOTE_CONFIG_DIR/$dest'" < "$src"
done

ssh "$ROUTER_USER@$ROUTER_HOST" "xray run -confdir '$REMOTE_CONFIG_DIR' -test"
ssh "$ROUTER_USER@$ROUTER_HOST" "xkeen -restart && xkeen -status"
