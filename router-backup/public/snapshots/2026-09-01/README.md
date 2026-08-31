# Sanitized recovery snapshot — 2026-09-01

This snapshot records the public-safe shape of the working router setup after
refreshing the VLESS provider profile.

## Runtime baseline

- USB-backed Entware/OPKG storage must be mounted before starting XKeen.
- Xray runs in Hybrid mode through XKeen.
- The outbound profile is provider-generated VLESS Reality configuration.
- Direct and block outbounds remain separate from the provider outbound.
- Validate the complete Xray configuration before restarting the service.
- If VLESS handshakes stall, refresh the provider subscription and replace the
  private outbound file; do not publish that file.
- SMB depends on the USB/Entware layer and should be checked separately from
  Xray connectivity.

## Public artifact

[`04_outbounds.template.json`](04_outbounds.template.json) preserves the
current outbound structure with placeholders only. It is not a usable VPN
profile until filled with credentials from a private provider subscription.

## Deliberate omissions

This snapshot contains no server address, access URL, UUID, Reality key,
short ID, password, Wi-Fi credential, LAN address, or live log excerpt.
