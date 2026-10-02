# VPN repair, 2 October 2026

Observed 05:37–05:57 MSK:

- Router personal Reality 8443 and router Blanc both timed out; direct HTTPS
  worked. Desktop Blanc working was reported by the user.
- VPS Xray had zero restarts and another direct iPhone client was active.
- Packet headers on VPS showed TCP handshake followed by only the first
  1188 bytes of the home connection's ClientHello, then timeout. This locates
  the symptom on the home-to-VPS path; it does not establish which device or
  provider dropped the traffic.
- Isolated firefox, iOS, Safari, Firefox 120, TLS fragmentation and port
  18443 did not provide repeatable recovery. Fragmentation had one successful
  YouTube check followed by timeouts; it was not deployed.
- Direct verified HTTPS to PERSONAL_VPS_IP:443 returned in about 0.2 seconds.

Applied:

- Separate `home-vpn-xhttp.service`, VLESS/XHTTP packet-up behind the existing
  nginx HTTPS endpoint, on local-only 127.0.0.1:18444. UUIDs remain private.
- Exact nginx backup `/root/vpn-repair-20261002/signal.conf`.
- Router personal outbound and independent recovery profile now use HTTPS
  443, valid IP certificate, `allowInsecure=false`, native TLS and HTTP/1.1.
- Exact router backup `/opt/var/backups/home-vpn-xhttp-20261002/` contains
  prior personal/probe/active JSON and mode. XKeen was restarted once for
  promotion, with successful postchecks. Routing rules were not changed.
- Original Reality 8443 remains active for existing direct clients.
- Existing certificate renewal timer `signal-cert-renew.timer` calls certbot
  from `/opt/fuel-relay-venv`, validates and reloads nginx on renewal.
  Current certificate expires 8 October 2026; last renewal service result was
  success. No new certificate renewal scheduler was needed.
- nginx location access logging is disabled. New service emits warning-level
  diagnostics to the existing system journal, with stdout disabled.

Validation:

- Full candidate confdir and independent probe passed Xray validation.
- Five initial paired checks passed. Then 20 fresh pairs over several minutes
  all returned egress PERSONAL_VPS_IP and full YouTube page HTTP 200, zero failures.
- Production postcheck returned the same egress and YouTube 200.
- Real Mac request bound to Wi-Fi en0 returned YouTube 200 in 0.68 seconds,
  local IP CLIENT_LAN_IP, remote 142.251.155.4. Fresh Xray access entry matched
  this exact destination through `[redirect -> vless-reality]`. The retained
  tag name now refers to XHTTP; the compatibility tag was deliberately kept.
- Cloudflare from that Mac followed a direct routing rule, so its residential
  IP is not evidence of a failed VPN. Forced SOCKS health checks prove VPS exit.
- Router mode home, fails 0, no automatic fallback in initial production checks.
- VPS home-vpn-xhttp/xray/nginx all active, new service NRestarts=0;
  existing landing returned 200 and signal protected endpoint returned 401.
- Nine offline monitor regression tests passed. Shell/Python syntax and Git
  whitespace checks passed. Real iPhone application confirmation is pending.
- Fifteen-minute incident journal currently about 2 MiB total; configured
  eight archives / 8 MiB archive limit retained. Repair incident saved.
- Temporary experimental listeners, private configs and logs were removed.

This verifies recovery and initial stability, not a full-day uptime guarantee.
The old router Blanc pool was unhealthy before repair; backup availability was
not established by these primary-path tests.

Primary transport reference:
https://github.com/XTLS/Xray-examples/blob/main/VLESS-TLS-SplitHTTP-CaddyNginx/nginx.conf

Rollback: acquire the same home-vpn-auto lock, restore the router's backed-up
personal/probe/active configs and mode, validate the full confdir, restart only
XKeen. Restoring nginx's saved signal.conf requires nginx -t and reload. Stop
and disable home-vpn-xhttp only after no clients depend on it. Secrets must not
be copied into this repository.
