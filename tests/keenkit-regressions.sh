#!/bin/sh
# KeenKit is delegated to the original upstream script, never reimplemented.
# Run only in the CI fake Entware filesystem, not on a production router.
set -eu

mkdir -p /opt/bin /opt/etc/keenutils
rm -f /opt/keenkit.sh /opt/bin/keenkit /opt/etc/keenutils-kit-test.txt

cat >/opt/keenkit.sh <<'MOCK_KIT'
#!/bin/sh
printf 'KEENKIT MENU OPENED\n'
printf 'KEENKIT UMASK=%s\n' "$(umask)"
printf 'test\n' >/opt/etc/keenutils-kit-test.txt
selection=''
IFS= read -r selection || :
printf 'KEENKIT EXIT=%s\n' "$selection"
MOCK_KIT
chmod 755 /opt/keenkit.sh
ln -s /opt/keenkit.sh /opt/bin/keenkit

# A previously installed KeenKit must launch immediately without an installer,
# then return to the KeenUtils main menu after the original 00 exit.
printf '5\n00\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-kit-installed.log
grep -Fq 'Запуск уже установленного KeenKit.' /tmp/keenutils-kit-installed.log
grep -Fq 'KEENKIT MENU OPENED' /tmp/keenutils-kit-installed.log
grep -Fq 'KEENKIT EXIT=00' /tmp/keenutils-kit-installed.log
grep -Fq 'KEENKIT UMASK=0022' /tmp/keenutils-kit-installed.log
grep -Fq 'Выход.' /tmp/keenutils-kit-installed.log
! grep -Fq 'Скачать и запустить официальный установщик KeenKit?' /tmp/keenutils-kit-installed.log
# Test actual read access (default ACLs can change the numeric mode).
su -s /bin/sh nobody -c 'test -r /opt/etc/keenutils-kit-test.txt'

# KeenKit's child is isolated; exiting it cannot change the parent's umask.
awk '/^install_keenkit\(\) \{/ {copy=1}
     /^install_hydra\(\) \{/ {copy=0}
     copy {print}' install >/tmp/keenutils-kit-function.sh
. /tmp/keenutils-kit-function.sh
say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }
umask 077
install_keenkit </dev/null >/tmp/keenutils-kit-direct.log
[ "$(umask)" = 0077 ]

# A damaged installed script must not be executed or silently overwritten.
printf 'if then\n' >/opt/keenkit.sh
printf '5\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-kit-broken.log
grep -Fq 'Установленный KeenKit повреждён' /tmp/keenutils-kit-broken.log
! grep -Fq 'Скачать и запустить официальный установщик KeenKit?' /tmp/keenutils-kit-broken.log

# A first-time installation should delegate upstream install.sh, which itself
# execs keenkit.sh: KeenUtils must not launch KeenKit twice afterwards.
rm -f /opt/keenkit.sh /opt/bin/keenkit
cat >/tmp/keenutils-kit-installer-fixture <<'MOCK_INSTALL'
#!/bin/sh
printf 'KEENKIT UPSTREAM INSTALLER\n'
cat >/opt/keenkit.sh <<'NEW_KIT'
#!/bin/sh
printf 'KEENKIT MENU OPENED\n'
printf 'KEENKIT UMASK=%s\n' "$(umask)"
printf 'test\n' >/opt/etc/keenutils-kit-test.txt
selection=''
IFS= read -r selection || :
printf 'KEENKIT EXIT=%s\n' "$selection"
NEW_KIT
chmod 755 /opt/keenkit.sh
ln -s /opt/keenkit.sh /opt/bin/keenkit
exec sh /opt/keenkit.sh
MOCK_INSTALL
cp ./sources.conf /opt/etc/keenutils/sources.conf
cat >/opt/bin/wget <<'MOCK_WGET'
#!/bin/sh
[ "$1" = -q ] && [ "$2" = -O ] || exit 1
case "$4" in
    */sources.conf) cp ./sources.conf "$3" ;;
    https://raw.githubusercontent.com/spatiumstas/KeenKit/main/install.sh)
        cp /tmp/keenutils-kit-installer-fixture "$3" ;;
    *) exit 1 ;;
esac
MOCK_WGET
chmod 755 /opt/bin/wget

# 5=install; Enter=confirm; 00=exit KeenKit; Enter=KeenUtils pause; 00=exit.
printf '5\n\n00\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-kit-first.log
grep -Fq 'KEENKIT UPSTREAM INSTALLER' /tmp/keenutils-kit-first.log
grep -Fq 'KEENKIT MENU OPENED' /tmp/keenutils-kit-first.log
grep -Fq 'KEENKIT EXIT=00' /tmp/keenutils-kit-first.log
grep -Fq 'KEENKIT UMASK=0022' /tmp/keenutils-kit-first.log
grep -Fq 'Выход.' /tmp/keenutils-kit-first.log
[ "$(grep -Fc 'KEENKIT MENU OPENED' /tmp/keenutils-kit-first.log)" -eq 1 ]
[ -f /opt/keenkit.sh ]
[ "$(readlink /opt/bin/keenkit)" = /opt/keenkit.sh ]
su -s /bin/sh nobody -c 'test -r /opt/etc/keenutils-kit-test.txt'

# Batch with already-installed KeenKit must NOT open its interactive menu.
printf '77\n5\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-kit-batch-installed.log
grep -Fq 'KeenKit уже установлен. Автозапуск меню пропущен.' /tmp/keenutils-kit-batch-installed.log
! grep -Fq 'KEENKIT MENU OPENED' /tmp/keenutils-kit-batch-installed.log
grep -Fq 'Очередь завершена без обнаруженных ошибок.' /tmp/keenutils-kit-batch-installed.log

# First-install batch uses the official installer body, but strips only the
# precise final exec statement which otherwise hijacks the queue.
rm -f /opt/keenkit.sh /opt/bin/keenkit
cat >/tmp/keenutils-kit-installer-fixture <<'MOCK_BATCH_INSTALL'
#!/bin/sh
OPT_DIR=/opt
SCRIPT=keenkit.sh
printf 'KEENKIT UPSTREAM INSTALLER\n'
cat >/opt/keenkit.sh <<'NEW_KIT'
#!/bin/sh
printf 'KEENKIT MENU OPENED\n'
NEW_KIT
chmod 755 /opt/keenkit.sh
ln -s /opt/keenkit.sh /opt/bin/keenkit
exec $OPT_DIR/$SCRIPT
MOCK_BATCH_INSTALL
printf '77\n5\n\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-kit-batch-first.log
grep -Fq 'KEENKIT UPSTREAM INSTALLER' /tmp/keenutils-kit-batch-first.log
grep -Fq 'KeenKit установлен в /opt/keenkit.sh' /tmp/keenutils-kit-batch-first.log
! grep -Fq 'KEENKIT MENU OPENED' /tmp/keenutils-kit-batch-first.log
test -f /opt/keenkit.sh
test -L /opt/bin/keenkit
grep -Fq 'Очередь завершена без обнаруженных ошибок.' /tmp/keenutils-kit-batch-first.log

# If upstream changes the final exec, do not rewrite unknown installer code.
rm -f /opt/keenkit.sh /opt/bin/keenkit
sed 's|exec \$OPT_DIR/\$SCRIPT|exec sh /opt/keenkit.sh|' \
    /tmp/keenutils-kit-installer-fixture >/tmp/keenutils-kit-changed-installer
cp /tmp/keenutils-kit-changed-installer /tmp/keenutils-kit-installer-fixture
printf '77\n5\n\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-kit-batch-unknown.log
grep -Fq 'KeenKit изменил запуск установщика' /tmp/keenutils-kit-batch-unknown.log
grep -Fq 'Ошибки в пунктах: 5' /tmp/keenutils-kit-batch-unknown.log
test ! -e /opt/keenkit.sh

rm -f /opt/keenkit.sh /opt/bin/keenkit /opt/etc/keenutils-kit-test.txt
echo 'KeenKit: manual UI, batch no-launch (installed and first-time), upstream safety and permissions OK.'
