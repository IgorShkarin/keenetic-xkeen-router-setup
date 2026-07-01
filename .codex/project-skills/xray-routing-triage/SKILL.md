---
name: xray-routing-triage
description: Use when a service fails through XKeen/Xray on the router, when access logs need parsing, or when proposing selective VLESS routing candidates for YouTube, Telegram, ChatGPT, Claude, Kino.pub, games, Smart TV, or mobile apps.
---

# Xray Routing Triage

Use this skill to turn symptoms and sanitized logs into routing candidates. It is a fact-gathering skill, not the final decision maker.

## Inputs

Use whichever are available:

- user symptom, for example "ChatGPT mobile says country not available"
- sanitized Xray access logs
- `router-backup/public/xkeen-configs/05_routing.fixed-no-v2fly.json`
- temporary files under `artifacts/routing-candidates/`

## Workflow

1. Identify the failing service and target device.
2. Extract observed domains, IPs, network type, port, and outbound tag.
3. Separate:
   - traffic already going through `vless-reality`
   - traffic still going `direct`
   - UDP/443 or other protocol-level clues
4. Propose the smallest routing candidate that could explain the symptom.
5. Mark confidence:
   - `likely-domain`
   - `likely-ip`
   - `likely-udp-443`
   - `needs-more-log`

## Boundaries

- Do not apply router changes.
- Do not broaden routing to huge categories without evidence.
- Do not publish raw logs.
- Do not include real VLESS credentials or subscription URLs.

## Output Shape

```text
Service
- ...

Observed Direct Candidates
- ...

Suggested Minimal Patch
- ...

Confidence
- ...
```
