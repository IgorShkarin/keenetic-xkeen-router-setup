# Netcraze/Keenetic Hopper NC-3811 XKeen Backup

Working state captured after YouTube, Kino.pub, WOT Blitz, Telegram, Claude,
and ChatGPT mobile started working through XKeen/Xray on devices connected to
the router.

## Коротко

Это санитизированная резервная копия рабочей настройки **XKeen + Xray + VLESS Reality** для **Netcraze / Keenetic Hopper NC-3811**.

Цель: сохранить структуру и безопасные примеры конфигов, чтобы можно было восстановить настройку роутерного VPN/proxy для YouTube, Smart TV, Telegram, Claude, ChatGPT mobile и других сервисов без публикации приватных VPN-ключей.

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

The working routing file also includes explicit rules for services that were
not fully covered by the generated config:

- YouTube / Smart TV
- Kino.pub
- WOT Blitz / Tanks Blitz
- Telegram domains and Telegram MTProto IP ranges
- Claude / Anthropic
- ChatGPT / OpenAI web and mobile domains
- `UDP/443` through `vless-reality` for mobile apps that use QUIC/HTTP3

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

## Public files

The public folder contains only safe examples:

```text
router-backup/public/xkeen-configs/03_inbounds.json
router-backup/public/xkeen-configs/04_outbounds.template.json
router-backup/public/xkeen-configs/05_routing.fixed-no-v2fly.json
```

Replace the template outbound file with your own private `04_outbounds.json` only on the router or in a private backup.

## Restore

Copy the working files to the router. If Entware Dropbear does not provide
`/opt/libexec/sftp-server`, `scp` may fail; use SSH, the router terminal, or add
an SFTP server first.

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

For Entware Dropbear key auth, put public keys here:

```text
/opt/etc/dropbear/authorized_keys
```

## Follow-up

- Create Keenetic internet policy named exactly `xkeen` if per-device routing is needed.
- Assign target TV or other clients to the `xkeen` policy.
- Change default Entware root password from `keenetic`.
- After a router reboot, verify `xkeen -status`.

## Keywords

Keenetic, Netcraze, Hopper, NC-3811, KN-3811, XKeen, Entware, OPKG, Xray, VLESS Reality, BlancVPN, router VPN, KeeneticOS, OpenWrt alternative, YouTube на Smart TV, VPN на роутере, Telegram на Keenetic, ChatGPT mobile, Claude, Anthropic, Kino.pub, WOT Blitz, Tanks Blitz, QUIC, HTTP3, UDP 443, BlancVPN на роутере, VLESS на роутере.
