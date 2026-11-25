#!/bin/sh
# Verify empty Enter behaves like 0 in every KeenUtils menu.
set -eu
mkdir -p /opt/bin /opt/etc
cat >/opt/bin/opkg <<'MOCK_OPKG'
#!/bin/sh
case "$1" in
    list-installed)
        for p in nfqws2-keenetic nfqws-keenetic-web; do
            if [ "$#" -eq 1 ] || [ "$2" = "$p" ]; then
                printf '%s - test\n' "$p"
            fi
        done ;;
    *) echo 'Unexpected opkg action' >&2; exit 70 ;;
esac
MOCK_OPKG
chmod 755 /opt/bin/opkg
# Ensure number 88/99 is visible, Enter in main exits (no pause).
printf '\n' | script -q -c 'sh ./install' /dev/null >/tmp/keenutils-main-enter.log
grep -Fq ' 88. Удаление программ' /tmp/keenutils-main-enter.log
grep -Fq ' 99. Обновить KeenUtils' /tmp/keenutils-main-enter.log
grep -Fq 'Выход.' /tmp/keenutils-main-enter.log

# Menu TorrServer: Enter returns to main, then another Enter exits.
printf '8\n\n\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-torr-enter.log
grep -Fq 'TorrServer | Управление' /tmp/keenutils-torr-enter.log
grep -Fq 'Выход.' /tmp/keenutils-torr-enter.log
! grep -Fq 'Неизвестный пункт' /tmp/keenutils-torr-enter.log

# Menu 88: Enter returns to main, then another Enter exits.
printf '88\n\n\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-remove-enter.log
grep -Fq 'Удаление программ' /tmp/keenutils-remove-enter.log
grep -Fq 'Выход.' /tmp/keenutils-remove-enter.log
! grep -Fq 'Неизвестный пункт' /tmp/keenutils-remove-enter.log

# Detail menu and linked-program menu: Enter back at each level.
# Linked-program operation also has a "press Enter to return" pause;
# that pause is not a menu selection and remains unchanged.
printf '88\n1\n3\n\n\n\n\n\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-linked-enter.log
grep -Fq 'nfqws2 | Удаление' /tmp/keenutils-linked-enter.log
grep -Fq 'Связанные программы' /tmp/keenutils-linked-enter.log
grep -Fq 'Выход.' /tmp/keenutils-linked-enter.log
! grep -Fq 'Неизвестный пункт' /tmp/keenutils-linked-enter.log

# Menu 77: Enter aborts selection and returns to main without installation.
printf '77\n\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-auto-enter.log
grep -Fq ' 77. Автоустановка программ' /tmp/keenutils-auto-enter.log
grep -Fq 'Автоустановка отменена.' /tmp/keenutils-auto-enter.log
grep -Fq 'Выход.' /tmp/keenutils-auto-enter.log

# Extract real dispatcher and batch queue into a safe mock-only shell.
awk '
    /^# One dispatcher shared by manual installation/ {copy=1}
    /^# Compact status header/ {copy=0}
    copy {print}
' install >/tmp/keenutils-auto-functions.sh
. /tmp/keenutils-auto-functions.sh

say() { printf '%s\n' "$*"; }
err() { printf 'ОШИБКА: %s\n' "$*" >&2; }
AUTO_TEST_LOG=/tmp/keenutils-auto-call-log
AUTO_FAIL_ITEM=''
record_action() {
    printf '%s\n' "$1" >> "$AUTO_TEST_LOG"
    [ "$AUTO_FAIL_ITEM" != "$1" ]
}
install_nfqws() { record_action 1; }
install_nfqws2() { record_action 2; }
install_nfqws_web() { record_action 3; }
launch_nfqws_menu() { record_action 4; }
install_keenkit() { record_action 5; }
install_hydra() { record_action 6; }
install_awg() { record_action 7; }
install_torrserver_wizard() { record_action 8; }
install_flashkeen() { record_action 9; }

# The exact user-requested sequence, in order and without interstep pauses.
: > "$AUTO_TEST_LOG"
printf '2 3 4 7 8\n' | auto_install_programs >/tmp/keenutils-auto-order.log
printf '2\n3\n4\n7\n8\n' >/tmp/keenutils-auto-expected
cmp "$AUTO_TEST_LOG" /tmp/keenutils-auto-expected
grep -Fq 'Очередь завершена без обнаруженных ошибок.' /tmp/keenutils-auto-order.log
grep -Fq '[5/5] TorrServer' /tmp/keenutils-auto-order.log
! grep -Fq 'Нажмите Enter' /tmp/keenutils-auto-order.log

# All nine selections call their preexisting functions once.
: > "$AUTO_TEST_LOG"
printf '1 2 3 4 5 6 7 8 9\n' | auto_install_programs >/tmp/keenutils-auto-all.log
printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n' >/tmp/keenutils-auto-expected
cmp "$AUTO_TEST_LOG" /tmp/keenutils-auto-expected

# Preserve the first occurrence, ignore later duplicates.
: > "$AUTO_TEST_LOG"
printf '8 2 8 3 2\n' | auto_install_programs >/tmp/keenutils-auto-dedup.log
printf '8\n2\n3\n' >/tmp/keenutils-auto-expected
cmp "$AUTO_TEST_LOG" /tmp/keenutils-auto-expected
grep -Fq 'пропускаю дубль' /tmp/keenutils-auto-dedup.log

# Failed installation must not prevent launching the next program.
: > "$AUTO_TEST_LOG"
AUTO_FAIL_ITEM=3
if printf '2 3 7\n' | auto_install_programs >/tmp/keenutils-auto-fail.log 2>&1; then
    echo 'Queue ignored failed step' >&2
    exit 1
fi
printf '2\n3\n7\n' >/tmp/keenutils-auto-expected
cmp "$AUTO_TEST_LOG" /tmp/keenutils-auto-expected
grep -Fq 'Ошибки в пунктах: 3' /tmp/keenutils-auto-fail.log
AUTO_FAIL_ITEM=''

# Reject the whole invalid selection before any action.
for bad in '2 99 3' '2 0 3' '1 2;echo unsafe' '4,7' '2 -e 3' '2 10' '2 ../x'; do
    : >"$AUTO_TEST_LOG"
    if printf '%s\n' "$bad" | auto_install_programs >/tmp/keenutils-auto-invalid.log 2>&1; then
        echo "Queue accepted invalid input: $bad" >&2
        exit 1
    fi
    [ ! -s "$AUTO_TEST_LOG" ]
done
: >"$AUTO_TEST_LOG"
printf '\n' | auto_install_programs >/tmp/keenutils-auto-cancel.log
[ ! -s "$AUTO_TEST_LOG" ]

# Manual menu number 8 still opens its 4-item submenu; queue item 8 runs
# its usual install wizard directly.
grep -Fq '8|08) torrserver_menu; continue ;;' install
grep -Fq '8) install_torrserver_wizard ;;' install
echo 'Auto-install: ordered queue, duplicates, validation, continued failures and shared functions OK.'

echo 'Enter-to-back navigation: main, TorrServer, removal, details and linked: OK'
