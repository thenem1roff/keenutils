#!/bin/sh
# Independent Flowseal -> nfqws2 manager; POSIX sh, BusyBox awk and jq, no Python.
# Development stage: saved drafts ONLY. Cannot deploy or touch running nfqws2.
set -u
umask 077
export PATH=/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUNTIME=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
HOME_DIR=${KEENUTILS_FLOWSEAL_HOME:-/opt/etc/keenutils/flowseal}
STRATEGIES="$HOME_DIR/strategies"
HISTORY="$HOME_DIR/history"
TEMP="$HOME_DIR/tmp"
CLEAN_TEMP=''
RELEASE_URL='https://api.github.com/repos/Flowseal/zapret-discord-youtube/releases/latest'
Nfqws2_CONF='/opt/etc/nfqws2/nfqws2.conf'

cleanup() {
    if [ -n "$CLEAN_TEMP" ]; then rm -rf "$CLEAN_TEMP"; CLEAN_TEMP=''; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

message() { printf '%s\n' "$*"; }
error() { printf 'Ошибка: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
pause_menu() { :; }
ask_yes() {
    while :; do
        printf '%s [Y/n]: ' "$1"
        IFS= read -r input || return 1
        case "$input" in ''|y|Y|yes|YES) return 0 ;; n|N|no|NO) return 1 ;; esac
        message 'Введите Y или n.'
    done
}
fetch() {
    fetch_url=$1; fetch_dest=$2
    if have wget && wget -q -O "$fetch_dest" "$fetch_url" && [ -s "$fetch_dest" ]; then
        return 0
    fi
    if have curl && curl -fLSs --connect-timeout 10 --max-time 75 -o "$fetch_dest" "$fetch_url" &&
        [ -s "$fetch_dest" ]; then return 0; fi
    return 1
}
need_tool() {
    tool=$1; package=$2
    have "$tool" && return 0
    message "Для конвертации требуется $tool (пакет Entware: $package)."
    ask_yes "Установить $package?" || return 1
    have opkg || { error 'Не найден opkg'; return 1; }
    opkg update && opkg install "$package" && have "$tool"
}
dependencies() {
    need_tool awk gawk || return 1
    need_tool jq jq || return 1
    need_tool od coreutils-od || return 1
    need_tool tr coreutils || return 1
    need_tool sha256sum coreutils-sha256sum || return 1
    (have wget || have curl) || need_tool curl curl || return 1
}
read_release() {
    release_json=$1
    fetch "$RELEASE_URL" "$release_json" || {
        error 'Не удалось получить последний выпуск Flowseal.'
        return 1
    }
    FLOW_VERSION=$(jq -er '.tag_name | strings' "$release_json") || return 1
    printf '%s\n' "$FLOW_VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){1,3}$' || {
        error 'Неизвестный формат версии Flowseal.';return 1
    }
    FLOW_URL="https://github.com/Flowseal/zapret-discord-youtube/releases/tag/$FLOW_VERSION"
    FLOW_TREE_URL="https://api.github.com/repos/Flowseal/zapret-discord-youtube/git/trees/$FLOW_VERSION?recursive=1"
    FLOW_RAW="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/$FLOW_VERSION"
}
read_tree() {
    rt_dest=$1
    fetch "$FLOW_TREE_URL" "$rt_dest" || {
        error "Не удалось получить дерево файлов Flowseal $FLOW_VERSION.";return 1
    }
    jq -e '.truncated == false and (.tree | type == "array")' "$rt_dest" >/dev/null || {
        error 'GitHub вернул неполное дерево выпуска Flowseal.';return 1
    }
    FLOW_TREE_SHA=$(jq -er '.sha | strings' "$rt_dest") || return 1
    printf '%s\n' "$FLOW_TREE_SHA" | grep -Eq '^[a-f0-9]{40}$' || {
        error 'Некорректная контрольная метка дерева выпуска.';return 1
    }
}
list_profiles() {
    lp_tree=$1; lp_list=$2
    # Entware jq can be compiled WITHOUT ONIGURUMA (no test/match/sub).
    # Let jq only read blob paths; validate filenames with BusyBox grep.
    # Keep the jq step separate so its failures cannot be hidden by sort.
    lp_all="$lp_list.all.$"
    if ! jq -r '.tree[] | select(.type == "blob") | .path' "$lp_tree" > "$lp_all"; then
        rm -f "$lp_all"
        error 'Не удалось прочитать список файлов выпуска Flowseal.'
        return 1
    fi
    LC_ALL=C grep -E '^general[ A-Za-z0-9()_-]*[.]bat
encode_filename() {
    printf '%s' "$1" | sed 's/ /%20/g; s/(/%28/g; s/)/%29/g'
}
get_profile() {
    gp_name=$1; gp_dest=$2
    printf '%s\n' "$gp_name" |
        grep -Eq '^general[ A-Za-z0-9()_-]*[.]bat$' || return 1
    gp_encoded=$(encode_filename "$gp_name")
    fetch "$FLOW_RAW/$gp_encoded" "$gp_dest" || {
        error "Не удалось скачать профиль $gp_name.";return 1
    }
    [ "$(wc -c < "$gp_dest")" -le 1048576 ] || {
        error 'Слишком большой BAT-профиль.';return 1
    }
}
tree_has_file() {
    th_tree=$1; th_path=$2
    jq -e --arg path "$th_path" 'any(.tree[]; .type == "blob" and .path == $path)' "$th_tree" >/dev/null
}
fetch_resource() {
    fr_tree=$1;fr_source=$2;fr_kind=$3;fr_name=$4;fr_output=$5
    case "$fr_kind" in lists|bin) : ;; *)return 1;;esac
    printf '%s\n' "$fr_name" | grep -Eq '^[A-Za-z0-9._-]+$' || return 1
    case "$fr_name" in .|..|*..*)return 1;;esac
    fr_path="$fr_kind/$fr_name"
    if ! tree_has_file "$fr_tree" "$fr_path"; then
        printf 'warning\tmissing-upstream-resource\t0\tНет файла в выпуске Flowseal: %s\n' \
            "$fr_path" >> "$fr_output/diagnostics.tsv"
        return 0
    fi
    mkdir -p "$fr_source/$fr_kind" || return 1
    if ! fetch "$FLOW_RAW/$fr_path" "$fr_source/$fr_kind/$fr_name"; then
        error "Не удалось скачать $fr_path из Flowseal $FLOW_VERSION.";return 1
    fi
    [ "$(wc -c < "$fr_source/$fr_kind/$fr_name")" -le 8388608 ] || {
        error "Слишком большой файл $fr_path.";return 1
    }
}
download_resources() {
    dr_tree=$1;dr_source=$2;dr_output=$3
    if [ -s "$dr_output/lists.manifest" ]; then
        while IFS="$(printf '\t')" read -r dr_name dr_destination; do
            [ -n "$dr_name" ] || continue
            fetch_resource "$dr_tree" "$dr_source" lists "$dr_name" "$dr_output" || return 1
        done < "$dr_output/lists.manifest"
    fi
    if [ -s "$dr_output/blobs.manifest" ]; then
        while IFS="$(printf '\t')" read -r dr_name dr_destination dr_blob; do
            [ -n "$dr_name" ] || continue
            fetch_resource "$dr_tree" "$dr_source" bin "$dr_name" "$dr_output" || return 1
        done < "$dr_output/blobs.manifest"
    fi
}
identity() {
    ident=$(printf '%s' "$1" | sed 's/\.bat$//;s/^general (//;s/)$//;s/^general$/GENERAL/' |
        tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g;s/--*/-/g;s/^-//;s/-$//')
    [ -n "$ident" ] || return 1
    STRATEGY_ID="flowseal-$FLOW_VERSION-$ident"
}
friendly() {
    printf '%s\n' "$1" | sed 's/\.bat$//;s/^general (//;s/)$//;s/^general$/GENERAL/'
}
pick_profile() {
    options=$1;index=0
    message ""
    message "Flowseal $FLOW_VERSION — доступные стратегии:"
    while IFS= read -r base; do
        index=$((index+1))
        printf '%2s. %s\n' "$index" "$(friendly "$base")"
    done < "$options"
    message ' 0. Назад'
    while :; do
        printf 'Выберите стратегию: '
        IFS= read -r number || return 1
        case "$number" in ''|0|00)return 1;;esac
        case "$number" in *[!0-9]*)message 'Неверный номер.';continue;;esac
        SELECTED=$(sed -n "${number}p" "$options")
        [ -n "$SELECTED" ] && return 0
        message 'Неверный номер.'
    done
}
wan_interface() {
    WAN=eth3
    if [ -r "$Nfqws2_CONF" ]; then
        current=$(sed -n 's/^ISP_INTERFACE=["'\'']\([^"'\'' ]*\)["'\''].*$/\1/p' "$Nfqws2_CONF" | head -n 1)
        case "$current" in
            ''|*[!A-Za-z0-9._-]*) : ;;
            *) WAN=$current ;;
        esac
    fi
}
copy_resources() {
    source=$1; output=$2
    test -f "$output/lists.manifest" && {
        while IFS="$(printf '\t')" read -r src dest; do
            case "$src:$dest" in
                *[!A-Za-z0-9._:-]*|*..*)error 'Недопустимый путь списка.';return 1;;
            esac
            if [ -f "$source/lists/$src" ]; then
                mkdir -p "$output/lists"
                cp "$source/lists/$src" "$output/lists/$dest" || return 1
            else
                printf 'warning\tmissing-list\t0\tНет отдельного списка %s\n' "$src" >> "$output/diagnostics.tsv"
            fi
        done < "$output/lists.manifest"
    }
    test -f "$output/blobs.manifest" && {
        while IFS="$(printf '\t')" read -r src dest blob_id; do
            case "$src:$dest:$blob_id" in
                *[!A-Za-z0-9._:-]*|*..*)error 'Недопустимый BIN-путь.';return 1;;
            esac
            if [ -f "$source/bin/$src" ]; then
                mkdir -p "$output/blobs"
                cp "$source/bin/$src" "$output/blobs/$dest" || return 1
            else
                printf 'warning\tmissing-blob\t0\tНет бинарного шаблона %s\n' "$src" >> "$output/diagnostics.tsv"
            fi
        done < "$output/blobs.manifest"
    }
    return 0
}
convert_profile() {
    source=$1; profile=$2; output=$3; games=$4
    mkdir -p "$output" || return 1
    wan_interface
    hex=$(od -An -tx1 -v "$RUNTIME/hostfakesplit_alt1.lua" | tr -d ' \n') || return 1
    [ -n "$hex" ] || { error 'Отсутствует код Lua-совместимости.';return 1; }
    FLOWSEAL_OUTPUT="$output" FLOWSEAL_GAMES="$games" FLOWSEAL_INTERFACE="$WAN" \
        FLOWSEAL_ALT_LUA_HEX="$hex" FLOWSEAL_STRATEGY_ID="${STRATEGY_ID:-flowseal}" \
        awk -f "$RUNTIME/converter.awk" "$source/$profile" || return 1
    [ -s "$output/nfqws2.conf" ] && sh -n "$output/nfqws2.conf" || {
        error 'Полученная конфигурация имеет ошибку синтаксиса shell.'
        return 1
    }
    return 0
}
save_report() {
    output=$1
    read_count=$(sed -n 's/^PROFILES_READ=//p' "$output/stats.txt")
    write_count=$(sed -n 's/^PROFILES_WRITTEN=//p' "$output/stats.txt")
    warns=0
    if [ -f "$output/diagnostics.tsv" ]; then
        warns=$(awk -F '\t' '$1=="warning"{n++}END{print n+0}' "$output/diagnostics.tsv")
    fi
    {
        printf '# Отчёт конвертации Flowseal\n\n'
        printf 'Профиль: %s\n' "$LABEL"
        printf 'Выпуск Flowseal: %s\n' "$FLOW_VERSION"
        printf 'Прочитано профилей: %s\n' "$read_count"
        printf 'Записано профилей: %s\n' "$write_count"
        printf 'Игровые порты: %s\n' "$GAMES"
        printf 'Предупреждения: %s\n\n' "$warns"
        printf 'Конфигурация СОХРАНЕНА, но НЕ ПРИМЕНЕНА к роутеру.\n'
        printf 'Сопоставление штатных списков и проверка nfqws2 перед установкой обязательны.\n'
        if [ -f "$output/diagnostics.tsv" ]; then
            printf '\nДиагностика:\n'
            awk -F '\t' '{printf "- [%s/%s] %s\n",$1,$2,$4}' "$output/diagnostics.tsv"
        fi
    } > "$output/REPORT.md"
    jq -n --arg source Flowseal --arg name "$LABEL" \
        --arg version "$FLOW_VERSION" --arg profile "$SELECTED" \
        --arg game_ports "$GAMES" --arg release_url "$FLOW_URL" \
        --arg release_tree_sha "$FLOW_TREE_SHA" --arg profile_sha256 "$PROFILE_SHA" \
        --arg converted_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --argjson profiles_read "$read_count" --argjson profiles_written "$write_count" \
        --argjson warnings "$warns" \
        '{source:$source,name:$name,version:$version,profile:$profile,
        game_ports:($game_ports=="yes"),release_url:$release_url,
        release_tree_sha:$release_tree_sha,profile_sha256:$profile_sha256,
        converted_at:$converted_at,profiles_read:$profiles_read,
        profiles_written:$profiles_written,warnings:$warnings,state:"saved_only"}' \
        > "$output/info.json" || return 1
    return 0
}
add_strategy() {
    dependencies || return 1
    mkdir -p "$TEMP" "$STRATEGIES" "$HISTORY" || return 1
    CLEAN_TEMP=$(mktemp -d "$TEMP/.import.XXXXXX") || return 1
    read_release "$CLEAN_TEMP/release.json" || { cleanup;return 1; }
    message "Получение стратегий Flowseal $FLOW_VERSION..."
    read_tree "$CLEAN_TEMP/tree.json" || { cleanup;return 1; }
    list_profiles "$CLEAN_TEMP/tree.json" "$CLEAN_TEMP/profiles.txt" || {
        cleanup;return 1
    }
    pick_profile "$CLEAN_TEMP/profiles.txt" || { cleanup;return 0; }
    LABEL=$(friendly "$SELECTED")
    ask_yes "Конвертировать $LABEL (Flowseal $FLOW_VERSION)?" || { cleanup;return 0; }
    GAMES=no
    if ask_yes 'Добавить игровые TCP/UDP-порты?'; then GAMES=yes; fi
    identity "$SELECTED" || { error 'Не удалось сформировать имя стратегии.';cleanup;return 1; }
    destination="$STRATEGIES/$STRATEGY_ID"
    if [ -L "$destination" ]; then
        error 'Путь стратегии является символической ссылкой.';cleanup;return 1
    fi
    if [ -e "$destination" ] && ! ask_yes 'Такая стратегия уже есть. Пересоздать?'; then
        cleanup;return 0
    fi
    if [ -e "$destination" ] && [ -f "$destination/nfqws2.conf" ] &&
        [ -r "$Nfqws2_CONF" ] &&
        cmp -s "$destination/nfqws2.conf" "$Nfqws2_CONF"; then
        error 'Конфигурация совпадает с рабочей; пересоздание запрещено.'
        cleanup;return 1
    fi
    mkdir -p "$CLEAN_TEMP/source"
    message "Загрузка выбранного профиля $LABEL (без архива)..."
    get_profile "$SELECTED" "$CLEAN_TEMP/source/$SELECTED" || {
        cleanup;return 1
    }
    PROFILE_SHA=$(sha256sum "$CLEAN_TEMP/source/$SELECTED" | awk '{print $1}')
    output="$CLEAN_TEMP/converted"
    message 'Конвертация...'
    if ! convert_profile "$CLEAN_TEMP/source" "$SELECTED" "$output" "$GAMES" ||
        ! download_resources "$CLEAN_TEMP/tree.json" "$CLEAN_TEMP/source" "$output" ||
        ! copy_resources "$CLEAN_TEMP/source" "$output" ||
        ! save_report "$output"; then
        error 'Конвертация не завершена. Рабочая конфигурация не изменена.'
        cleanup;return 1
    fi
    if [ -e "$destination" ]; then
        old="$HISTORY/$STRATEGY_ID-$(date -u +%Y%m%d-%H%M%S)-$$"
        mv "$destination" "$old" || { cleanup;return 1; }
        if ! mv "$output" "$destination"; then
            mv "$old" "$destination" || error 'Не удалось восстановить сохранённую стратегию!'
            cleanup;return 1
        fi
    else
        mv "$output" "$destination" || { cleanup;return 1; }
    fi
    message ""
    message "Сохранено: $LABEL — Flowseal $FLOW_VERSION"
    message "Каталог: $destination"
    message "Игровые порты: $GAMES"
    message 'Конвертация не применена к роутеру.'
    cat "$destination/REPORT.md"
    cleanup
}

show_strategy() {
    selected_dir=$1
    while :; do
        if [ ! -f "$selected_dir/info.json" ] || [ -L "$selected_dir" ]; then
            error 'Стратегия отсутствует.';return
        fi
        label=$(jq -r '.name + " — Flowseal " + .version' "$selected_dir/info.json")
        message ""
        message "$label"
        if [ -f "$selected_dir/nfqws2.conf" ] && [ -r "$Nfqws2_CONF" ] &&
            cmp -s "$selected_dir/nfqws2.conf" "$Nfqws2_CONF"; then
            message 'Статус: совпадает с рабочим конфигом'
            active=yes
        else active=no;message 'Статус: сохранена';fi
        message ' 1. Информация и предупреждения'
        message ' 2. Просмотреть nfqws2.conf'
        message ' 3. Проверить синтаксис и ресурсы (без применения)'
        message ' 4. Удалить стратегию'
        message ' 0. Назад'
        printf 'Выбор: '
        IFS= read -r choice || return
        case "$choice" in
            ''|0|00)return;;
            1) cat "$selected_dir/REPORT.md" ;;
            2) cat "$selected_dir/nfqws2.conf" ;;
            3) sh "$RUNTIME/validator.sh" "$selected_dir" || : ;;
            4)
                if [ "$active" = yes ]; then
                    error 'Удаление действующей конфигурации запрещено.'
                    continue
                fi
                if ask_yes "Удалить $label и прежние редакции?"; then
                    id=$(basename "$selected_dir")
                    rm -rf "$selected_dir" || return 1
                    for older in "$HISTORY/$id"-*; do
                        [ -d "$older" ] && [ ! -L "$older" ] && rm -rf "$older"
                    done
                    message 'Стратегия удалена.'
                    return
                fi ;;
            *) message 'Неизвестный пункт.' ;;
        esac
    done
}
saved_menu() {
    while :; do
        mkdir -p "$STRATEGIES" || return
        list="$HOME_DIR/.saved-index.$$"
        : > "$list"
        count=0
        message ""
        message 'Мои стратегии:'
        for item in "$STRATEGIES"/*; do
            [ -d "$item" ] && [ ! -L "$item" ] && [ -f "$item/info.json" ] || continue
            count=$((count+1))
            title=$(jq -r '.name + " — Flowseal " + .version' "$item/info.json" 2>/dev/null) || continue
            printf '%2s. %s\n' "$count" "$title"
            printf '%s\t%s\n' "$count" "$item" >> "$list"
        done
        [ "$count" -gt 0 ] || message '  Пока нет сохранённых стратегий.'
        message ' 0. Назад'
        printf 'Выберите стратегию: '
        IFS= read -r choice || { rm -f "$list";return; }
        case "$choice" in ''|0|00)rm -f "$list";return;;esac
        case "$choice" in *[!0-9]*)message 'Неверный номер.';rm -f "$list";continue;;esac
        target=$(awk -F '\t' -v id="$choice" '$1==id {print $2;exit}' "$list")
        rm -f "$list"
        [ -n "$target" ] && show_strategy "$target" || message 'Неверный номер.'
    done
}
main() {
    [ -d "$HOME_DIR" ] && [ ! -L "$HOME_DIR" ] || {
        error 'Некорректный каталог данных конвертера.';return 1;
    }
    mkdir -p "$STRATEGIES" "$TEMP" || return 1
    [ ! -L "$STRATEGIES" ] && [ ! -L "$TEMP" ] || {
        error 'Символические ссылки в каталогах конвертера запрещены.';return 1;
    }
    while :; do
        message ''
        message '======== KeenUtils | Flowseal → nfqws2 ========'
        message ' 1. Добавить стратегию'
        message ' 2. Мои стратегии'
        message ' 0. Назад в KeenUtils'
        message ' Разработка: сохранение без применения к роутеру.'
        printf 'Выберите пункт: '
        IFS= read -r choice || return 0
        case "$choice" in
            ''|0|00) return 0 ;;
            1) add_strategy || : ;;
            2) dependencies && saved_menu || : ;;
            *)message 'Неизвестный пункт.' ;;
        esac
    done
}
# Test harness sources functions without launching the interactive menu.
if [ "${KEENUTILS_FLOWSEAL_TEST_ONLY:-0}" != 1 ]; then
    main
fi
 "$lp_all" |
        LC_ALL=C sort -u > "$lp_list"
    rm -f "$lp_all"
    [ -s "$lp_list" ] || {
        error 'Стратегии general*.bat не найдены в выпуске.'
        return 1
    }
}
encode_filename() {
    printf '%s' "$1" | sed 's/ /%20/g; s/(/%28/g; s/)/%29/g'
}
get_profile() {
    gp_name=$1; gp_dest=$2
    printf '%s\n' "$gp_name" |
        grep -Eq '^general[ A-Za-z0-9()_-]*[.]bat$' || return 1
    gp_encoded=$(encode_filename "$gp_name")
    fetch "$FLOW_RAW/$gp_encoded" "$gp_dest" || {
        error "Не удалось скачать профиль $gp_name.";return 1
    }
    [ "$(wc -c < "$gp_dest")" -le 1048576 ] || {
        error 'Слишком большой BAT-профиль.';return 1
    }
}
tree_has_file() {
    th_tree=$1; th_path=$2
    jq -e --arg path "$th_path" 'any(.tree[]; .type == "blob" and .path == $path)' "$th_tree" >/dev/null
}
fetch_resource() {
    fr_tree=$1;fr_source=$2;fr_kind=$3;fr_name=$4;fr_output=$5
    case "$fr_kind" in lists|bin) : ;; *)return 1;;esac
    printf '%s\n' "$fr_name" | grep -Eq '^[A-Za-z0-9._-]+$' || return 1
    case "$fr_name" in .|..|*..*)return 1;;esac
    fr_path="$fr_kind/$fr_name"
    if ! tree_has_file "$fr_tree" "$fr_path"; then
        printf 'warning\tmissing-upstream-resource\t0\tНет файла в выпуске Flowseal: %s\n' \
            "$fr_path" >> "$fr_output/diagnostics.tsv"
        return 0
    fi
    mkdir -p "$fr_source/$fr_kind" || return 1
    if ! fetch "$FLOW_RAW/$fr_path" "$fr_source/$fr_kind/$fr_name"; then
        error "Не удалось скачать $fr_path из Flowseal $FLOW_VERSION.";return 1
    fi
    [ "$(wc -c < "$fr_source/$fr_kind/$fr_name")" -le 8388608 ] || {
        error "Слишком большой файл $fr_path.";return 1
    }
}
download_resources() {
    dr_tree=$1;dr_source=$2;dr_output=$3
    if [ -s "$dr_output/lists.manifest" ]; then
        while IFS="$(printf '\t')" read -r dr_name dr_destination; do
            [ -n "$dr_name" ] || continue
            fetch_resource "$dr_tree" "$dr_source" lists "$dr_name" "$dr_output" || return 1
        done < "$dr_output/lists.manifest"
    fi
    if [ -s "$dr_output/blobs.manifest" ]; then
        while IFS="$(printf '\t')" read -r dr_name dr_destination dr_blob; do
            [ -n "$dr_name" ] || continue
            fetch_resource "$dr_tree" "$dr_source" bin "$dr_name" "$dr_output" || return 1
        done < "$dr_output/blobs.manifest"
    fi
}
identity() {
    ident=$(printf '%s' "$1" | sed 's/\.bat$//;s/^general (//;s/)$//;s/^general$/GENERAL/' |
        tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g;s/--*/-/g;s/^-//;s/-$//')
    [ -n "$ident" ] || return 1
    STRATEGY_ID="flowseal-$FLOW_VERSION-$ident"
}
friendly() {
    printf '%s\n' "$1" | sed 's/\.bat$//;s/^general (//;s/)$//;s/^general$/GENERAL/'
}
pick_profile() {
    options=$1;index=0
    message ""
    message "Flowseal $FLOW_VERSION — доступные стратегии:"
    while IFS= read -r base; do
        index=$((index+1))
        printf '%2s. %s\n' "$index" "$(friendly "$base")"
    done < "$options"
    message ' 0. Назад'
    while :; do
        printf 'Выберите стратегию: '
        IFS= read -r number || return 1
        case "$number" in ''|0|00)return 1;;esac
        case "$number" in *[!0-9]*)message 'Неверный номер.';continue;;esac
        SELECTED=$(sed -n "${number}p" "$options")
        [ -n "$SELECTED" ] && return 0
        message 'Неверный номер.'
    done
}
wan_interface() {
    WAN=eth3
    if [ -r "$Nfqws2_CONF" ]; then
        current=$(sed -n 's/^ISP_INTERFACE=["'\'']\([^"'\'' ]*\)["'\''].*$/\1/p' "$Nfqws2_CONF" | head -n 1)
        case "$current" in
            ''|*[!A-Za-z0-9._-]*) : ;;
            *) WAN=$current ;;
        esac
    fi
}
copy_resources() {
    source=$1; output=$2
    test -f "$output/lists.manifest" && {
        while IFS="$(printf '\t')" read -r src dest; do
            case "$src:$dest" in
                *[!A-Za-z0-9._:-]*|*..*)error 'Недопустимый путь списка.';return 1;;
            esac
            if [ -f "$source/lists/$src" ]; then
                mkdir -p "$output/lists"
                cp "$source/lists/$src" "$output/lists/$dest" || return 1
            else
                printf 'warning\tmissing-list\t0\tНет отдельного списка %s\n' "$src" >> "$output/diagnostics.tsv"
            fi
        done < "$output/lists.manifest"
    }
    test -f "$output/blobs.manifest" && {
        while IFS="$(printf '\t')" read -r src dest blob_id; do
            case "$src:$dest:$blob_id" in
                *[!A-Za-z0-9._:-]*|*..*)error 'Недопустимый BIN-путь.';return 1;;
            esac
            if [ -f "$source/bin/$src" ]; then
                mkdir -p "$output/blobs"
                cp "$source/bin/$src" "$output/blobs/$dest" || return 1
            else
                printf 'warning\tmissing-blob\t0\tНет бинарного шаблона %s\n' "$src" >> "$output/diagnostics.tsv"
            fi
        done < "$output/blobs.manifest"
    }
    return 0
}
convert_profile() {
    source=$1; profile=$2; output=$3; games=$4
    mkdir -p "$output" || return 1
    wan_interface
    hex=$(od -An -tx1 -v "$RUNTIME/hostfakesplit_alt1.lua" | tr -d ' \n') || return 1
    [ -n "$hex" ] || { error 'Отсутствует код Lua-совместимости.';return 1; }
    FLOWSEAL_OUTPUT="$output" FLOWSEAL_GAMES="$games" FLOWSEAL_INTERFACE="$WAN" \
        FLOWSEAL_ALT_LUA_HEX="$hex" FLOWSEAL_STRATEGY_ID="${STRATEGY_ID:-flowseal}" \
        awk -f "$RUNTIME/converter.awk" "$source/$profile" || return 1
    [ -s "$output/nfqws2.conf" ] && sh -n "$output/nfqws2.conf" || {
        error 'Полученная конфигурация имеет ошибку синтаксиса shell.'
        return 1
    }
    return 0
}
save_report() {
    output=$1
    read_count=$(sed -n 's/^PROFILES_READ=//p' "$output/stats.txt")
    write_count=$(sed -n 's/^PROFILES_WRITTEN=//p' "$output/stats.txt")
    warns=0
    if [ -f "$output/diagnostics.tsv" ]; then
        warns=$(awk -F '\t' '$1=="warning"{n++}END{print n+0}' "$output/diagnostics.tsv")
    fi
    {
        printf '# Отчёт конвертации Flowseal\n\n'
        printf 'Профиль: %s\n' "$LABEL"
        printf 'Выпуск Flowseal: %s\n' "$FLOW_VERSION"
        printf 'Прочитано профилей: %s\n' "$read_count"
        printf 'Записано профилей: %s\n' "$write_count"
        printf 'Игровые порты: %s\n' "$GAMES"
        printf 'Предупреждения: %s\n\n' "$warns"
        printf 'Конфигурация СОХРАНЕНА, но НЕ ПРИМЕНЕНА к роутеру.\n'
        printf 'Сопоставление штатных списков и проверка nfqws2 перед установкой обязательны.\n'
        if [ -f "$output/diagnostics.tsv" ]; then
            printf '\nДиагностика:\n'
            awk -F '\t' '{printf "- [%s/%s] %s\n",$1,$2,$4}' "$output/diagnostics.tsv"
        fi
    } > "$output/REPORT.md"
    jq -n --arg source Flowseal --arg name "$LABEL" \
        --arg version "$FLOW_VERSION" --arg profile "$SELECTED" \
        --arg game_ports "$GAMES" --arg release_url "$FLOW_URL" \
        --arg release_tree_sha "$FLOW_TREE_SHA" --arg profile_sha256 "$PROFILE_SHA" \
        --arg converted_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --argjson profiles_read "$read_count" --argjson profiles_written "$write_count" \
        --argjson warnings "$warns" \
        '{source:$source,name:$name,version:$version,profile:$profile,
        game_ports:($game_ports=="yes"),release_url:$release_url,
        release_tree_sha:$release_tree_sha,profile_sha256:$profile_sha256,
        converted_at:$converted_at,profiles_read:$profiles_read,
        profiles_written:$profiles_written,warnings:$warnings,state:"saved_only"}' \
        > "$output/info.json" || return 1
    return 0
}
add_strategy() {
    dependencies || return 1
    mkdir -p "$TEMP" "$STRATEGIES" "$HISTORY" || return 1
    CLEAN_TEMP=$(mktemp -d "$TEMP/.import.XXXXXX") || return 1
    read_release "$CLEAN_TEMP/release.json" || { cleanup;return 1; }
    message "Получение стратегий Flowseal $FLOW_VERSION..."
    read_tree "$CLEAN_TEMP/tree.json" || { cleanup;return 1; }
    list_profiles "$CLEAN_TEMP/tree.json" "$CLEAN_TEMP/profiles.txt" || {
        cleanup;return 1
    }
    pick_profile "$CLEAN_TEMP/profiles.txt" || { cleanup;return 0; }
    LABEL=$(friendly "$SELECTED")
    ask_yes "Конвертировать $LABEL (Flowseal $FLOW_VERSION)?" || { cleanup;return 0; }
    GAMES=no
    if ask_yes 'Добавить игровые TCP/UDP-порты?'; then GAMES=yes; fi
    identity "$SELECTED" || { error 'Не удалось сформировать имя стратегии.';cleanup;return 1; }
    destination="$STRATEGIES/$STRATEGY_ID"
    if [ -L "$destination" ]; then
        error 'Путь стратегии является символической ссылкой.';cleanup;return 1
    fi
    if [ -e "$destination" ] && ! ask_yes 'Такая стратегия уже есть. Пересоздать?'; then
        cleanup;return 0
    fi
    if [ -e "$destination" ] && [ -f "$destination/nfqws2.conf" ] &&
        [ -r "$Nfqws2_CONF" ] &&
        cmp -s "$destination/nfqws2.conf" "$Nfqws2_CONF"; then
        error 'Конфигурация совпадает с рабочей; пересоздание запрещено.'
        cleanup;return 1
    fi
    mkdir -p "$CLEAN_TEMP/source"
    message "Загрузка выбранного профиля $LABEL (без архива)..."
    get_profile "$SELECTED" "$CLEAN_TEMP/source/$SELECTED" || {
        cleanup;return 1
    }
    PROFILE_SHA=$(sha256sum "$CLEAN_TEMP/source/$SELECTED" | awk '{print $1}')
    output="$CLEAN_TEMP/converted"
    message 'Конвертация...'
    if ! convert_profile "$CLEAN_TEMP/source" "$SELECTED" "$output" "$GAMES" ||
        ! download_resources "$CLEAN_TEMP/tree.json" "$CLEAN_TEMP/source" "$output" ||
        ! copy_resources "$CLEAN_TEMP/source" "$output" ||
        ! save_report "$output"; then
        error 'Конвертация не завершена. Рабочая конфигурация не изменена.'
        cleanup;return 1
    fi
    if [ -e "$destination" ]; then
        old="$HISTORY/$STRATEGY_ID-$(date -u +%Y%m%d-%H%M%S)-$$"
        mv "$destination" "$old" || { cleanup;return 1; }
        if ! mv "$output" "$destination"; then
            mv "$old" "$destination" || error 'Не удалось восстановить сохранённую стратегию!'
            cleanup;return 1
        fi
    else
        mv "$output" "$destination" || { cleanup;return 1; }
    fi
    message ""
    message "Сохранено: $LABEL — Flowseal $FLOW_VERSION"
    message "Каталог: $destination"
    message "Игровые порты: $GAMES"
    message 'Конвертация не применена к роутеру.'
    cat "$destination/REPORT.md"
    cleanup
}

show_strategy() {
    selected_dir=$1
    while :; do
        if [ ! -f "$selected_dir/info.json" ] || [ -L "$selected_dir" ]; then
            error 'Стратегия отсутствует.';return
        fi
        label=$(jq -r '.name + " — Flowseal " + .version' "$selected_dir/info.json")
        message ""
        message "$label"
        if [ -f "$selected_dir/nfqws2.conf" ] && [ -r "$Nfqws2_CONF" ] &&
            cmp -s "$selected_dir/nfqws2.conf" "$Nfqws2_CONF"; then
            message 'Статус: совпадает с рабочим конфигом'
            active=yes
        else active=no;message 'Статус: сохранена';fi
        message ' 1. Информация и предупреждения'
        message ' 2. Просмотреть nfqws2.conf'
        message ' 3. Проверить синтаксис и ресурсы (без применения)'
        message ' 4. Удалить стратегию'
        message ' 0. Назад'
        printf 'Выбор: '
        IFS= read -r choice || return
        case "$choice" in
            ''|0|00)return;;
            1) cat "$selected_dir/REPORT.md" ;;
            2) cat "$selected_dir/nfqws2.conf" ;;
            3) sh "$RUNTIME/validator.sh" "$selected_dir" || : ;;
            4)
                if [ "$active" = yes ]; then
                    error 'Удаление действующей конфигурации запрещено.'
                    continue
                fi
                if ask_yes "Удалить $label и прежние редакции?"; then
                    id=$(basename "$selected_dir")
                    rm -rf "$selected_dir" || return 1
                    for older in "$HISTORY/$id"-*; do
                        [ -d "$older" ] && [ ! -L "$older" ] && rm -rf "$older"
                    done
                    message 'Стратегия удалена.'
                    return
                fi ;;
            *) message 'Неизвестный пункт.' ;;
        esac
    done
}
saved_menu() {
    while :; do
        mkdir -p "$STRATEGIES" || return
        list="$HOME_DIR/.saved-index.$$"
        : > "$list"
        count=0
        message ""
        message 'Мои стратегии:'
        for item in "$STRATEGIES"/*; do
            [ -d "$item" ] && [ ! -L "$item" ] && [ -f "$item/info.json" ] || continue
            count=$((count+1))
            title=$(jq -r '.name + " — Flowseal " + .version' "$item/info.json" 2>/dev/null) || continue
            printf '%2s. %s\n' "$count" "$title"
            printf '%s\t%s\n' "$count" "$item" >> "$list"
        done
        [ "$count" -gt 0 ] || message '  Пока нет сохранённых стратегий.'
        message ' 0. Назад'
        printf 'Выберите стратегию: '
        IFS= read -r choice || { rm -f "$list";return; }
        case "$choice" in ''|0|00)rm -f "$list";return;;esac
        case "$choice" in *[!0-9]*)message 'Неверный номер.';rm -f "$list";continue;;esac
        target=$(awk -F '\t' -v id="$choice" '$1==id {print $2;exit}' "$list")
        rm -f "$list"
        [ -n "$target" ] && show_strategy "$target" || message 'Неверный номер.'
    done
}
main() {
    [ -d "$HOME_DIR" ] && [ ! -L "$HOME_DIR" ] || {
        error 'Некорректный каталог данных конвертера.';return 1;
    }
    mkdir -p "$STRATEGIES" "$TEMP" || return 1
    [ ! -L "$STRATEGIES" ] && [ ! -L "$TEMP" ] || {
        error 'Символические ссылки в каталогах конвертера запрещены.';return 1;
    }
    while :; do
        message ''
        message '======== KeenUtils | Flowseal → nfqws2 ========'
        message ' 1. Добавить стратегию'
        message ' 2. Мои стратегии'
        message ' 0. Назад в KeenUtils'
        message ' Разработка: сохранение без применения к роутеру.'
        printf 'Выберите пункт: '
        IFS= read -r choice || return 0
        case "$choice" in
            ''|0|00) return 0 ;;
            1) add_strategy || : ;;
            2) dependencies && saved_menu || : ;;
            *)message 'Неизвестный пункт.' ;;
        esac
    done
}
# Test harness sources functions without launching the interactive menu.
if [ "${KEENUTILS_FLOWSEAL_TEST_ONLY:-0}" != 1 ]; then
    main
fi
