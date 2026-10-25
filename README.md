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

### Самостоятельные TorrServer-скрипты

- `torr_watchdog`: перед выполнением проверяет существующий watchdog, обе строки Cron, синтаксис и доступность команд. Если всё готово — выходит без изменений. Иначе через `opkg` ставит только недостающие зависимости (включая `curl`, `procps-ng-pgrep`, `psmisc`, `cron` при отсутствии), дополняет Cron без дублирования, не перезаписывает существующий файл watchdog и затем повторяет проверки.
- `torrserver`: перед обновлением проверяет команды и автоматически устанавливает отсутствующие зависимости Entware. Установленный бинарник и служба обязательны; скрипт не изменяет расписание Cron или watchdog.
- В обоих сценариях `opkg update` вызывается только когда требуется установить пакет. Общего `opkg upgrade` нет. Проверки на реальном роутере пока не выполнялись.

## Сторонние проекты

KeenUtils — независимый проект, не связанный с авторами перечисленных программ. Все права на сторонние программы принадлежат их правообладателям. Установка выполняется из официальных источников. Условия использования определяются лицензиями соответствующих проектов.

- [nfqws](https://github.com/nfqws/nfqws-keenetic)
- [nfqws2](https://github.com/nfqws/nfqws2-keenetic)
- [nfqws-web](https://github.com/nfqws/nfqws-keenetic-web)
- [KeenKit](https://github.com/spatiumstas/KeenKit)
- [HydraRoute Neo](https://github.com/Ground-Zerro/HydraRoute/tree/main/Neo)
- [AWG Manager](https://github.com/hoaxisr/awg-manager)
- [TorrServer](https://github.com/YouROK/TorrServer)

KeenUtils не является официальным установщиком перечисленных проектов. Ссылки ведут на их исходные репозитории; авторство и лицензии следует проверять в соответствующих проектах.
