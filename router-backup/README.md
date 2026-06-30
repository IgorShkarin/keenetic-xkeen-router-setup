# Netcraze/Keenetic Hopper NC-3811 XKeen Backup

Working state captured after YouTube started working through XKeen/Xray on a TV connected to the router.

## Router

- Model: Netcraze/Keenetic Hopper NC-3811
- Entware storage: USB flash drive mounted as OPKG
- XKeen: 2.0 Stable
- Xray: 26.6.27
- Mode after start: Hybrid
- VPN config source: BlancVPN-generated Xray/VLESS Reality config

## Working actions performed

1. Formatted USB flash drive as EXT4 with label `OPKG`.
2. Installed Entware for `aarch64-k3.10`.
3. Installed XKeen with Xray core.
4. Installed GeoSite/GeoIP sources:
   - `geosite_refilter.dat`
   - `geosite_zkeen.dat`
   - `geoip_refilter.dat`
   - `geoip_zkeenip.dat`
5. Replaced configs in `/opt/etc/xray/configs/`:
   - `03_inbounds.json`
   - `04_outbounds.json`
   - `05_routing.json`
6. Ran:

```sh
xkeen -ap 80,443,50000:50030
xkeen -start
xkeen -status
```

## Important fix

The BlancVPN-generated `05_routing.json` referenced:

```text
ext:geosite_v2fly.dat:category-ads-all
```

That file was not present on the router, so Xray failed to start. The working routing file removes only that missing geosite reference and keeps the rest of the rules.

Working public copy:

```text
router-backup/public/xkeen-configs/05_routing.fixed-no-v2fly.json
```

## Sensitive files

Do not commit real `04_outbounds.json` to a public repository. It contains VPN access credentials.

Local private backup path:

```text
router-backup/private/xkeen-configs/
```

This folder is ignored by Git.

## Restore

Copy the working files to the router:

```sh
scp 03_inbounds.json root@192.168.1.1:/opt/etc/xray/configs/03_inbounds.json
scp 04_outbounds.json root@192.168.1.1:/opt/etc/xray/configs/04_outbounds.json
scp 05_routing.fixed-no-v2fly.json root@192.168.1.1:/opt/etc/xray/configs/05_routing.json
```

Then restart:

```sh
xkeen -restart
xkeen -status
```

If SSH needs binding from macOS because of local routing issues:

```sh
ssh -b <mac_wifi_ip> root@192.168.1.1
```

## Follow-up

- Create Keenetic internet policy named exactly `xkeen` if per-device routing is needed.
- Assign target TV or other clients to the `xkeen` policy.
- Change default Entware root password from `keenetic`.
- After a router reboot, verify `xkeen -status`.

## Keywords

Keenetic, Netcraze, Hopper, NC-3811, XKeen, Entware, OPKG, Xray, VLESS Reality, BlancVPN, router VPN, KeeneticOS, OpenWrt alternative.
