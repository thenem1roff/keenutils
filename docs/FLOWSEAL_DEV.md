# Конвертер Flowseal → nfqws2 для KeenUtils (пункт 77)

## Текущий этап: Shell + AWK без Python на Keenetic

Код конвертера работает через POSIX sh, AWK и Lua-совместимость. **Python на роутер
не загружается и не устанавливается.** Оригинальный конвертер на Python хранится
исключительно в tests/reference/ для сравнительных тестов GitHub Actions.

Пункт 77 в основном install запускает отдельный локально установленный модуль.
Пункт 0 внутри модуля возвращает в **тот же** главный экран KeenUtils.

Доступно:
- Получение списка профилей general*.bat из ZIP последнего официального релиза Flowseal
- Выбор ALT / FAKE / EXP и других стратегий, подтверждения [Y/n] с ответом Y по Enter
- Игровые порты TCP/UDP с ответом Y по Enter
- Парсинг winws-аргументов, fake, hostfakesplit, multisplit, multidisorder,
  fakedsplit, fakeddisorder, syndata и нескольких последовательных правил
- Lua-функция для hostfakesplit altorder=1 из оригинального MIT-конвертера
- Сопоставление базовых списков Flowseal со штатными списками nfqws2:
  list-general → user.list; list-exclude → exclude.list;
  ipset-all → ipset.list; ipset-exclude → ipset_exclude.list
- Дополнительные списки (например, list-google) и бинарные шаблоны сохраняются
  **отдельно** в каталоге результата (без записи в системные файлы)
- Автоматическое сохранение стратегии с названием и номером версии Flowseal
- Просмотр сохранённых стратегий, отчётов, предупреждений и удаление
- Пересоздание стратегии с переносом предыдущей редакции в history/

**Ограничение:** это этап безопасной конвертации. Применение к рабочему
/opt/etc/nfqws2/nfqws2.conf, установка BIN/LIST, проверка службы, гибридный режим
и откат после применения пока недоступны. Программа **не пишет** в системные
каталоги nfqws2 и **не перезапускает** службу.

Конвертация по синтаксису не гарантирует эффективности стратегии у конкретного
провайдера. Совместимость с актуальным nfqws2 надо проверять отдельно.

## Папки и файлы

- /opt/bin/keenutils-flowseal — локальный загрузчик обычной версии
- /opt/etc/keenutils/flowseal/current.version — версия установленного модуля
- /opt/etc/keenutils/flowseal/runtime/<версия>/ — Shell + AWK + Lua + MIT
- /opt/etc/keenutils/flowseal/strategies/ — автоматически сохранённые результаты
- /opt/etc/keenutils/flowseal/history/ — предыдущие редакции пересозданных стратегий
- /opt/etc/keenutils/flowseal/tmp/ — временный ZIP и распаковка, очищаются после операции

Папка стратегии содержит nfqws2.conf, info.json, stats.txt, REPORT.md,
а также подкаталоги lists/ и blobs/ для необходимых дополнительных файлов.

В тестовом режиме используется отдельное хранилище:
- /opt/bin/keenutils-flowseal-dev
- /opt/etc/keenutils/flowseal-dev/

Стабильная копия от тестов не заменяется.

## Тестировать через install без замены команды utils

Скачайте install из отдельной ветки разработки:

~~~sh
wget -O /tmp/keenutils-flowseal-dev-install.sh \
  https://raw.githubusercontent.com/thenem1roff/keenutils/feature/flowseal-converter-77/install
~~~

Запустите от root в Entware:

~~~sh
KEENUTILS_DISABLE_UPDATE_CHECK=1 \
KEENUTILS_FLOWSEAL_DEV_MODE=1 \
KEENUTILS_FLOWSEAL_REF=feature/flowseal-converter-77 \
sh /tmp/keenutils-flowseal-dev-install.sh
~~~

Затем выберите **77 → 1**, выберите стратегию и игровые порты. После
конвертации результат автоматически окажется в **77 → 2**. Нажатие 0
возвращает сначала в подменю, затем из модуля в тестовый install. Обычная
команда utils по-прежнему запускает основную установленную версию.

При первом импорте могут понадобиться Entware-пакеты jq и unzip (программа
предлагает их установить). AWK обычно входит в BusyBox. Python не требуется.

## Как обновляется модуль

При входе в 77 запрашивается небольшой файл flowseal.version. Если он не
изменился, исполняется локальная версия из runtime/. Если версия изменилась,
код загружается в отдельный каталог, проверяется и только после успешной
подготовки активируется. При недоступности GitHub ранее установленный модуль
остаётся доступен.

В **режиме разработки** install может повторно загрузить только небольшой
файл начального загрузчика — это нужно для миграции со старого Python-прототипа.
Сам код Shell + AWK повторно не скачивается при совпадающей версии.

ZIP Flowseal загружается при выборе «Добавить стратегию», а не при открытии
основного меню. Временная распаковка затем удаляется. Сохранённые стратегии
переживают обновления модуля.

**Разработчику:** при каждом изменении flowseal_converter, menu.sh, converter.awk
или Lua-функции увеличивайте flowseal.version.

## Автоматические проверки

Без Python:

~~~sh
sh -n install && sh -n flowseal_converter && sh -n modules/flowseal/menu.sh
sh tests/flowseal-converter-regressions.sh
~~~

В GitHub Actions отдельно выполняются сравнительные тесты Shell/AWK
против исходного конвертера Python на зафиксированных оригинальных .bat
Flowseal. **Этот Python нужен только тестовому окружению GitHub, не Keenetic.**
Есть также проверка возврата из пункта 77 в главное меню.

## Следующие задачи

1. Протестировать на реальном Keenetic/Entware разных архитектур (особенно jq, unzip, AWK).
2. Проверить полный набор профилей конкретного выпуска Flowseal, выходные
   аргументы и влияние сопоставления стандартных списков nfqws2.
3. Привязать отдельные BIN/LIST к имени стратегии и версии, исключить коллизии.
4. Реализовать проверку с установленным nfqws2; затем перенос файлов,
   резервные копии, применение и откат.
5. Реализовать гибридный режим (при необходимости), не затрагивая основное меню install.

Исходный MIT-конвертер:
https://github.com/Sxlenium/zapret-keenetic-converter
Лицензия и copyright: modules/flowseal/LICENSE

Flowseal: https://github.com/Flowseal/zapret-discord-youtube
Фикстуры .bat в tests/fixtures/flowseal получены по лицензии MIT Flowseal.
