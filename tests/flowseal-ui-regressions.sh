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
# Apply and manual undo must use the common [Y/n] prompt with Enter=Yes.
# Replace the deployment helper with a harmless call recorder.
mkdir -p "$work/mock-runtime"
cat > "$work/mock-runtime/deployer.sh" <<'MOCK_DEPLOY'
#!/bin/sh
printf '%s\n' "$1" >> "$KEENUTILS_FLOWSEAL_HOME/action.log"
MOCK_DEPLOY
RUNTIME="$work/mock-runtime"
printf '5\nn\n\n0\n' | show_strategy "$strategy" > "$work/confirm-no.log"
grep -Fq 'Применить эту стратегию к nfqws2? [Y/n]:' "$work/confirm-no.log"
grep -Fq 'Действие отменено.' "$work/confirm-no.log"
test ! -e "$HOME_DIR/action.log"
printf '5\n\n\n0\n' | show_strategy "$strategy" > "$work/confirm-yes.log"
grep -Fq 'Применить эту стратегию к nfqws2? [Y/n]:' "$work/confirm-yes.log"
grep -Fxq apply "$HOME_DIR/action.log"
printf '3\nn\n\n0\n' | deployment_menu > "$work/undo-no.log"
grep -Fq 'Восстановить предыдущую конфигурацию? [Y/n]:' "$work/undo-no.log"
test "$(wc -l < "$HOME_DIR/action.log")" -eq 1
printf '3\n\n\n0\n' | deployment_menu > "$work/undo-yes.log"
grep -Fxq undo "$HOME_DIR/action.log"
test "$(wc -l < "$HOME_DIR/action.log")" -eq 2
# Active status is read from a deployed config checksum, not from template equality.
Nfqws2_CONF="$work/live.conf"
printf '# preserved ISP settings\n' > "$Nfqws2_CONF"
mkdir -p "$HOME_DIR/deployments"
sha=$(sha256sum "$Nfqws2_CONF" | awk '{print $1}')
printf 'flowseal-1.10.4-alt12\t%s\n' "$sha" > "$HOME_DIR/deployments/active"
printf '0\n' | show_strategy "$strategy" > "$work/active.log"
grep -Fq 'Статус: совпадает с рабочим конфигом' "$work/active.log"
# Delete must be unavailable when active metadata identifies this strategy.
printf '6\n\n0\n' | show_strategy "$strategy" > "$work/blocked-delete.log" 2>&1
grep -Fq 'Удаление действующей конфигурации запрещено' "$work/blocked-delete.log"
# Read-only pages leave stored strategies unchanged.
test -f "$strategy/info.json"
test -f "$strategy/nfqws2.conf"
printf 'Flowseal submenu placement, Enter pause and redraw: OK\n'
