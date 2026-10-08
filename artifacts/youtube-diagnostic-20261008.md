# YouTube / VPN diagnosis — 2026-10-08

Read-only checks at 19:24–19:26 MSK. Exact symptom time and affected device were requested but not supplied during this stage.

## Confirmed

- Router: XKeen/Xray running in Hybrid, selected vless-reality (personal XHTTP H2), health healthy, fails 0. No new incident/switch archives since 2 October. Router uptime approximately 11 days 18 hours; load 0.53 / 0.43 / 0.37; available memory approximately 212 MiB.
- Saved minute checks (19:11–19:25 MSK): YouTube health endpoint took 7.021 seconds at 19:13 and 7.800 seconds at 19:24; timed out after 5.002 seconds at 19:21. Cloudflare also had delays/timeouts in this window. The independent probe.log fragments are stale (2 October) and were not treated as current evidence.
- Three additional alternating YouTube generate_204 checks: active H2 returned 204 in 0.195 and 0.159 seconds, then timed out after 5.002 seconds. H1 returned 204 in 0.433, 0.684 and 0.365 seconds. An earlier fresh Amnezia check returned 204 in 1.467 seconds.
- H1 and Amnezia were marked healthy; Blanc unavailable. These reserves were not selected for production during this diagnosis.
- Manager accepts the active path if either YouTube or Cloudflare succeeds. Therefore partial stalls can coexist with health=healthy without triggering failover.
- VPS VPN services home-vpn-h2, home-vpn-xhttp and xray, plus their nginx frontend, active; NRestarts=0. No entries in the two transport service journals for the checked interval. Direct server YouTube probe returned 204 in 0.095 seconds. Certificate renewal timer active; actual forced HTTPS checks succeeded with normal TLS validation.
- Mac-to-router ICMP: 12/12 replies, no loss, mean 3.356 ms. Cisco and Tailscale connected; external sample route via Wi-Fi/router. The application's exact destination route was not verified. Router-originated failures establish a symptom independent of these desktop tunnels.
- Visible related Xray entries selected VPN for www.youtube.com and youtubei.googleapis.com. Video CDN throughput and real playback on the affected device were not tested.

## Interpretation and limits

Intermittent latency/timeouts on the active H2 VPN path are confirmed and can plausibly explain the reported YouTube stalls if time/device align. The small paired sample favors investigating H2/home-to-VPS transport versus H1, but does not identify packet loss, ISP filtering, CDN problems, or transport implementation as the cause. No proof of a VPS crash or a router restart was found. Current HTTP probes do not establish video playback quality or sustained bandwidth.

No Mac/router/VPS configuration, production route, service or process was changed/restarted. Only this sanitized report and the saved health evidence were created locally. No raw browsing logs, credentials or infrastructure addresses were saved.

Next step if the symptom repeats: correlate exact time/device and observed video CDN with the logs; if persistent, evaluate a controlled H2/H1 playback comparison. The unavailable Blanc reserve is a separate maintenance item.
