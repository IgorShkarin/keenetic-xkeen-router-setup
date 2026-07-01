---
name: keenetic-repo-triage
description: Use when working in this repository before changing docs, public router configs, backups, release notes, or GitHub-facing content. Performs a cheap first pass over repo state, related files, inconsistencies, and publication risks without making final routing or security decisions.
---

# Keenetic Repo Triage

Use this skill as the first pass when the task touches repository structure, README text, public config examples, backups, release notes, or GitHub discoverability.

## Workflow

1. Inspect `git status --short`.
2. Read only the files that are directly relevant:
   - `README.md`
   - `router-backup/README.md`
   - `router-backup/public/xkeen-configs/*.json`
   - changed files from `git diff --name-only`
3. Produce a compact triage:
   - scope
   - changed or risky files
   - contradictions between README and configs
   - whether `public-config-sanitizer` should run before commit
   - whether `xray-routing-triage` should inspect logs or routing candidates

## Boundaries

- Do not decide final routing policy.
- Do not move private configs into public paths.
- Do not claim a service works unless the user confirmed it or current verification proves it.
- Do not commit or push.

## Output Shape

```text
Scope
- ...

Findings
- ...

Next Actions
- ...
```
