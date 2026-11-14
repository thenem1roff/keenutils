# KeenUtils

**Установщик и менеджер программ для роутеров Keenetic с Entware.**

KeenUtils объединяет популярные сетевые утилиты в одном консольном меню. Помогает устанавливать программы, запускать доступные меню управления, обновлять и удалять компоненты, не разыскивая каждый раз отдельные команды.

## Установка

Запустите в терминале Entware от пользователя `root` (через SSH):

```sh
opkg update && opkg install ca-certificates wget-ssl
wget -O /tmp/keenutils-install.sh https://raw.githubusercontent.com/thenem1roff/keenutils/main/install
sh /tmp/keenutils-install.sh
```

После установки откройте меню командой:

```sh
utils
```

Команда `keenutils` также поддерживается.

## Программы

| № | Программа | Для чего |
| :--: | --- | --- |
| 1 | **nfqws** | Обработка трафика и обход DPI-ограничений. |
| 2 | **nfqws2** | Новая версия инструментов обхода DPI. |
| 3 | **nfqws-web** | Веб-интерфейс для управления nfqws. |
| 4 | **nfqws-menu** | Выбор и настройка стратегий nfqws. |
| 5 | **KeenKit** | Набор инструментов для Keenetic в отдельном меню. |
| 6 | **HydraRoute Neo** | Маршрутизация трафика через выбранные подключения. |
| 7 | **AWG Manager** | Управление туннелями AmneziaWG. |
| 8 | **TorrServer** | Торрент-стриминг, обновление и обслуживание службы. |

## Дополнительные инструменты

| № | Действие |
| :--: | --- |
| **77** | **Flowseal → nfqws2** — конвертация, сохранение и переключение стратегий с резервным копированием и откатом. |
| **88** | Удаление программ и очистка их остатков с подтверждением. |
| **99** | Обновление KeenUtils. |
| **00** | Выход. |

В меню KeenUtils пустой **Enter** возвращает на предыдущий уровень или завершает работу. В меню сторонних программ действуют их собственные команды.

**Важно:** применение конвертированной стратегии меняет конфигурацию nfqws2 и может повлиять на сеть. Перед использованием на основном роутере рекомендуется проверить работу на отдельной Entware. Подробности: [конвертер Flowseal и откат](docs/FLOWSEAL_DEV.md).

## Сторонние проекты

KeenUtils — независимый проект, не являющийся официальным продуктом перечисленных авторов. Права на сторонние программы и условия их использования определяются соответствующими правообладателями и лицензиями.

- [nfqws](https://github.com/nfqws/nfqws-keenetic)
- [nfqws2](https://github.com/nfqws/nfqws2-keenetic)
- [nfqws-web](https://github.com/nfqws/nfqws-keenetic-web)
- [nfqws-menu](https://github.com/rndnaame/nfqws-menu)
- [KeenKit](https://github.com/spatiumstas/KeenKit)
- [HydraRoute Neo](https://github.com/Ground-Zerro/HydraRoute/tree/main/Neo)
- [AWG Manager](https://github.com/hoaxisr/awg-manager)
- [TorrServer](https://github.com/YouROK/TorrServer)
- [Flowseal](https://github.com/Flowseal/zapret-discord-youtube)

Исходная реализация конвертации адаптирована из [Sxlenium/zapret-keenetic-converter](https://github.com/Sxlenium/zapret-keenetic-converter) по лицензии MIT; оригинальный текст лицензии сохранён в [modules/flowseal/LICENSE](modules/flowseal/LICENSE).
