# Keenetic XKeen Router Setup

[![Router](https://img.shields.io/badge/router-Keenetic%20%2F%20Netcraze-blue)](#tested-router)
[![XKeen](https://img.shields.io/badge/XKeen-2.0%20Stable-success)](#high-level-setup)
[![Xray](https://img.shields.io/badge/Xray-26.6.27-success)](#tested-router)
[![Secrets](https://img.shields.io/badge/secrets-not%20included-critical)](#security-notes)

Practical backup and notes for running XKeen + Xray on a Keenetic / Netcraze router with Entware on a USB drive.

The setup was tested on **Netcraze / Keenetic Hopper NC-3811** with KeeneticOS 5.x, Entware, XKeen 2.0 Stable, and Xray 26.6.27.

## Коротко по-русски

Это рабочий публичный конспект настройки **XKeen + Xray + VLESS Reality** на роутере **Keenetic / Netcraze Hopper NC-3811** через **Entware / OPKG на USB-флешке**.

Задача была простая и болезненная: сделать нормальный интернет на роутере, чтобы через него открывался YouTube и работал Smart TV, без прошивки OpenWrt и без установки VPN-клиента на каждое устройство.

В этом репозитории:

- есть безопасные примеры конфигов XKeen/Xray;
- есть фикс ошибки с отсутствующим `geosite_v2fly.dat`;
- есть структура резервной копии;
- нет реальных ключей, UUID, VLESS-ссылок и BlancVPN-секретов.

Если репозиторий сэкономил тебе вечер боли с роутером, поставь звезду - так его проще найдут другие.

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

## Who This Helps

This repository may help if:

- you have a Keenetic or Netcraze router with USB support;
- you want router-level VPN/proxy for YouTube, Smart TV, Telegram, streaming, or blocked domains;
- you use BlancVPN, VLESS Reality, Xray, or similar configs;
- you do not want to flash OpenWrt yet;
- XKeen starts failing because a generated routing config references a missing GeoSite file;
- you want a safe public backup structure without publishing private VPN credentials.

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

## Problem And Fix

| Symptom | Cause | Fix |
| --- | --- | --- |
| Xray does not start through XKeen | Generated routing config references `geosite_v2fly.dat`, but the file is absent on the router | Use `05_routing.fixed-no-v2fly.json` as `05_routing.json` |
| YouTube or Smart TV does not work through router VPN | XKeen/Xray may be down, wrong policy may be selected, or DNS/routing may be inconsistent | Check `xkeen -status`, routing policy, DNS, and config files |
| Public backup is risky | Real `04_outbounds.json` contains VPN credentials | Store only `04_outbounds.template.json` publicly |

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

## Что Не Входит В Репозиторий

- реальные VPN-ключи;
- реальные VLESS-ссылки;
- приватный `04_outbounds.json`;
- универсальная гарантия для любого провайдера, модели роутера или VPN-сервиса;
- инструкция по прошивке OpenWrt.

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

Copy configs to the router. On some Entware installations, `scp` may fail if
`/opt/libexec/sftp-server` is absent; in that case use SSH, the router terminal,
or install an SFTP server first.

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

For Entware Dropbear, SSH public keys are read from:

```text
/opt/etc/dropbear/authorized_keys
```

Adding keys only to `/opt/root/.ssh/authorized_keys` may not be enough.

## Security Notes

- Change the default Entware root password after setup.
- Never commit real VLESS / Reality / Xray outbounds.
- Prefer a private repository if you want to store real configs.
- Keep public repos limited to templates and sanitized notes.

## AI Disclosure

This README and repository structure were prepared with AI assistance. The network setup was tested on a real router, and private VPN credentials were intentionally removed before publishing.

## Keywords

Keenetic, Netcraze, Hopper, NC-3811, KN-3811, XKeen, Entware, OPKG, Xray, VLESS Reality, BlancVPN, YouTube, Smart TV, router VPN, KeeneticOS, OpenWrt alternative, VPN на роутере, YouTube на телевизоре, YouTube на Smart TV, обход блокировок на Keenetic, настройка XKeen.
