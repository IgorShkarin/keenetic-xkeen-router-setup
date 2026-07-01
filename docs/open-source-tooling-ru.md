# Open-Source Tooling For XKeen + Xray

Короткий вывод: готового зрелого набора именно под `Keenetic / Netcraze + Entware + XKeen + Xray + selective routing` почти нет.

Практичный путь:

1. брать готовые upstream-компоненты для `geosite`, `geoip`, проверки Xray-конфигов и примеров;
2. не ставить тяжелые панели на роутер без необходимости;
3. держать свой тонкий pipeline вокруг `access.log`, проверки JSON, staged apply и rollback.

## Что брать готовым

| Инструмент | Зачем |
| --- | --- |
| [Xray-core](https://github.com/XTLS/Xray-core) | Проверка и запуск Xray-конфигов |
| [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) | Источник доменных категорий для geosite |
| [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) | Готовые `geoip.dat` и `geosite.dat` |
| [v2fly/geoip](https://github.com/v2fly/geoip) | IP-базы для маршрутизации |
| [Xray-examples](https://github.com/XTLS/Xray-examples) | Reference-конфиги |
| [xray-knife](https://github.com/lilendian0x00/xray-knife) | Разбор и тестирование subscription/config links на рабочей машине |
| [jq](https://github.com/jqlang/jq) | Детерминированная работа с JSON |
| [lnav](https://github.com/tstack/lnav) | Удобный просмотр логов локально |

## Что лучше написать самим

- `analyze_access_log.py` - вытащить домены/IP/порты/outbound из Xray access log.
- `suggest_routing_patch.py` - предложить минимальные routing-кандидаты.
- `validate_xray_bundle.sh` - проверить JSON и, при наличии Xray, семантику конфига.
- `deploy_router.sh` - безопасно выложить config bundle на роутер через SSH с backup.

## Почему не искать бесконечно

Ценность проекта не в том, чтобы найти идеальную панель. Ценность в воспроизводимом контуре:

- symptoms -> logs
- logs -> candidates
- candidates -> minimal patch
- patch -> validation
- validation -> deploy
- deploy -> README/backups

Это быстрее, дешевле и надежнее, чем каждый раз руками угадывать домены.
