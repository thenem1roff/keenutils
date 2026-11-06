#!/bin/sh
# KeenUtils Flowseal transaction manager for nfqws2-keenetic (Entware).
# Actions: check DIR | preview DIR | apply DIR | undo | status | history
# No Python, no eval, no sourcing Flowseal files, no installer execution.
set -u
umask 077
PATH=/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

STORE_HOME=${KEENUTILS_FLOWSEAL_HOME:-/opt/etc/keenutils/flowseal}
TEST_MODE=${KEENUTILS_FLOWSEAL_TEST_ONLY:-0}
ROOT=/opt
if [ "$TEST_MODE" = 1 ] && [ -n "${KEENUTILS_FLOWSEAL_TEST_ROOT:-}" ]; then
    ROOT=$KEENUTILS_FLOWSEAL_TEST_ROOT
fi
case "$ROOT" in /*) : ;; *) echo 'Неверный корень Entware.' >&2;exit 1;; esac
case "$ROOT" in *..*|*/.) echo 'Небезопасный корень Entware.' >&2;exit 1;; esac
SYSTEM="$ROOT/etc/nfqws2"
CONF="$SYSTEM/nfqws2.conf"
SERVICE="$ROOT/etc/init.d/S51nfqws2"
BIN="$ROOT/usr/bin/nfqws2"
STORE="$STORE_HOME/deployments"
BACKUPS="$STORE/backups"
LOCK="$STORE/.lock"
ACTIVE="$STORE/active"
LATEST="$STORE/latest"
STAGE=''
TRANSACTION=0
BACKUP=''
LOCKED=0
VERB=${1:-}
SAVED=${2:-}

say() { printf '%s\n' "$*"; }
err() { printf 'Ошибка: %s\n' "$*" >&2; }
die() { err "$*"; return 1; }
check_plain_dir() {
    [ -d "$1" ] && [ ! -L "$1" ]
}
check_plain_file() {
    [ -f "$1" ] && [ ! -L "$1" ]
}
real_file() {
    # Convert literal /opt references in generated configs to test root.
    case "$1" in
        /opt/etc/nfqws2/*) printf '%s%s\n' "$ROOT" "${1#/opt}" ;;
        *) return 1 ;;
    esac
}
service_running() {
    [ -x "$SERVICE" ] || return 1
    "$SERVICE" status 2>/dev/null | grep -Fq 'Service NFQWS2 is running'
}
service_restore() {
    previous=$1
    if [ "$previous" = yes ]; then
        if service_running; then "$SERVICE" restart; else "$SERVICE" start; fi
    else
        if service_running; then "$SERVICE" stop; else return 0; fi
    fi
}
safe_file_path() {
    case "$1" in
        /opt/etc/nfqws2/lists/*|/opt/etc/nfqws2/blobs/*|/opt/etc/nfqws2/lua/*) : ;;
        *) return 1 ;;
    esac
    name=${1##*/}
    case "$name" in ''|.|..|*..*|*[!A-Za-z0-9._-]*) return 1 ;; esac
    [ -n "$name" ]
}
ensure_paths() {
    [ "$ROOT" = /opt ] || [ "$TEST_MODE" = 1 ] || return 1
    check_plain_dir "$SYSTEM" || return 1
    for p in "$SYSTEM/lists" "$SYSTEM/blobs" "$SYSTEM/lua"; do
        check_plain_dir "$p" || return 1
    done
    check_plain_file "$CONF" && [ -x "$SERVICE" ] && [ -x "$BIN" ] || return 1
    command -v awk >/dev/null && command -v grep >/dev/null &&
        command -v sort >/dev/null && command -v cmp >/dev/null || return 1
}
ensure_saved() {
    case "$SAVED" in
        "$STORE_HOME"/strategies/*) : ;;
        *) return 1 ;;
    esac
    case "$SAVED" in *..*|*//*) return 1 ;; esac
    check_plain_dir "$SAVED" && check_plain_file "$SAVED/nfqws2.conf" || return 1
    check_plain_file "$SAVED/info.json" || return 1
    [ -z "${SAVED##*/}" ] && return 1
    return 0
}
validate_generated() {
    savedconf=$1
    sh -n "$savedconf" || { err 'Синтаксис подготовленного конфига некорректен.'; return 1; }
    for key in ISP_INTERFACE NFQWS_BASE_ARGS NFQWS_ARGS NFQWS_ARGS_CUSTOM \
        NFQWS_ARGS_QUIC NFQWS_ARGS_UDP NFQWS_EXTRA_ARGS NFQWS_ARGS_IPSET \
        TCP_PORTS UDP_PORTS NFQUEUE_NUM POLICY_NAME USER; do
        grep -q "^$key=" "$savedconf" || {
            err "Обязательный параметр $key отсутствует."
            return 1
        }
    done
    if grep -Eq '%(BIN|LISTS|GameFilterTCP|GameFilterUDP)%|%~dp0' "$savedconf"; then
        err 'В конфиге остались переменные Windows.'
        return 1
    fi
    if [ -s "$SAVED/diagnostics.tsv" ] && grep -q '^warning' "$SAVED/diagnostics.tsv"; then
        err 'Стратегия содержит предупреждения конвертации. Применение блокировано.'
        return 1
    fi
}
prepare_candidate() {
    savedconf="$SAVED/nfqws2.conf"
    validate_generated "$savedconf" || return 1
    # Keep settings that are tied to THIS Entware/router. Do not source
    # the existing shell config; read only literal scalar assignment lines.
    if ! awk -F= '
        BEGIN {
            split("ISP_INTERFACE IPV6_ENABLED POLICY_NAME POLICY_EXCLUDE NFQUEUE_NUM USER LOG_LEVEL LOG_DEBUG_PATH CONFIG_VERSION", a, " ")
            for(i in a) keep[a[i]]=1
        }
        FNR==NR {
            if(($1 in keep) && $0 ~ /^[A-Z_]+=/) {
                v=substr($0,index($0,"=")+1)
                if(v ~ /[;\`$\\<>|&]/ || v ~ /\(/ || v ~ /\)/) bad=1
                else old[$1]=$0
            }
            next
        }
        ($1 in old) && $0 ~ /^[A-Z_]+=/ { print old[$1];next }
        {print}
        END {if(bad)exit 3}
    ' "$CONF" "$savedconf" > "$STAGE/nfqws2.conf"; then
        err 'Текущий конфиг содержит неподдерживаемый формат критических настроек.'
        return 1
    fi
    sh -n "$STAGE/nfqws2.conf" || return 1
}
extract_references() {
    # Expected form uses literal --blob/--hostlist/--ipset/--lua-init=@ paths.
    # Treat only fixed /opt/etc/nfqws2 entries, never execute config.
    grep -Eo '/opt/etc/nfqws2/(lists|blobs|lua)/[A-Za-z0-9._-]+' \
        "$STAGE/nfqws2.conf" | LC_ALL=C sort -u > "$STAGE/references" || :
}
resource_for() {
    ref=$1
    case "$ref" in
        /opt/etc/nfqws2/lists/*)
            SOURCE="$SAVED/lists/${ref##*/}" ;;
        /opt/etc/nfqws2/blobs/*)
            SOURCE="$SAVED/blobs/${ref##*/}" ;;
        /opt/etc/nfqws2/lua/*)
            SOURCE='' ;;
        *) return 1 ;;
    esac
    DEST=$(real_file "$ref") || return 1
    case "$ref" in
        */lists/*) check_plain_dir "$SYSTEM/lists" || return 1 ;;
        */blobs/*) check_plain_dir "$SYSTEM/blobs" || return 1 ;;
        */lua/*) check_plain_dir "$SYSTEM/lua" || return 1 ;;
    esac
    safe_file_path "$ref"
}
check_resources() {
    MISSING=0
    NEED=0
    COLLISIONS=0
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        resource_for "$ref" || return 1
        if [ -L "$DEST" ] || [ -L "$SOURCE" ]; then
            say "ОПАСНО: символьная ссылка $ref"
            COLLISIONS=$((COLLISIONS+1))
        elif [ -f "$DEST" ]; then
            if [ -f "$SOURCE" ] && ! cmp -s "$SOURCE" "$DEST"; then
                say "Конфликт (различное содержимое): $ref"
                COLLISIONS=$((COLLISIONS+1))
            else
                say "Уже присутствует: $ref"
            fi
        elif [ -f "$SOURCE" ]; then
            say "Подготовлен для копирования: $ref"
            NEED=$((NEED+1))
        else
            say "Не найден ни в nfqws2, ни в стратегии: $ref"
            MISSING=$((MISSING+1))
        fi
    done < "$STAGE/references"
    [ "$MISSING" -eq 0 ] && [ "$COLLISIONS" -eq 0 ]
}
acquire_lock() {
    mkdir -p "$BACKUPS" || return 1
    check_plain_dir "$STORE" && check_plain_dir "$BACKUPS" || return 1
    mkdir "$LOCK" 2>/dev/null || {
        err 'Операция уже выполняется или осталась незавершённой. Файлы не изменены.'
        return 1
    }
    LOCKED=1
}
atomic_config() {
    source_file=$1
    config_tmp=$(mktemp "$SYSTEM/.flowseal-conf.XXXXXX") || return 1
    if ! cp "$source_file" "$config_tmp" || ! chmod 600 "$config_tmp" ||
        ! mv -f "$config_tmp" "$CONF"; then
        rm -f "$config_tmp"
        return 1
    fi
}
rollback_files() {
    backup=$1
    if [ -f "$backup/created.tsv" ]; then
        tab=$(printf '\t')
        while IFS="$tab" read -r ref key; do
            [ -n "$ref" ] || continue
            path=$(real_file "$ref") || continue
            if [ ! -L "$path" ] && [ -f "$path" ] &&
                check_plain_file "$backup/resources/$key" &&
                cmp -s "$path" "$backup/resources/$key"; then
                rm -f "$path" || :
            fi
        done < "$backup/created.tsv"
    fi
}
restore_snapshot() {
    backup=$1
    check_plain_file "$backup/nfqws2.conf" || return 1
    was=$(cat "$backup/was-running") || return 1
    case "$was" in yes|no) : ;; *) return 1 ;; esac
    # Keep resource files until the old daemon has been restored.
    atomic_config "$backup/nfqws2.conf" || return 1
    if ! service_restore "$was"; then
        err 'Не удалось восстановить работу службы; резервная копия сохранена.'
        return 1
    fi
    rollback_files "$backup"
    return 0
}
on_exit() {
    if [ "$TRANSACTION" = 1 ] && [ -n "$BACKUP" ]; then
        err 'Сбой установки: восстанавливается прежняя конфигурация.'
        restore_snapshot "$BACKUP" || err "Аварийное восстановление не завершено: $BACKUP"
    fi
    [ -z "$STAGE" ] || rm -rf "$STAGE"
    if [ "$LOCKED" = 1 ]; then
        rmdir "$LOCK" 2>/dev/null || :
    fi
}
trap 'on_exit' 0
trap 'exit 130' 2
trap 'exit 143' 15
begin_stage() {
    mkdir -p "$STORE" || return 1
    check_plain_dir "$STORE" || return 1
    STAGE=$(mktemp -d "$STORE/.stage.XXXXXX") || return 1
}
validate_and_prepare() {
    ensure_paths || { err 'Не найдены безопасные пути к nfqws2, бинарному файлу или службе.';return 1; }
    ensure_saved || { err 'Папка стратегии за пределами хранилища или повреждена.';return 1; }
    begin_stage || return 1
    prepare_candidate || return 1
    extract_references
    check_resources
}
do_check() {
    validate_and_prepare || return 1
    say "Проверка совместимости: $SAVED"
    say "Текущий интерфейс/политика/очередь сохраняются из $CONF"
    say "Необходимых копий: $NEED; отсутствует: $MISSING; конфликтов: $COLLISIONS"
    say 'Проверка статическая, реальный запуск будет проверен после применения.'
}
do_preview() {
    validate_and_prepare || return 1
    say '--- Изменения конфигурации (только просмотр) ---'
    diff -u "$CONF" "$STAGE/nfqws2.conf" || :
    say "Новые файлы: $NEED. При применении рабочая конфигурация будет скопирована в $BACKUPS."
}
copy_new_files() {
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        resource_for "$ref" || return 1
        [ -f "$DEST" ] && continue
        check_plain_file "$SOURCE" || return 1
        key=$(printf '%s' "$ref" | tr '/' '_')
        cp "$SOURCE" "$BACKUP/resources/$key" || return 1
        # Write undo journal BEFORE moving the file into place.
        printf '%s\t%s\n' "$ref" "$key" >> "$BACKUP/created.tsv" || return 1
        new_tmp=$(mktemp "$(dirname "$DEST")/.flowseal-bin.XXXXXX") || return 1
        if ! cp "$SOURCE" "$new_tmp" || ! chmod 600 "$new_tmp" ||
            ! mv "$new_tmp" "$DEST"; then
            rm -f "$new_tmp"
            return 1
        fi
    done < "$STAGE/references"
}
do_apply() {
    validate_and_prepare || return 1
    acquire_lock || return 1
    BACKUP="$BACKUPS/$(date -u '+%Y%m%d-%H%M%S')-$$"
    mkdir "$BACKUP" && mkdir "$BACKUP/resources" || return 1
    cp -p "$CONF" "$BACKUP/nfqws2.conf" || return 1
    : > "$BACKUP/created.tsv"
    if service_running; then was=yes;else was=no;fi
    printf '%s\n' "$was" > "$BACKUP/was-running" || return 1
    if check_plain_file "$ACTIVE"; then
        cp "$ACTIVE" "$BACKUP/previous-active" || return 1
    fi
    printf '%s\n' "$SAVED" > "$BACKUP/target" || return 1
    TRANSACTION=1
    say "Резервная копия: $BACKUP"
    if ! copy_new_files || ! atomic_config "$STAGE/nfqws2.conf"; then
        err 'Не удалось записать подготовленные файлы.'
        return 1
    fi
    if [ "$was" = yes ]; then action=restart;else action=start;fi
    if ! "$SERVICE" "$action" || ! service_running; then
        err 'nfqws2 не подтвердил успешный запуск.'
        return 1
    fi
    strategy_id=${SAVED##*/}
    sha=$(sha256sum "$CONF" | awk '{print $1}') || return 1
    printf '%s\t%s\n' "$strategy_id" "$sha" > "$STORE/.active.$$" || return 1
    mv "$STORE/.active.$$" "$ACTIVE" || return 1
    printf '%s\n' "${BACKUP##*/}" > "$STORE/.latest.$$" || return 1
    mv "$STORE/.latest.$$" "$LATEST" || return 1
    : > "$BACKUP/committed"
    TRANSACTION=0
    say "Стратегия $strategy_id установлена. Служба nfqws2 работает."
    say "Для отката: пункт 'Резервные копии и откат'."
}
do_undo() {
    ensure_paths || return 1
    check_plain_dir "$BACKUPS" || return 1
    check_plain_file "$LATEST" || { err 'Нет резервной копии последнего применения.';return 1; }
    backup_id=$(cat "$LATEST") || return 1
    case "$backup_id" in ''|*[!0-9-]*)return 1;;esac
    backup="$BACKUPS/$backup_id"
    check_plain_dir "$backup" && check_plain_file "$backup/committed" || return 1
    # Protect manual changes performed outside KeenUtils after activation.
    if check_plain_file "$ACTIVE"; then
        saved_sha=$(awk -F '\t' '{print $2}' "$ACTIVE")
        actual_sha=$(sha256sum "$CONF" | awk '{print $1}')
        if [ "$saved_sha" != "$actual_sha" ]; then
            err 'Конфигурация изменена извне. Автоматический откат отменён.'
            return 1
        fi
    fi
    acquire_lock || return 1
    say "Восстановление из $backup"
    restore_snapshot "$backup" || return 1
    if check_plain_file "$backup/previous-active"; then
        cp "$backup/previous-active" "$STORE/.active.$$" &&
            mv "$STORE/.active.$$" "$ACTIVE" || return 1
    else
        rm -f "$ACTIVE"
    fi
    rm -f "$LATEST"
    : > "$backup/restored"
    say 'Предыдущий конфиг и состояние службы восстановлены.'
}
do_status() {
    if service_running; then
        say 'Служба nfqws2: работает'
    else
        say 'Служба nfqws2: остановлена'
    fi
    if check_plain_file "$ACTIVE"; then
        id=$(awk -F '\t' '{print $1}' "$ACTIVE")
        known=$(awk -F '\t' '{print $2}' "$ACTIVE")
        current=$(sha256sum "$CONF" 2>/dev/null | awk '{print $1}')
        if [ "$known" = "$current" ]; then
            say "Активная стратегия KeenUtils: $id"
        else
            say "Последняя применённая: $id (конфигурация изменена извне!)"
        fi
    else
        say 'Активная стратегия KeenUtils: не зарегистрирована'
    fi
}
do_history() {
    say 'Сохранённые резервные копии:'
    if ! check_plain_dir "$BACKUPS"; then say '  Пока нет.';return 0;fi
    total=0
    for b in "$BACKUPS"/*; do
        check_plain_dir "$b" || continue
        check_plain_file "$b/nfqws2.conf" || continue
        total=$((total+1))
        target=$(cat "$b/target" 2>/dev/null) || target='?'
        if [ -f "$b/restored" ]; then state='восстановлена'
        elif [ -f "$b/committed" ]; then state='сохранена'
        else state='незавершена';fi
        printf ' %s | %s | %s\n' "${b##*/}" "$state" "$target"
    done
    [ "$total" -gt 0 ] || say '  Пока нет.'
}
case "$VERB" in
    check) do_check ;;
    preview) do_preview ;;
    apply) do_apply ;;
    undo) do_undo ;;
    status) do_status ;;
    history) do_history ;;
    *) err 'Используйте: deployer.sh {check|preview|apply|undo|status|history} [папка стратегии]'
       exit 2 ;;
esac
