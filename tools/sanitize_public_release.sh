#!/bin/sh
set -eu

SCOPE="${*:-README.md router-backup/README.md router-backup/public docs tools .codex .gitignore}"

echo "Scanning public release scope:"
printf '%s\n' "$SCOPE"
echo

PATTERN='vless://|withblancvpn|privateKey"[[:space:]]*:|shortId"[[:space:]]*:[[:space:]]*"(?!REPLACE_WITH)|password"[[:space:]]*:|uuid"[[:space:]]*:[[:space:]]*"(?!REPLACE_WITH)|092be170|6dbab41'

if rg --pcre2 -n \
  --glob '!tools/sanitize_public_release.sh' \
  --glob '!.codex/project-skills/public-config-sanitizer/SKILL.md' \
  "$PATTERN" $SCOPE; then
  echo
  echo "needs-redaction: possible private material found in public scope"
  exit 1
fi

echo "safe-to-publish: no obvious private VPN/router secrets found"
