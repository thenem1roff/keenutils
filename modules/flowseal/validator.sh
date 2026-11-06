#!/bin/sh
# Read-only validator for a saved Flowseal strategy. NEVER deploys or restarts.
# Usage: sh validator.sh /opt/etc/keenutils/flowseal*/strategies/<id>
set -u
export PATH=/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin
if [ "$#" -ne 1 ] || [ ! -d "$1" ] || [ -L "$1" ]; then
    printf 'Ошибка: не найдена папка сохранённой стратегии.\n' >&2
    exit 1
fi
saved=$1
conf="$saved/nfqws2.conf"
if [ ! -f "$conf" ] || [ -L "$conf" ]; then
    printf 'Ошибка: отсутствует конфигурация.\n' >&2
    exit 1
fi
if ! sh -n "$conf"; then
    printf 'Ошибка: некорректный синтаксис конфигурации.\n' >&2
    exit 1
fi
if grep -Eq '%(BIN|LISTS|GameFilterTCP|GameFilterUDP)%|%~dp0' "$conf"; then
    printf 'Ошибка: остались неразрешённые переменные Flowseal.\n' >&2
    exit 1
fi
if ! grep -q '^NFQWS_ARGS=' "$conf" ||
    ! grep -q '^NFQWS_BASE_ARGS=' "$conf" ||
    ! grep -q '^TCP_PORTS=' "$conf" ||
    ! grep -q '^UDP_PORTS=' "$conf"; then
    printf 'Ошибка: отсутствуют обязательные параметры nfqws2.\n' >&2
    exit 1
fi

printf 'Синтаксис конфигурации: OK\n'
needed=0
missing=0
conflicts=0
references=$(mktemp /tmp/.keenutils-flowseal-validate.XXXXXX) || exit 1
trap 'rm -f "$references"' EXIT INT TERM
# Extract only safe, literal nfqws2 paths; never source or evaluate the config.
grep -Eo '/opt/etc/nfqws2/(lists|blobs)/[A-Za-z0-9._-]+' "$conf" |
    sort -u > "$references" || :
while IFS= read -r dest; do
    [ -n "$dest" ] || continue
    case "$dest" in
        /opt/etc/nfqws2/lists/*)
            stored="$saved/lists/$(basename "$dest")" ;;
        /opt/etc/nfqws2/blobs/*)
            stored="$saved/blobs/$(basename "$dest")" ;;
        *) continue ;;
    esac
    if [ -f "$dest" ]; then
        if [ -f "$stored" ] && ! cmp -s "$stored" "$dest"; then
            printf 'Конфликт с существующим файлом: %s\n' "$dest"
            conflicts=$((conflicts+1))
        else
            printf 'Доступен: %s\n' "$dest"
        fi
    elif [ -f "$stored" ]; then
        printf 'Требует переноса: %s\n' "$stored"
        needed=$((needed+1))
    else
        printf 'Отсутствует файл: %s\n' "$dest"
        missing=$((missing+1))
    fi
done < "$references"

if [ -f "$saved/info.json" ] && command -v jq >/dev/null 2>&1; then
    warnings=$(jq -r '.warnings // 0' "$saved/info.json" 2>/dev/null) || warnings=0
    printf 'Предупреждения конвертации: %s\n' "$warnings"
else warnings='неизвестно';fi
if ! command -v opkg >/dev/null 2>&1 ||
    ! opkg list-installed nfqws2-keenetic 2>/dev/null | grep -q '^nfqws2-keenetic '; then
    printf 'Внимание: установленный пакет nfqws2-keenetic не подтверждён.\n'
    missing=$((missing+1))
fi
if [ "$needed" -eq 0 ] && [ "$missing" -eq 0 ] && [ "$conflicts" -eq 0 ] &&
   [ "$warnings" = 0 ]; then
    printf 'Статическая проверка: OK. Проверка запуска и совместимости НЕ выполнена.\n'
    exit 0
fi
printf 'Проверка с замечаниями: перенос=%s, отсутствует=%s, конфликтов=%s.\n' \
    "$needed" "$missing" "$conflicts"
printf 'Применение пока отключено. Сохранённая конфигурация не изменена.\n'
exit 2
