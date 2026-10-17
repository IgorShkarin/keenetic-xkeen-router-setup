# Netcup VPN observation — 2026-10-17

## Active now

The hourly thread heartbeat `vpn-netcup` runs the read-only checker
`tools/check-netcup-vpn.py`. Its configuration and previous result are in ignored
`private-backups/netcup-guard-20261017/`; they are not public examples.

The current configuration checks the existing public HTTPS endpoint with normal
certificate validation. `healthy: null` means that only availability was checked.
It does not establish a working VLESS data path or measure the iPhone. On failure,
the scheduled task repeats once and compares an independent control endpoint.
The computer and desktop app must be running for these local scheduled checks.

An example private configuration, using actual private paths when deployed:

```json
{
  "host": "REPLACE_WITH_SERVER_IP",
  "previous_result": "REPLACE_WITH_PRIVATE_RESULT_PATH"
}
```

Run with `python3 tools/check-netcup-vpn.py --config REPLACE_WITH_PRIVATE_CONFIG`.

## Prepared, not deployed

The owner has been asked to authorize a persistent server guard and an independently
revocable SSH key restricted to a status command. Automatic approval review rejected
the installation pending that explicit authorization. No server files or SSH access
were changed by the rejected attempt. The generated local private status key is
ignored and is not authorized on the server.

The prepared guard checks every 60 seconds after each completed run:

- It starts a temporary loopback-only Xray client, passes through nginx/443 and
  Reality, and checks Google and Cloudflare HTTP 204 endpoints. The selected
  existing phone identity follows the same server routing rules; these synthetic
  loopback requests must not be attributed to a physical phone.
- It reads the current identity and Reality parameters from root-owned configuration.
  OpenSSL derives the public key through stdin; private key material is not passed
  in argv, status output or a duplicate permanent probe configuration.
- A partial site failure is reported as degraded and does not restart production.
  All-site failures require a successful independent direct control, active local
  services, at least three consecutive checks spanning at least two minutes, and
  another failed check immediately before recovery.
- Both production configurations must validate before one affected service is
  restarted. The global recovery cooldown is 30 minutes, including failed attempts.
  Intentionally inactive services are left to the operator/native restart policy.
- State contains synthetic health metadata and a bounded 100-entry history.
  The service caps runtime at 75 seconds and memory at 150 MB. A maintenance marker
  at `/etc/netcup-vpn-guard/maintenance` suppresses execution.
- The proposed nginx drop-in enables failure restart after five seconds, with
  five attempts per five-minute window. No planned production restart is needed
  to apply this policy with a daemon reload.

Prepared sources: `tools/netcup_vpn_guard.py`, `tools/netcup-vpn-guard.service`,
`tools/netcup-vpn-guard.timer`, `tools/nginx-vpn-recovery.conf` and
`tools/test_netcup_vpn_guard.py`. The 13 safety tests pass locally; the service
sandbox and live timer have not been verified because deployment awaits approval.

After deployment and verification, adding `ssh_key` to the private checker
configuration enables full server-status retrieval. That key must have a forced
`--status` command with forwarding, shell and PTY access restricted. It must never
be treated as a general administration key.

Neither check promises uninterrupted carrier access, measures the remote iPhone,
or repairs an iOS extension crash. These limits remain even after server deployment.
