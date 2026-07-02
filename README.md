# Keenetic XKeen Router Setup

[![Router](https://img.shields.io/badge/router-Keenetic%20%2F%20Netcraze-blue)](#tested-router)
[![XKeen](https://img.shields.io/badge/XKeen-2.0%20Stable-success)](#high-level-setup)
[![Xray](https://img.shields.io/badge/Xray-26.6.27-success)](#tested-router)
[![Secrets](https://img.shields.io/badge/secrets-not%20included-critical)](#security-notes)

Practical backup and notes for running XKeen + Xray on a Keenetic / Netcraze router with Entware on a USB drive.

The setup was tested on **Netcraze / Keenetic Hopper NC-3811** with KeeneticOS 5.x, Entware, XKeen 2.0 Stable, and Xray 26.6.27.

## Tested Services

The setup was used for router-level access to:

- YouTube on Smart TV
- Kino.pub on LG webOS TV
- WOT Blitz / Tanks Blitz
- Telegram on mobile and desktop
- Claude
- ChatGPT web and ChatGPT mobile app
- OpenAI / ChatGPT / Codex

The most useful debugging pattern was simple: enable temporary Xray access logs,
reproduce the broken app on the target device, find domains that still go
`direct`, and add only those domains or IPs to the `vless-reality` route.

For some mobile apps, routing domains was not enough. The working fix was to
route `UDP/443` through `vless-reality`, because apps may use QUIC/HTTP3 and
skip the domain-based routing path.

## Коротко по-русски

Это рабочий публичный конспект настройки **XKeen + Xray + VLESS Reality** на роутере **Keenetic / Netcraze Hopper NC-3811** через **Entware / OPKG на USB-флешке**.

Задача была простая и болезненная: сделать нормальный интернет на роутере, чтобы через него открывался YouTube и работал Smart TV, без прошивки OpenWrt и без установки VPN-клиента на каждое устройство.

В этом репозитории:

- есть безопасные примеры конфигов XKeen/Xray;
- есть фикс ошибки с отсутствующим `geosite_v2fly.dat`;
- есть пример точечной маршрутизации для YouTube, Kino.pub, WOT Blitz, Telegram, Claude и ChatGPT;
- есть фикс для мобильных приложений через маршрутизацию `UDP/443` в VLESS;
- есть фикс для Telegram media/CDN, когда сообщения работают, но картинки и аватарки не грузятся;
- есть структура резервной копии;
- нет реальных ключей, UUID, VLESS-ссылок и BlancVPN-секретов.

Если репозиторий сэкономил тебе вечер боли с роутером, поставь звезду - так его проще найдут другие люди с Keenetic, XKeen, BlancVPN, VLESS Reality и Smart TV.

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
- you want router-level VPN/proxy for YouTube, Smart TV, Telegram, Claude, ChatGPT mobile, streaming, or blocked domains;
- Telegram connects, but images, avatars, previews, or media files do not load on mobile Wi-Fi;
- you use BlancVPN, VLESS Reality, Xray, or similar configs;
- you do not want to flash OpenWrt yet;
- XKeen starts failing because a generated routing config references a missing GeoSite file;
- mobile apps still fail even though the same service works in a browser;
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
| Kino.pub interface opens but posters or films do not load on TV | TV app uses extra CDN/API domains or raw IPs that may still go `direct` | Add observed domains/IPs from Xray logs to the `vless-reality` route |
| WOT Blitz still detects RU region | The game uses domains such as `wotb.app` and `gamegrids.net`, not only obvious Wargaming/Lesta domains | Route the actual domains seen in Xray logs through VPN |
| Telegram does not connect on home Wi-Fi | Telegram apps may use direct MTProto IP ranges, not only web domains | Route Telegram domains and Telegram IP ranges through VPN |
| Telegram messages work, but pictures or avatars do not load | Telegram media/CDN can use extra IPs outside the common MTProto ranges; in this tested case `91.105.192.100` and `194.221.250.50` went `direct` and timed out | Route observed Telegram media/CDN IPs through `vless-reality` |
| ChatGPT works in browser but mobile app says country is unavailable | Mobile app may use QUIC/HTTP3 over `UDP/443`, bypassing domain-based routing | Route `UDP/443` through `vless-reality` |
| Claude redirects to region unavailable page | Claude domains are not in the VPN route | Add `claude.com` and `anthropic.com` to the VPN route |
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

## Codex Workflow

This repository also keeps a small local Codex workflow so future debugging does
not start from zero every time.

```text
.codex/project-skills/
  keenetic-repo-triage/
  xray-routing-triage/
  public-config-sanitizer/
  macos-vpn-diagnostician/
docs/
  local-codex-workflow.md
  open-source-tooling-ru.md
tools/
  analyze_access_log.py
  sanitize_public_release.sh
  validate_xray_bundle.sh
  deploy_router.sh
artifacts/
  incidents/
  routing-candidates/
  release-checks/
```

The intended workflow is:

1. describe the symptom and the target device;
2. collect facts cheaply with a triage skill or junior agent;
3. make the smallest routing/config change;
4. validate JSON and restart XKeen;
5. confirm the service on the real target device;
6. run public config sanitization before any public commit.

See [`docs/local-codex-workflow.md`](docs/local-codex-workflow.md) for the
human-facing process.

Router deployment tooling is dry-run by default. It expects private configs
under `router-backup/private/xkeen-configs/` and requires `--apply` before it
uploads anything or restarts XKeen.

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

Keenetic, Netcraze, Hopper, NC-3811, KN-3811, XKeen, Entware, OPKG, Xray, VLESS Reality, BlancVPN, YouTube, Smart TV, Telegram, Telegram media, Telegram CDN, Claude, ChatGPT, ChatGPT mobile, OpenAI, Kino.pub, WOT Blitz, Tanks Blitz, QUIC, HTTP3, UDP 443, router VPN, KeeneticOS, OpenWrt alternative, VPN на роутере, YouTube на телевизоре, YouTube на Smart TV, ChatGPT на телефоне, Telegram на Keenetic, не грузятся картинки Telegram, Telegram media через VPN, обход блокировок на Keenetic, настройка XKeen, BlancVPN на роутере, VLESS на роутере.
