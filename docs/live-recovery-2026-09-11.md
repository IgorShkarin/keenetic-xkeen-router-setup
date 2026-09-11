# Live recovery: ChatGPT native apps

## Symptom

On 2026-09-11, ChatGPT Classic on macOS and the official iPhone app reported
that ChatGPT was unavailable in the region, while the browser path remained
usable.

## Cause

The router sent `UDP/443` directly. The native clients could use QUIC/HTTP3,
which bypassed the domain-based Xray rules for `chatgpt.com` and `openai.com`.
The tested VLESS Reality outbound also does not provide a usable QUIC path.

## Fix

The routing rule for `UDP/443` was changed from `direct` to `block`. This forces
the clients to retry over TCP/443, where Xray can classify the destination and
send the ChatGPT/OpenAI domains through `vless-reality`.

The complete Xray configuration was validated before the change, XKeen was
restarted, and the native iPhone and macOS clients were then confirmed working.
The public routing example already contains the sanitized `UDP/443` block.

No VPN credentials, UUIDs, private keys, subscription URLs, or public IPs are
stored in this note.
