#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_DIR/launchd/com.igorshkarin.blanc-router-refresh.plist.in"
DEST="${HOME}/Library/LaunchAgents/com.igorshkarin.blanc-router-refresh.plist"
LOG_PATH="${HOME}/Library/Logs/blanc-router-refresh.log"
TMP_PLIST="$(mktemp /tmp/blanc-router-refresh.XXXXXX.plist)"
UID_VALUE="$(id -u)"
trap 'rm -f "$TMP_PLIST"' EXIT

mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"
sed \
  -e "s|__SCRIPT_PATH__|$SCRIPT_DIR/blanc-refresh-if-needed.sh|g" \
  -e "s|__LOG_PATH__|$LOG_PATH|g" \
  "$TEMPLATE" > "$TMP_PLIST"
plutil -lint "$TMP_PLIST"
cp "$TMP_PLIST" "$DEST"
chmod 600 "$DEST"

launchctl bootout "gui/$UID_VALUE" "$DEST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID_VALUE" "$DEST"
launchctl kickstart -k "gui/$UID_VALUE/com.igorshkarin.blanc-router-refresh"

echo "Installed: $DEST"
echo "Interval: 5 minutes"
echo "Log: $LOG_PATH"
