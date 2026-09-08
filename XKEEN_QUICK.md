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
cd /Users/igor/Documents/VPN
./tools/blanc-country.sh near
```

Для конкретной страны:

```bash
./tools/blanc-country.sh fi
```

Коды: `ee` Эстония, `se` Швеция, `fi` Финляндия, `pl` Польша, `lt` Литва,
`ch` Цюрих, `nl` Нидерланды. Для последовательной проверки близких стран:
`./tools/blanc-country.sh near`. При первом запуске ссылка подписки один раз
вводится в защищённый запрос macOS Keychain. После успешной проверки XKeen
остаётся включённым; при неудаче предыдущая конфигурация восстанавливается.

## Автоматическое восстановление VLESS

Монитор на роутере проверяет YouTube и ChatGPT раз в 3 минуты. После двух
ошибок подряд он перебирает сохранённые страны и оставляет первый рабочий
узел. Между переключениями действует пауза 20 минут. Если все сохранённые
узлы и `last-good` недоступны, монитор оставляет Xray запущенным для правил
`direct`, но фиксирует `health: degraded` и `refresh: required`. Счётчик
ошибок больше не сбрасывается в ложный ноль.

```bash
ssh root@192.168.1.1 'blanc-auto status'
ssh root@192.168.1.1 'blanc-auto test'
ssh root@192.168.1.1 'blanc-auto on'
ssh root@192.168.1.1 'blanc-auto off'
ssh root@192.168.1.1 'blanc-auto recover'
ssh root@192.168.1.1 'blanc-auto needs-refresh'
```

`off` выключает только автоматику и не останавливает XKeen. Для немедленной
ручной проверки и возможного переключения:

```bash
ssh root@192.168.1.1 'blanc-auto run; blanc-auto status'
```

Принудительно перебрать весь сохранённый пул, включая текущую страну:

```bash
ssh root@192.168.1.1 'blanc-auto force; blanc-auto status'
```

## Страховка от устаревшей подписки

Роутер не хранит приватную ссылку Blanc: она остаётся в macOS Keychain.
LaunchAgent раз в 5 минут проверяет VPN. Пока VLESS здоров, он ничего не
скачивает и не переключает. После полного отказа сохранённого пула агент
загружает свежую подписку из Keychain, валидирует новые профили на роутере,
запускает failover и показывает уведомление только при аварии или
восстановлении.

Установка или обновление:

```bash
cd /Users/igor/Documents/VPN
./tools/install-blanc-auto.sh
./tools/install-blanc-refresh-agent.sh
```

Ручная проверка того же контура:

```bash
./tools/blanc-refresh-if-needed.sh
```

Лог macOS: `~/Library/Logs/blanc-router-refresh.log`.
Исполняемая копия агента хранится вне `Documents`, в
`~/Library/Application Support/Blanc Router Monitor/bin`, потому что macOS
может запрещать launchd запускать фоновые сценарии непосредственно из
пользовательской папки `Documents`.
