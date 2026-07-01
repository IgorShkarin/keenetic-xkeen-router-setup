---
name: public-config-sanitizer
description: Use before committing or pushing public router backup files, Xray/XKeen configs, README examples, logs, diagnostics, or GitHub SEO content. Checks that no private VPN credentials, VLESS subscription links, Reality keys, UUIDs, real endpoints, passwords, or private router snapshots are exposed.
---

# Public Config Sanitizer

Use this skill before every public commit that touches router configs, logs, backup structure, docs with examples, or deployment tooling.

## Workflow

1. Inspect `git status --short` and `git diff --cached --name-only` when staged files exist.
2. Confirm private paths stay private:
   - `router-backup/private/`
   - `vpn_logs/`
   - raw router snapshots
3. Scan public paths for risky material:
   - real VLESS links
   - BlancVPN subscription links or hostnames
   - Reality private keys and short IDs
   - real UUIDs in outbound configs
   - passwords, API keys, tokens
   - raw access logs with private IPs or device names
4. Verify public examples use placeholders such as `REPLACE_WITH_*`.
5. Return a verdict:
   - `safe-to-publish`
   - `needs-redaction`

## Boundaries

- If unsure, choose `needs-redaction`.
- Do not copy values from private files into public templates.
- Do not print suspected secrets in the final answer; identify file and field type only.

## Useful Local Checks

```sh
git status --short
git diff --name-only
tools/sanitize_public_release.sh
```
