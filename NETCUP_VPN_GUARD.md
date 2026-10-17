# Netcup VPN observation and recovery — 2026-10-17

## Active now

The server's enabled `netcup-vpn-guard.timer` checks every 60 seconds after a
completed run and operates independently of the Mac. The hourly thread heartbeat
`vpn-netcup` runs the read-only checker `tools/check-netcup-vpn.py`, which now
retrieves that status and verifies external HTTPS with normal certificate checks.
Its private configuration/key and previous result are ignored under
`private-backups/netcup-guard-20261017/`.

The status key is independently revocable and forced to the guard's `--status`
command. A live attempt to execute `id` returned status JSON, and an SSH forwarding
attempt was denied. It is not a general administration key.

At 20:21 Moscow time, 13 checks over approximately 11 minutes were healthy, with
no recovery needed and no automatic production restart. The final external checker
reported `healthy: true`, fresh server status and valid public HTTPS. These checks
do not measure the remote phone or its operator. Without `ssh_key`, the checker
reports `healthy: null` and limits scope to external HTTPS availability.

On failure, the hourly task repeats once and compares an independent control
endpoint. The Mac and desktop app must be running for this hourly observation;
the server timer continues separately. The owner chose one Netcup with a German
exit. Its Reality, H1 and H2 configurations all use direct/block outbounds and
contain no reference to the old VPS. The proposed Netherlands chain was cancelled.

An example private configuration, using actual private paths when deployed:

```json
{
  "host": "REPLACE_WITH_SERVER_IP",
  "ssh_key": "REPLACE_WITH_PRIVATE_STATUS_KEY_PATH",
  "previous_result": "REPLACE_WITH_PRIVATE_RESULT_PATH"
}
```

Run with `python3 tools/check-netcup-vpn.py --config REPLACE_WITH_PRIVATE_CONFIG`.

## Server guard

The owner explicitly authorized the guard and restricted status key. They are
installed. The root-only installation backup is
`/root/vpn-recovery-backups/20261017T171008Z-guard/`; its manifest records original
paths, modes, ownership and hashes. The script before the validation fix is also
saved there as `guard.py.before-validator-fix`.

The guard:

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
- Before an Xray restart, it validates a private temporary copy of the current
  configuration with only logging disabled. All transport/routing fields remain;
  production configuration and log files are not modified. This avoids granting
  extra capabilities to access the production logger.
- nginx recovery uses its existing native `reload`, which validates configuration
  and preserves the running configuration if invalid. Native failure restart is
  enabled separately. The guard's capability bounding set remains empty.
- The global recovery cooldown is 30 minutes, including failed attempts.
  Intentionally inactive services are left to the operator/native restart policy.
- State contains synthetic health metadata and a bounded 100-entry history.
  The service caps runtime at 75 seconds and memory at 150 MB. A maintenance marker
  at `/etc/netcup-vpn-guard/maintenance` suppresses execution.
- The installed nginx drop-in enables failure restart after five seconds, with
  five attempts per five-minute window. No planned production restart is needed
  to apply this policy with a daemon reload.

Sources: `tools/netcup_vpn_guard.py`, `tools/netcup-vpn-guard.service`,
`tools/netcup-vpn-guard.timer`, `tools/nginx-vpn-recovery.conf` and
`tools/test_netcup_vpn_guard.py`. The installed script, service and timer hashes
match the workspace sources. Thirteen local safety tests passed.

`tools/test_netcup_vpn_guard_live.py` exercised the installed recovery code inside
the same sandbox with an empty capability set. It seeded an isolated prior-failure
state and injected two failing proxy results. A real recovery command was redirected
exclusively to a disposable test service; that service's PID changed and real VPN
checks then passed. All four production PIDs remained unchanged. Temporary test
services and state were removed. Healthy production services were not deliberately
crashed. The test first exposed a logger/port-validation permission issue, resolved
by the logging-disabled candidate and native nginx reload above.

For rollback, stop/disable the guard timer and restore only its managed files from
the manifest, then reload systemd. Revoke only the matching status-key entry; do not
overwrite later unrelated authorized-key changes. This guard rollback does not
restore earlier VPN routing or restart production VPN services.

Neither check promises uninterrupted carrier access, measures the remote iPhone,
or repairs an iOS extension crash. These limits remain even after server deployment.
