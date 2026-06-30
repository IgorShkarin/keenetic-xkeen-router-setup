# Keenetic XKeen Router Setup

Practical backup and notes for running XKeen + Xray on a Keenetic / Netcraze router with Entware on a USB drive.

The setup was tested on **Netcraze / Keenetic Hopper NC-3811** with KeeneticOS 5.x, Entware, XKeen 2.0 Stable, and Xray 26.6.27.

## What This Repository Is For

This repository is a safe public checklist for people who want to run a selective VPN/proxy setup on Keenetic routers using:

- Keenetic / Netcraze router
- USB drive with OPKG / Entware
- XKeen
- Xray
- VLESS Reality
- BlancVPN-generated Xray configs
- GeoSite / GeoIP routing
- selective routing for services such as YouTube and other blocked domains

This is **not** an OpenWrt flashing guide. It is a KeeneticOS + Entware setup, useful when you want an OpenWrt-like router VPN result without replacing the router firmware.

It does **not** contain real VPN credentials.

## Why This Exists

The tricky part was not installing XKeen itself, but making generated Xray configs match the GeoSite files actually present on the router.

In this case, a generated routing config referenced:

```text
ext:geosite_v2fly.dat:category-ads-all
```

But the router had:

```text
geosite_refilter.dat
geosite_zkeen.dat
geoip_refilter.dat
geoip_zkeenip.dat
```

Because `geosite_v2fly.dat` was missing, Xray failed to start. The working routing config removes that missing reference and keeps the useful routing rules.

## Repository Contents

```text
router-backup/
  README.md
  public/
    xkeen-configs/
      03_inbounds.json
      04_outbounds.template.json
      05_routing.fixed-no-v2fly.json
```

Private real configs are intentionally ignored:

```text
router-backup/private/
```

## Tested Router

- Model: Netcraze / Keenetic Hopper NC-3811
- Storage: USB flash drive mounted as `OPKG`
- Entware architecture: `aarch64-k3.10`
- XKeen: 2.0 Stable
- Xray: 26.6.27
- Mode: Hybrid

Other Keenetic models with USB and Entware support may work, but were not tested here.

## High-Level Setup

1. Format USB drive as EXT4 with label `OPKG`.
2. Install Keenetic components:
   - USB support
   - EXT filesystem support
   - SMB file sharing
   - OPKG / open package support
   - Netfilter kernel modules
3. Install Entware to the USB drive.
4. SSH into Entware as `root`.
5. Install XKeen with Xray core.
6. Replace Xray configs in:

```text
/opt/etc/xray/configs/
```

7. Limit proxy ports:

```sh
xkeen -ap 80,443,50000:50030
```

8. Start XKeen:

```sh
xkeen -start
xkeen -status
```

Expected status:

```text
Proxy client xray is running in Hybrid mode
```

## Safe Config Files

Use these files as public examples:

```text
router-backup/public/xkeen-configs/03_inbounds.json
router-backup/public/xkeen-configs/04_outbounds.template.json
router-backup/public/xkeen-configs/05_routing.fixed-no-v2fly.json
```

Replace `04_outbounds.template.json` with your own generated `04_outbounds.json`.

Do not publish a real `04_outbounds.json`: it contains VPN credentials.

## Restore Example

Copy configs to the router:

```sh
scp 03_inbounds.json root@192.168.1.1:/opt/etc/xray/configs/03_inbounds.json
scp 04_outbounds.json root@192.168.1.1:/opt/etc/xray/configs/04_outbounds.json
scp 05_routing.fixed-no-v2fly.json root@192.168.1.1:/opt/etc/xray/configs/05_routing.json
```

Restart XKeen:

```sh
xkeen -restart
xkeen -status
```

If macOS has local routing issues, bind SSH to the current Wi-Fi IP:

```sh
ssh -b <mac_wifi_ip> root@192.168.1.1
```

## Security Notes

- Change the default Entware root password after setup.
- Never commit real VLESS / Reality / Xray outbounds.
- Prefer a private repository if you want to store real configs.
- Keep public repos limited to templates and sanitized notes.

## Keywords

Keenetic, Netcraze, Hopper, NC-3811, KN-3811, XKeen, Entware, OPKG, Xray, VLESS Reality, BlancVPN, YouTube, Smart TV, router VPN, KeeneticOS, OpenWrt alternative.
