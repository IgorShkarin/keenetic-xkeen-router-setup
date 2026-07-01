#!/bin/sh
set -eu

CONFIG_DIR="${1:-router-backup/public/xkeen-configs}"

echo "Checking JSON files in: $CONFIG_DIR"

for file in "$CONFIG_DIR"/*.json; do
  [ -f "$file" ] || continue
  python3 -m json.tool "$file" >/dev/null
  echo "ok json: $file"
done

if command -v xray >/dev/null 2>&1; then
  echo "xray found; running semantic config test"
  xray run -confdir "$CONFIG_DIR" -test
else
  echo "xray not found locally; skipped semantic Xray test"
fi
