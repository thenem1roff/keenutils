обновление torrserver
```bash
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/torrserver | sh
```
torrserver watchdog
```bash
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/torr_watchdog | sh
```
стратегия general11 1.10.3 от flowseal (nfqws)
```bash
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/nfqws | sh
```
```bash
opkg update && opkg install ca-certificates wget-ssl jq
opkg remove wget-nossl 2>/dev/null
mkdir -p /opt/etc/opkg
echo "src/gz nfqws2-keenetic https://nfqws.github.io/nfqws2-keenetic/all" > /opt/etc/opkg/nfqws2-keenetic.conf
echo "src/gz nfqws-keenetic-web https://nfqws.github.io/nfqws-keenetic-web/all" > /opt/etc/opkg/nfqws-keenetic-web.conf
opkg update && opkg install nfqws2-keenetic nfqws-keenetic-web
```

## KeenUtils Installer (Entware)

Интерактивный установщик программ для Keenetic с Entware.

Запуск в shell Entware от root через SSH/Telnet:

```sh
opkg update && opkg install ca-certificates curl
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/install -o /tmp/keenutils-install.sh
sh /tmp/keenutils-install.sh
```

Не запускайте интерактивное меню через `curl | sh`: скрипт должен читать ответы с терминала.

Пункты: 1 nfqws, 2 nfqws2, 3 nfqws-web, 4 KeenKit, 5 HydraRoute Neo, 6 AWG Manager, 7 TorrServer, 99 список пакетов Entware, 00 выход.

- Сначала проверяются пакеты и ожидаемые файлы; nfqws и nfqws2 не устанавливаются поверх друг друга.
- Сторонние инсталляторы запускаются только после подтверждения; не вызывается общий `opkg upgrade`.
- TorrServer: первоначальная установка через `opkg`, обновление через существующий скрипт (только aarch64), кеш через API и опциональный watchdog с проверкой обеих задач Cron.
- Кеш создаётся в `/tmp/mnt/<том-с-Entware>/tscashe` только если накопитель проверен; иначе настройки не меняются.
- `UseDisk` и `TorrentsSavePath` меняются через локальный API `/settings`; исходный JSON сохраняется в `/opt/var/backups/keenutils` с правами 600. Сервер останавливать для этого не требуется.
- Чтобы расширить меню, добавьте функцию `install_*`, строку в `menu()` и ветку в главном `case`.

Проверка расположения файлов и пакетов не гарантирует функциональную настройку каждой сторонней программы; сверяйтесь с требованиями выбранного проекта.
