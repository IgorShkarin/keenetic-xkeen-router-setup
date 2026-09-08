# Router backup before AmneziaWG setup

- Created: 2026-09-08 10:50 Europe/Moscow
- Router: Netcraze Hopper NC-3811, KeeneticOS 5.01.C.4.0-1
- Remote backup: `/opt/var/backups/codex-amnezia-pre-20260908-105000`
- Size verified: 112 KB

The backup contains the live Xray JSON files, Blanc auto-failover script and
state, country pool, root crontab, and a Keenetic running-config snapshot.
Private configuration contents are intentionally not stored in Git.

## Healthy Blanc VLESS baseline after subscription refresh

- Created: 2026-09-08 11:47 Europe/Moscow
- Remote backup: `/opt/var/backups/codex-vless-healthy-20260908-114744`
- Permissions: `0700`, root-only
- Contents: live Xray configs, refreshed Blanc country pool, `blanc-auto`
  script and state, root crontab, Xray init script, Keenetic running-config,
  version/status output, and full Xray validation output
- Verification: 88 files, 496 KB, 87 stored file checksums passed
- Xray validation: `Configuration OK.`
- Live VLESS proof before backup: YouTube `HTTP 204`, ChatGPT `HTTP 200`

The backup contains private provider credentials and remains only on the router.
Only this sanitized inventory is stored in Git.

## Stale-pool recovery guard deployment

- Router monitor installed: 2026-09-08 12:16 Europe/Moscow
- Pre-install router backup: `/opt/var/backups/blanc-auto-install-20260908-121653`
- Router state after install: `country=se`, `health=healthy`, `failures=0`,
  `refresh=no`
- Router cron: one health check every 3 minutes
- macOS LaunchAgent:
  `~/Library/LaunchAgents/com.igorshkarin.blanc-router-refresh.plist`
- macOS interval: 5 minutes
- Executable copy:
  `~/Library/Application Support/Blanc Router Monitor/bin`
- Previous plist backup:
  `~/Library/LaunchAgents/com.igorshkarin.blanc-router-refresh.plist.bak-20260908-122156`
- LaunchAgent verification: two runs, last exit code `0`
- Final router checks: `Configuration OK.`, YouTube `HTTP 204`,
  ChatGPT `HTTP 200`
- Degraded-state simulation: `needs-refresh` became visible, a healthy `force`
  check cleared it, and the active outbound hash remained unchanged

The subscription URL remains only in macOS Keychain. The router stores generated
profiles, not the subscription URL; the public Git history stores neither.
