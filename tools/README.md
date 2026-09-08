# Tools

Small helper scripts for the Keenetic / XKeen workflow.

These scripts are intentionally conservative:

- no real VPN credentials;
- no automatic router changes without `--apply`;
- local validation before deploy;
- redacted output by default where logs may contain local network data.

## Scripts

- `analyze_access_log.py` - parse sanitized Xray access logs and summarize direct/proxy traffic.
- `sanitize_public_release.sh` - scan public release files for likely private VPN/router secrets.
- `validate_xray_bundle.sh` - validate JSON files and optionally run `xray run -test` if `xray` is installed.
- `deploy_router.sh` - staged SSH deployment helper with a timestamped router-side backup.
- `blanc-country.sh` - fetch the private Blanc subscription from macOS Keychain,
  switch one router VLESS node, verify YouTube and ChatGPT, and roll back on failure.
- `blanc-auto-router.sh` - low-load router-side health checks, failover, explicit
  degraded state, and a `needs-refresh` signal when the saved pool is exhausted.
- `install-blanc-auto.sh` - securely refresh and validate the router country pool
  without exposing the subscription URL in process arguments.
- `blanc-refresh-if-needed.sh` - macOS recovery guard: use the saved router pool
  first, then refresh the private subscription only after sustained failure.
- `install-blanc-refresh-agent.sh` - install the five-minute macOS LaunchAgent for
  automatic recovery and state-change notifications.
