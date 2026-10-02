# Codex VPN repair — 2026-10-02

Observed repeated HTTP 403 on usage and notification requests. The error page reported the residential egress instead of the VPN egress. Router connection tracking confirmed a long-lived direct NetworkService connection; fresh domain-recognized traffic used the primary VPN.

Restarted only the Electron NetworkService. Added a narrow TCP/443 rule for the observed OpenAI destination when domain sniffing is unavailable. The exact routing backup remains on the router. Full Xray configuration validation passed; XKeen restarted in Hybrid mode. A fresh request by destination address confirmed VPN selection without domain sniffing. TLS validation was preserved (address-only probe correctly rejected the hostname mismatch).

Some desktop requests still returned the old residential-IP 403 after these steps. Full application restart and a visible usage-panel check remain required; no claim of complete recovery. Computer Use denied access to the app, so restart is left to the user.

The rule covers the observed address only. Future endpoint-address changes may require revisiting it. No credentials or private infrastructure addresses are recorded here.
