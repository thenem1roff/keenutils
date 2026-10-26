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
echo 'Enter-to-back navigation: main, TorrServer, removal, details and linked: OK'
