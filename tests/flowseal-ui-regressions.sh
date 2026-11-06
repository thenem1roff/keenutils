#!/bin/sh
# Navigation: strategy menu stays above details, Enter returns to clean menu.
# Must work with POSIX sh and without a real router or interactive terminal.
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
export KEENUTILS_FLOWSEAL_TEST_ONLY=1
export KEENUTILS_FLOWSEAL_HOME="$work/home"
mkdir -p "$KEENUTILS_FLOWSEAL_HOME"
. ./modules/flowseal/menu.sh
RUNTIME="$PWD/modules/flowseal"
strategy="$STRATEGIES/flowseal-1.10.4-alt12"
mkdir -p "$strategy"
cat > "$strategy/info.json" <<'JSON'
{"name":"ALT12","version":"1.10.4","warnings":0,"state":"saved_only"}
JSON
cat > "$strategy/REPORT.md" <<'REPORT'
REPORT-DETAIL: saved strategy, no router changes
REPORT
cat > "$strategy/nfqws2.conf" <<'CONF'
ISP_INTERFACE='eth3'
NFQWS_BASE_ARGS="--lua-init=@/opt/etc/nfqws2/lua/zapret-lib.lua"
NFQWS_ARGS="--filter-tcp=443"
TCP_PORTS=443
UDP_PORTS=
CONF
# No Enter after selecting 1: show details and prompt, but do not redraw.
printf '1\n' | show_strategy "$strategy" > "$work/no-enter.log"
test "$(grep -Fc 'KeenUtils | Моя стратегия' "$work/no-enter.log")" -eq 2
grep -Fq 'REPORT-DETAIL' "$work/no-enter.log"
grep -Fq 'Нажмите Enter, чтобы вернуться к выбору пункта' "$work/no-enter.log"

# Enter resumes the menu. Test all 4 read-only pages and navigate back with 0.
printf '1\n\n2\n\n3\n\n4\n\n0\n' | show_strategy "$strategy" > "$work/pages.log"
test "$(grep -Fc 'KeenUtils | Моя стратегия' "$work/pages.log")" -eq 9
test "$(grep -Fc 'Нажмите Enter, чтобы вернуться к выбору пункта' "$work/pages.log")" -eq 4
grep -Fq 'REPORT-DETAIL' "$work/pages.log"
grep -Fq 'Конфигурация nfqws2.conf' "$work/pages.log"
grep -Fq 'ISP_INTERFACE=' "$work/pages.log"
grep -Fq 'Проверка совместимости nfqws2' "$work/pages.log"
grep -Fq 'Сравнение с установленным nfqws2' "$work/pages.log"
# Details must ALWAYS appear below a menu, not before it.
awk '
    /KeenUtils \| Моя стратегия/ { latest_menu=NR; headers++ }
    /REPORT-DETAIL/ {if (!latest_menu || latest_menu>=NR) bad=1; report++}
    /ISP_INTERFACE=/ {if (!latest_menu || latest_menu>=NR) bad=1; config++}
    /Проверка совместимости nfqws2/ {if (!latest_menu || latest_menu>=NR) bad=1; validator++}
    /Сравнение с установленным nfqws2/ {if (!latest_menu || latest_menu>=NR) bad=1; preview++}
    END {if (bad || headers!=9 || report!=1 || config!=1 || validator!=1 || preview!=1) exit 1}
' "$work/pages.log"
# The submenu must not interpret an empty Enter as the "Back" action.
printf '\n0\n' | show_strategy "$strategy" > "$work/blank.log"
test "$(grep -Fc 'KeenUtils | Моя стратегия' "$work/blank.log")" -eq 2
# Applying requires explicit uppercase APPLY; arbitrary input must cancel.
printf '5\nno\n\n0\n' | show_strategy "$strategy" > "$work/confirm.log"
grep -Fq 'Для подтверждения введите APPLY' "$work/confirm.log"
grep -Fq 'Действие отменено.' "$work/confirm.log"
# Read-only pages leave stored strategies unchanged.
test -f "$strategy/info.json"
test -f "$strategy/nfqws2.conf"
printf 'Flowseal submenu placement, Enter pause and redraw: OK\n'
