#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_DIR/launchd/com.igorshkarin.blanc-router-refresh.plist.in"
DEST="${HOME}/Library/LaunchAgents/com.igorshkarin.blanc-router-refresh.plist"
LOG_PATH="${HOME}/Library/Logs/blanc-router-refresh.log"
INSTALL_DIR="${HOME}/Library/Application Support/Blanc Router Monitor/bin"
TMP_PLIST="$(mktemp /tmp/blanc-router-refresh.XXXXXX.plist)"
UID_VALUE="$(id -u)"
trap 'rm -f "$TMP_PLIST"' EXIT

mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs" "$INSTALL_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
if [[ -n "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  backup_dir="${INSTALL_DIR}.bak-$stamp"
  mkdir -p "$backup_dir"
  cp -p "$INSTALL_DIR"/* "$backup_dir/"
  echo "Previous agent files: $backup_dir"
fi
cp -p \
  "$SCRIPT_DIR/blanc-refresh-if-needed.sh" \
  "$SCRIPT_DIR/install-blanc-auto.sh" \
  "$SCRIPT_DIR/blanc-auto-router.sh" \
  "$SCRIPT_DIR/blanc_vless_to_xray.py" \
  "$INSTALL_DIR/"
chmod 700 \
  "$INSTALL_DIR/blanc-refresh-if-needed.sh" \
  "$INSTALL_DIR/install-blanc-auto.sh" \
  "$INSTALL_DIR/blanc-auto-router.sh" \
  "$INSTALL_DIR/blanc_vless_to_xray.py"
sed \
  -e "s|__SCRIPT_PATH__|$INSTALL_DIR/blanc-refresh-if-needed.sh|g" \
  -e "s|__LOG_PATH__|$LOG_PATH|g" \
  "$TEMPLATE" > "$TMP_PLIST"
plutil -lint "$TMP_PLIST"
if [[ -f "$DEST" ]]; then
  cp -p "$DEST" "$DEST.bak-$stamp"
fi
cp "$TMP_PLIST" "$DEST"
chmod 600 "$DEST"

launchctl bootout "gui/$UID_VALUE" "$DEST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_VALUE" "$DEST"
launchctl kickstart -k "gui/$UID_VALUE/com.igorshkarin.blanc-router-refresh"

echo "Installed: $DEST"
echo "Interval: 5 minutes"
echo "Log: $LOG_PATH"
