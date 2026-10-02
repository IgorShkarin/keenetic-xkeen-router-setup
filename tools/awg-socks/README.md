# Loopback SOCKS bridge for AmneziaWG 3.x

Uses the official AmneziaWG userspace network stack. It does not create a
kernel interface or alter system routes, DNS, or firewall rules. Target DNS
queries run inside AWG. The only listener is `127.0.0.1:10932`; TCP CONNECT
only, with 64 simultaneous connections maximum. No credentials or domains are
logged. Config files must remain private, with mode 600.

Verified on ARM64 KeeneticOS 5.1.6 with an existing Premium AWG 3.x export.
An isolated test and production Xray both returned HTTPS 204/200; a 1 MiB
download completed. Observed RSS was about 9 MiB; this is not a peak-load bound.
Supervisor uses `GOMAXPROCS=2` and a soft `GOMEMLIMIT=64MiB`.

## Rebuild

Official source revision: `b5928efb6ca19f0153958460c3d141f04abc5c2e`.
The deployment used Go 1.26.8, linux/arm64, CGO disabled. Source archive
SHA256 (the master archive fetched for this deployment):
`7ac289b5d33f78b23d44e6568722f0cbb23eba51f38c53ab1799c53ad83acedf`.
Deployed binary SHA256:
`60f65dc857634124c4a95993f835891d4b002924ba8f7840a9be285b54892255`.

Check out that revision of `https://github.com/amnezia-vpn/amneziawg-go`, copy
`main.go` and `main_test.go` into its `cmd/router-socks/`, then run from its root:

```sh
go test -v -timeout 20s ./cmd/router-socks
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o awg-socks ./cmd/router-socks
```

Install the binary as `/opt/bin/home-awg-socks`, an existing private export as
`/opt/etc/home-vpn/amnezia.conf`, and `../home-vpn-amnezia.sh` as
`/opt/sbin/home-vpn-amnezia`. Check the private file with `-check` first.
`../S98home-amnezia` starts it on Entware boot; cron calls `ensure` each minute.
Keep exact backups and prove the separate SOCKS route before changing Xray.
An Xray SOCKS outbound pointing at the loopback listener integrates this bridge
as `reserve-amnezia`. Preserve the primary and the other reserve profiles.

Sources: [official netstack example](https://github.com/amnezia-vpn/amneziawg-go/blob/b5928efb6ca19f0153958460c3d141f04abc5c2e/tun/netstack/examples/http_client.go),
[official router compatibility guide](https://docs.amnezia.org/documentation/instructions/keenetic-os-awg/).

`../amnezia_refresh_profile.py` is a manual diagnostic for Premium VLESS exports
with installed AmneziaVPN 5.0.1. It reads a privately exported subscription and
reuses the client identity. Its binary public-key lookup is version dependent.
Refreshing a profile does not prove it works; it is not scheduled or used by
the deployed AWG reserve.
