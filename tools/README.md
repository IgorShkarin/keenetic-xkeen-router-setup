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
