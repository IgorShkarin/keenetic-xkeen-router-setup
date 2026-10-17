# Happ/iPhone recovery — 2026-10-17

Status: **application access restored on the iPhone**. After reinstalling Happ
and receiving the new profile again, the owner reports that ChatGPT loaded in
Chrome and later confirms YouTube videos play. The earlier basement failure does
not establish its cause. Long-term stability is not proven by those observations.
Fresh authenticated Reality/443 traffic is present. The minute server guard and
hourly external/status observation are active. The chosen setup is one Netcup
with a German exit, independent of the old VPS.
The active server is the new Netcup VPS. The older AlexHost reachability incident
is separate. The current server address and continuation details belong in the
shared `PROJECT_STATE/vpn.md`, not this public repository.

## Evidence from the iPhone

The owner reports failure on mobile data and a cafe Wi-Fi network; the cafe network
is not the home network used for our external probes. Screenshots at 18:54–18:57
Moscow time show one Netcup-Happ ping of 1293 ms, subsequent `n/a` results, a tunnel
timer of 0:01:48, and unloaded Codex, YouTube and ChatGPT pages. The final screenshot
reports an unknown fatal error in `Tunnel.appEx` and offers to recreate the system
TUNNEL configuration.

This is evidence of a client tunnel failure. It does not establish whether the
underlying cause is memory pressure, an app defect, an invalid system VPN entry,
or another condition. A ping or a VPN icon is not proof of working applications.
The failure screenshots do not show a switch to port 443. The owner dismissed the recreation dialog and later
reported accidentally reinstalling Happ. The private Reality/443 import URI was
delivered again at the owner's request. The later report of a loaded ChatGPT page
is the first positive application result after reinstall. A subsequent reply
explicitly confirms videos load, beyond merely opening the YouTube feed.

Additional screenshots, taken at 18:37–18:39 before the later fatal-error dialog,
provide these narrower facts:

- The old Netcup-Happ profile still used port 8443, TCP, XTLS Vision, Chrome
  fingerprint and Reality. The VLESS protocol's `none` security/encryption field
  coexists with Reality below; it does not show that transport encryption was off.
- Happ reported app 6.1.0 and Xray core 26.9.9 for that earlier attempt. It logged
  successful core startup, then TLS handshake/deadline timeouts to the ping test
  endpoint. Its final stop reason was `userInitiated`; that record is not evidence
  of a crash or of the later fatal error.
- The separate tunnel-history screenshot contains entries from October 9–10,
  with app 6.0.0 and Cloudflare DoH. It does not prove the October 17 DNS settings.
- Mux, fragmentation and Xray TUN were off; IPv4 was selected. Packet analysis
  was on. The memory-limit slider was between 40 and 50 MB, with no exact numeric
  selection displayed. The idle timeout was 300 and the TCP/UDP limits 256/128.
  A stopped-state RAM reading of 0.0 MB does not establish memory pressure.

The new private URI uses port 443 and Firefox. Client versions and settings after
the reinstall have not been confirmed; do not assume those earlier settings persist.

At 19:15:39 Moscow time, a fresh read-only SSH check showed Xray active,
NRestarts=0, and 260 accepted requests for the existing Happ identity through
`home-vpn-443`, with the latest at that moment. Earlier controlled 443 probes
accounted for 24 requests and had already stopped. This proves fresh authenticated
traffic through the new inbound; it does not prove which physical device sent it
or that webpages/video finished loading. No configuration was changed in this check.

A follow-up at 19:19:41 Moscow time showed Xray, H1, H2 and nginx active, each with
NRestarts=0. The same counter reached 269, with its latest record at 19:15:52 Moscow
time. No kernel OOM event appeared in the checked interval since 18:50 Moscow.
This is a service-health snapshot, not proof of uninterrupted phone connectivity.

At 19:26 Moscow, the services still had no automatic restarts. Approximately
3.4 GB RAM and 70.77 GB disk space were free; no resource shortage was observed.

## Ongoing observation and exit-country option

At the owner's request, the hourly thread automation `vpn-netcup` was created,
then its ACTIVE status, hourly interval and thread attachment were verified.
It invokes `tools/check-netcup-vpn.py` with ignored local configuration. The
current check retrieves the minute guard's fresh status through a restricted key
and verifies external HTTPS with normal certificate validation. It reports
`healthy: true`; this is server-path evidence, not a remote phone measurement.
Local hourly runs require the Mac and app, while the server guard runs independently.

The owner authorized the bounded server guard and status-only key. Both are
installed and verified. At 20:21 Moscow, all 13 checks over approximately 11 minutes
were healthy, the timer was enabled/active, recovery count was zero and production
PIDs and automatic restart counts were unchanged. Thirteen safety tests and the
live isolated recovery test passed. The installed source hashes match the worktree;
the guard's capability bounding set remains empty. See
[NETCUP_VPN_GUARD.md](../NETCUP_VPN_GUARD.md) for its scope and rollback.

The active exit geolocates to Germany, and YouTube's anonymous page reports DE.
The previous VPS geolocates to the Netherlands, but its YouTube page reports RU.
This may explain the advertising difference; it does not prove an ad-free result.
Direct home access to that VPS still timed out, while access from the new VPS
worked. An isolated VLESS client on the new VPS through the previous server
passed Google, YouTube and Cloudflare HTTP 204 checks and a 10 MB download in
1.20 seconds. Its YouTube page also reported RU. Production PIDs and routes were
unchanged. The owner subsequently rejected a two-server dependency because of
cost and expects the old VPS to be switched off in about two weeks. The chain was
not deployed. All three new VPS VPN configurations have direct/block outbounds
and no old-server address reference. The hourly observation prompt now specifies
one Netcup with its German exit. No provider billing or renewal setting was changed.

## Deployed changes

- Preserved the existing Reality inbound on TCP 8443 and its existing identities.
- Added an inbound tagged `home-vpn-443` on **127.0.0.1:18448** using the same
  credentials and Reality parameters. It accepts PROXY protocol only on loopback.
- Added nginx stream SNI routing on public TCP 443. The existing Reality SNI goes
  to that loopback inbound; other traffic goes to the existing HTTPS virtual host,
  now listening on loopback port 18443. TLS is passed through without terminating
  the Reality connection. PROXY protocol preserves the source IP for both backends;
  HTTP trusts those headers only from loopback.
- Enabled TCP keepalive after 30 idle seconds, with 15-second intervals. The
  nginx public listener also sets keepalive and a one-hour stream timeout.
- Set Xray level-0 connection idle timeout to 600 seconds. Configured the Reality
  and H1 services to retry after failures every five seconds without exhausting
  the systemd start limit. Existing invalid-configuration exit protection remains.
- The existing Happ identity was also added to the H1 XHTTP backend for comparison.
  This is an experimental option; its large-transfer check failed. It is not the
  selected phone recovery path. H1 proxy read/send timeouts are now one hour.
- Installed only the official Debian `libnginx-mod-stream` package. No other
  packages were upgraded or removed. Router production configuration was not changed.

The two Reality inbounds contain copies of their client lists. Future issuance,
revocation or key rotation must update both relevant inbounds. The H1 experiment
also accepts the same Happ identity; revocation must include that backend.

The public nginx stream template is
[`tools/reality-443-stream.nginx.conf.in`](../tools/reality-443-stream.nginx.conf.in).
It requires the stream module, a top-level nginx include, matching loopback
backends, and the existing server's actual SNI. It is not a standalone deployment.

## Verification and limits

Both Xray candidate configurations and nginx configuration passed validation.
The changed services are active; no automatic Xray restarts were observed after
the final planned restart. No kernel OOM event was found. There were planned
restarts and two automatic configuration rollbacks during deployment readiness
checks; this is not a claim of uninterrupted service throughout maintenance.

| Check | Observed result |
| --- | --- |
| VPS local Reality, Firefox and Chrome fingerprints | Google/Cloudflare/YouTube HTTP 204; DNS-over-HTTPS HTTP 200 |
| VPS local 10 MB transfer through Reality | Complete, approximately 0.37 s |
| Home network, original Reality/8443 | Three HTTP 204 responses; 10 MB complete in 3.11 s |
| Home network, new Reality/443 | Three HTTP 204 responses and a valid DNS answer |
| First 10 MB transfer through Reality/443 | Complete in 1.40 s |
| Following two 10 MB transfers through Reality/443 | 30 s timeouts after 1,528,046 and 3,264,183 bytes |
| Continuous Reality/443 transfer, intentionally capped at 64 KiB/s | All 10 MB received over 150.47 s without a disconnect |
| Existing home H2 path, three 10 MB transfers | One 20 s timeout, then complete transfers in 7.79 and 4.87 s |
| VPS direct 10 MB control | Complete in 0.235 s |
| Existing HTTPS site through the home H2 path | All 3,289,229 bytes received in 3.85 s |
| New H1 XHTTP option, from home | Small HTTPS requests and DNS passed; 10 MB timed out after 1,056,110 bytes |

Fast bulk transfers remain intermittently slow on more than one transport.
These measurements do not identify the carrier, filtering mechanism or exact
cause. The successful continuous test demonstrates a bounded transfer from the
home network, not reliable operation on the owner's iPhone or indefinite uptime.

At cutover the first Reality check timed out; a subsequent complete four-request
readiness round passed. Later external 443 checks passed. Reload completion alone
must not be treated as endpoint readiness.

Existing TLS certificate validation and its twice-daily renewal timer remain
enabled. Existing Xray access/error logs mask client addresses and rotate daily
with a 25 MB size threshold and seven retained rotations. Raw browsing logs and
connection credentials are not copied into this repository.

## Continuation

1. Application access and the guard are verified. Continue the installed
   observation within its scope, keeping the one-server Netcup setup.
2. If failure recurs with adequate signal, collect its exact Moscow time and
   fresh Happ log/settings before changing the server. Correlate `home-vpn-443`
   events; server logs use Europe/Berlin, one hour behind Moscow on this date.
3. If the extension fails again, obtain the Happ/iOS versions and its log or
   iOS crash record around the failure. Recreate only the Happ VPN entry under
   iOS Settings > General > VPN & Device Management > VPN; reboot if recreation
   does not help, as the Happ error dialog suggests. Do not infer a memory or
   carrier cause from the generic message alone.

The private Reality/443 import file and QR are under ignored
`private-backups/happ-20261017/`; the QR was decoded locally and matched the URI.

Root-only backups of the successful stages remain on the VPS:
`/root/vpn-recovery-backups/20261017T154225Z/` and
`/root/vpn-recovery-backups/20261017T155052Z-443/`.
Each `manifest.json` maps exact original files, ownership, permissions and hashes.
Restore complete stages in reverse order, validate both Xray and nginx, then
restart only the affected Xray service and reload nginx. Do not reset the router
or restore unrelated application files.

## Primary references

- [Happ: adding a configuration](https://www.happ.su/main/faq/adding-configuration-subscription)
- [Happ: ping methods](https://www.happ.su/main/ru/faq/ping)
- [Xray: socket keepalive](https://xtls.github.io/ru/config/transports/sockopt.html)
- [nginx: routing ClientHello by SNI](https://nginx.org/en/docs/stream/ngx_stream_ssl_preread_module.html)
- [Apple: VPN and network connectivity troubleshooting](https://support.apple.com/ru-ru/102281)
- [Scheduled tasks: local execution requirements](https://learn.chatgpt.com/docs/automations?surface=app)
- [YouTube monetized markets and paused advertising in Russia](https://support.google.com/youtube/answer/1342206?hl=ru)
