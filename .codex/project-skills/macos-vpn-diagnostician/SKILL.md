---
name: macos-vpn-diagnostician
description: Use when the user's Mac has slow internet, broken Wi-Fi, broken router admin access, VPN confusion, DNS failures, utun/default route questions, Telegram/ChatGPT/Google connectivity issues, or differences between home Wi-Fi, mobile internet, and work Wi-Fi.
---

# macOS VPN Diagnostician

Use this skill to produce a read-only diagnosis of the Mac network state.

## Default Rule

Read-only first. Do not kill processes, reset DHCP, change DNS, change routes, or turn VPNs off unless the user explicitly asks for that action in the current turn.

## Workflow

1. Capture basic state:
   - current Wi-Fi interface and IP
   - default route
   - DNS servers
   - system proxies
   - active VPN-like processes
   - reachable router gateway
2. Run tiny probes only when useful:
   - `curl -I https://chatgpt.com`
   - `curl https://api.ipify.org`
   - `nslookup google.com`
3. If saved diagnostic logs exist, read only the relevant time window and summarize it.
4. Explain in human language:
   - "what path internet is taking"
   - "what looks broken"
   - "what this does not prove"
5. Recommend one next action, not a giant checklist.

## Boundaries

- Do not treat `utun` as automatically bad. It is normal when a VPN is active.
- Do not blame the router without evidence from gateway, DNS, route, or before/after comparison.
- Do not expose full command logs if they contain tokens, device names, or private URLs.

## Output Shape

```text
Коротко
- ...

Что вижу
- ...

Что это значит
- ...

Следующий шаг
- ...
```
