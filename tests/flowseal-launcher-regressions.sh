#!/bin/sh
# Integration smoke test: main menu 77 calls a separate local child and returns.
set -eu
mkdir -p /opt/bin /opt/etc
test -f ./flowseal_converter
sh -n ./flowseal_converter
test -f ./flowseal.version
test -f ./modules/flowseal/LICENSE

launcher=/opt/bin/keenutils-flowseal
backup=''
if [ -e "$launcher" ] || [ -L "$launcher" ]; then
    backup=$(mktemp /opt/bin/.flowseal-launcher-backup.XXXXXX)
    mv "$launcher" "$backup"
fi
restore() {
    rm -f "$launcher"
    [ -z "$backup" ] || mv "$backup" "$launcher"
}
trap restore EXIT INT TERM

cat > "$launcher" <<'FAKE_CHILD'
#!/bin/sh
printf 'FLOWSEAL_CHILD_MENU\n'
IFS= read -r child_choice || :
[ "$child_choice" = 0 ] || exit 2
printf 'FLOWSEAL_CHILD_RETURN\n'
FAKE_CHILD
chmod 700 "$launcher"
printf '77\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null > /tmp/keenutils-flowseal-navigation.log

grep -Fq '77. Конвертер Flowseal' /tmp/keenutils-flowseal-navigation.log
# Visual section break after TorrServer, before standalone converter.
awk '
    /8[.] TorrServer/ {found=1;next}
    found && /^[[:space:]]*$/ {blank=1;next}
    found && /77[.] Конвертер Flowseal/ {if(blank) ok=1;found=0;blank=0}
    END {exit !ok}
' /tmp/keenutils-flowseal-navigation.log
grep -Fq 'FLOWSEAL_CHILD_MENU' /tmp/keenutils-flowseal-navigation.log
grep -Fq 'FLOWSEAL_CHILD_RETURN' /tmp/keenutils-flowseal-navigation.log
grep -Fq 'Выход.' /tmp/keenutils-flowseal-navigation.log
count=$(grep -Fc 'KeenUtils | Entware' /tmp/keenutils-flowseal-navigation.log)
[ "$count" -ge 2 ]
printf 'Flowseal child menu and return to KeenUtils: OK\n'
