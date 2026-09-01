# XKeen — быстрые команды

Подключись к домашнему Wi-Fi и копируй нужную команду целиком.

## Статус

```bash
ssh root@192.168.1.1 'xkeen -status'
```

## Выключить VPN на роутере

```bash
ssh root@192.168.1.1 'xkeen -stop; xkeen -status'
```

## Включить VPN на роутере

```bash
ssh root@192.168.1.1 'xkeen -start; xkeen -status'
```

## Перезапустить только XKeen

```bash
ssh root@192.168.1.1 'xkeen -restart; xkeen -status'
```

## Если SSH не подключается

Скопируй команду и пришли весь результат:

```bash
ipconfig getifaddr en0; route -n get 192.168.1.1; ping -c 2 192.168.1.1; nc -vz -w 3 192.168.1.1 22; nc -vz -w 3 192.168.1.1 2022
```

## Тест YouTube и ChatGPT через VLESS

Пока не установлен. Для него требуется один раз добавить локальный SOCKS-вход
`127.0.0.1:10808`, проверить конфигурацию и перезапустить XKeen.
