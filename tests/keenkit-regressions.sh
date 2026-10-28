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

rm -f /opt/keenkit.sh /opt/bin/keenkit /opt/etc/keenutils-kit-test.txt
echo 'KeenKit: installed launch, first install, return, file access, umask and corrupt-file protection OK.'
