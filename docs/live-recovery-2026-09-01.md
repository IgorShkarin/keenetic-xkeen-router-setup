# Live recovery note — 2026-09-01

This note records a sanitized router-side recovery check. It contains no credentials,
UUIDs, subscription URLs, private keys, or client secrets.

## Stable router baseline

- Keep the router's built-in administration service and the Entware/OPKG shell on
  separate, explicitly configured ports.
- If both services are assigned the same port, the Entware startup script can fail
  even though the router itself and the VPN core are otherwise healthy.
- Treat the removable OPKG storage as a dependency: confirm it is mounted before
  diagnosing the VPN layer.
- Validate the complete generated Xray configuration before restarting XKeen.

## SMB and VLESS checks

SMB can be enabled with the OPKG share active; after enabling it, CPU, memory, DNS,
HTTPS, Xray status, and TCP listeners on 139/445 remained healthy. The configured
secondary share is inactive when its separate storage is absent.

When a provider-side VLESS incident occurs, requests can be classified to the VPN
outbound while the handshake still stalls. This is distinct from a routing typo or a
storage/SMB failure; refresh the provider subscription before changing routing rules.
