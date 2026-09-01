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

## Тест Blanc VLESS: YouTube + ChatGPT

Запускает XKeen, делает запросы с самого роутера через локальный тестовый вход,
показывает HTTP-результат и строки с outbound `vless-reality`, затем выключает
XKeen:

```bash
ssh root@192.168.1.1 'set +e; xkeen -start; sleep 2; curl --proxy socks5h://127.0.0.1:10808 -sS -o /dev/null --connect-timeout 10 --max-time 20 -w "YouTube http=%{http_code} total=%{time_total}s\n" https://www.youtube.com/generate_204; curl --proxy socks5h://127.0.0.1:10808 -sS -o /dev/null --connect-timeout 10 --max-time 20 -w "ChatGPT http=%{http_code} total=%{time_total}s\n" https://chatgpt.com/cdn-cgi/trace; echo "--- route log ---"; tail -n 120 /opt/var/log/xray/access.log | grep -Ei "codex-test-socks.*(youtube|chatgpt).*vless-reality" | tail -n 10; xkeen -stop; xkeen -status'
```

`HTTP 000` означает timeout/ошибку соединения. Строка
`[codex-test-socks >> vless-reality]` подтверждает выбор маршрута Blanc;
сама по себе она ещё не означает, что внешний ответ получен.

## Сменить страну одной командой

Скрипт скачивает подписку Blanc, выбирает узел, проверяет его и откатывает
неудачный вариант:

```bash
./tools/blanc-country.sh fi
```

Коды: `ee` Эстония, `se` Швеция, `fi` Финляндия, `pl` Польша, `lt` Литва,
`ch` Цюрих, `nl` Нидерланды. Для последовательной проверки близких стран:
`./tools/blanc-country.sh near`. При первом запуске ссылка подписки один раз
вводится в защищённый запрос macOS Keychain. После успешной проверки XKeen
остаётся включённым; при неудаче предыдущая конфигурация восстанавливается.
