# Tools

Small helper scripts for the Keenetic / XKeen workflow.

These scripts are intentionally conservative:

- no real VPN credentials;
- no automatic router changes without `--apply`;
- local validation before deploy;
- redacted output by default where logs may contain local network data.

## Scripts

- `analyze_access_log.py` - parse sanitized Xray access logs and summarize direct/proxy traffic.
- `macos-vpn-preflight.sh` - read-only guard for connected desktop VPNs, active
  IPv4 tunnel interfaces, VPN-like processes, and the Mac route to a target IP.
  Use `--strict` before attributing an application's behavior to the router.
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

## ChromeGPT automatic VPN selection

`ChromeGPT через VLESS.command` now uses the loopback SOCKS switch on port
10809. Install/update it with `python3 tools/install-chromegpt-auto.py`.
The installer copies the runtime to `~/Library/Application Support/ChromeGPT-Auto`
and registers `com.igor.chromegpt-auto`; Documents is restricted for LaunchAgents.
Only the dedicated old ChromeGPT SSH forward is replaced; browser tabs and
router configuration remain intact.

When both public IPv4 probe routes use the same tunnel interface, connections
use the desktop VPN. Each destination must route through that same interface.
Otherwise they use the dedicated router SOCKS route via SSH port 10819.
There is no direct physical-network fallback. A VPN route change closes existing
proxy streams within about one second; refresh a stalled page afterward.
This detects full IPv4 tunnel routing, not merely an open VPN app; split tunnels
use the router. IPv6-only desktop destinations are rejected. The proxy listens
only on loopback and records mode changes without browsing destinations.

Logs: `~/Library/Logs/ChromeGPT-Auto/`. Rollback: boot out the LaunchAgent,
restore the prior launcher from Git, and run it to recreate the original forward.
The live desktop path was verified with N26 and Adyen (HTTP 200); five tests cover
route selection and rejection of a destination outside the desktop tunnel.
The live VPN-off transition requires a separate observation; VPN was kept on.
