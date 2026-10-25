## KeenUtils Installer (Entware)

Интерактивный установщик программ для Keenetic с Entware.

Запуск в shell Entware от root через SSH/Telnet:

```sh
wget -O /tmp/keenutils-install.sh https://raw.githubusercontent.com/thenem1roff/keenutils/main/install && sh /tmp/keenutils-install.sh
```

Если установленный `wget` не поддерживает HTTPS, сначала установите его SSL-версию:

```sh
opkg update && opkg install ca-certificates wget-ssl
```

**Повторный запуск:** просто введите `keenutils` в терминале. Скачивать установщик заново не нужно.

### Главное меню

| Пункт | Программа | Назначение |
| --- | --- | --- |
| **1** | **nfqws** | Обход DPI-блокировок, первая версия. |
| **2** | **nfqws2** | Обход DPI-блокировок, вторая версия. |
| **3** | **nfqws-web** | Веб-интерфейс для управления nfqws/nfqws2. |
| **4** | **nfqws-menu** | Оригинальное меню выбора и установки стратегий обхода блокировок. |
| **5** | **KeenKit** | Набор утилит для настройки и обслуживания роутера Keenetic. |
| **6** | **HydraRoute Neo** | Маршрутизация выбранного трафика через нужные подключения и туннели. |
| **7** | **AWG Manager** | Установка и управление VPN-туннелями AmneziaWG. |
| **8** | **TorrServer** | Потоковое воспроизведение торрентов с роутера; открывает отдельное подменю. |
| **88** | **Обновить KeenUtils** | Скачать новую версию самого меню из этого репозитория. |
| **99** | **Установленные приложения** | Показать основные установленные программы Entware (без системных библиотек). |
| **00** | **Выход** | Закрыть меню. |

### Подменю TorrServer (пункт 8)

| Пункт | Действие |
| --- | --- |
| **1** | Установить TorrServer. |
| **2** | Обновить TorrServer. |
| **3** | Установить или проверить watchdog — автоматический контроль работы TorrServer. |
| **4** | Настроить дисковый кеш на накопителе с Entware. |
| **0** | Вернуться в главное меню. |

KeenUtils проверяет, установлена ли программа, прежде чем выполнять установку. Ссылки на официальные установщики хранятся в [`sources.conf`](sources.conf), а их доступность регулярно проверяется. Для подтверждений используются английские `y/n`.

## Сторонние проекты

KeenUtils — независимый проект, не связанный с авторами перечисленных программ. Все права на сторонние программы принадлежат их правообладателям. Установка выполняется из официальных источников. Условия использования определяются лицензиями соответствующих проектов.

- [nfqws](https://github.com/nfqws/nfqws-keenetic)
- [nfqws2](https://github.com/nfqws/nfqws2-keenetic)
- [nfqws-web](https://github.com/nfqws/nfqws-keenetic-web)
- [nfqws-menu](https://github.com/rndnaame/nfqws-menu)
- [KeenKit](https://github.com/spatiumstas/KeenKit)
- [HydraRoute Neo](https://github.com/Ground-Zerro/HydraRoute/tree/main/Neo)
- [AWG Manager](https://github.com/hoaxisr/awg-manager)
- [TorrServer](https://github.com/YouROK/TorrServer)

KeenUtils не является официальным установщиком перечисленных проектов. В частности, исходный код nfqws-menu не включён в KeenUtils. Ссылки ведут на их исходные репозитории; авторство и лицензии следует проверять в соответствующих проектах.
