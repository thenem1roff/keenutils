#!/bin/sh
# Simulated Entware: test self-uninstall without affecting real programs.
set -eu
mkdir -p /opt/bin /opt/etc/nfqws2 /opt/etc/keenutils \
    /opt/var/backups/keenutils
cat >/opt/bin/opkg <<'MOCK_OPKG'
#!/bin/sh
case "$1" in
    list-installed)
        for pkg in nfqws2-keenetic torrserver; do
            if [ "$#" -eq 1 ] || [ "$2" = "$pkg" ]; then
                printf '%s - test\n' "$pkg"
            fi
        done ;;
    *) printf 'Unexpected package operation %s\n' "$*" >&2; exit 75 ;;
esac
MOCK_OPKG
chmod 755 /opt/bin/opkg
cp ./install /opt/bin/keenutils
chmod 755 /opt/bin/keenutils
rm -f /opt/bin/utils
ln -s /opt/bin/keenutils /opt/bin/utils
cp ./install /opt/bin/keenutils.backup
cp ./install /tmp/keenutils-install.sh
cp ./sources.conf /opt/etc/keenutils/sources.conf
printf 'OTHER APP CONFIG\n' >/opt/etc/nfqws2/nfqws2.conf
printf 'TORR BACKUP\n' >/opt/var/backups/keenutils/torr-settings.test
printf '1 2 * * * root echo keep\n* * * * * root /opt/bin/torr_watchdog.sh\n' \
    >/opt/etc/crontab
printf '#!/bin/sh\nexit 0\n' >/opt/bin/torr_watchdog.sh
chmod 755 /opt/bin/torr_watchdog.sh
cp /opt/etc/crontab /tmp/keenutils-self-cron-original

# Find KeenUtils's dynamically assigned selection number after scanning
# any leftover mock program installations from preceding CI tests.
printf '88\n\n\n' | script -q -c 'sh ./install' /dev/null \
    >/tmp/keenutils-self-menu.log
self_index=$(sed -n \
    's/^[[:space:]]*\([0-9][0-9]*\)\. KeenUtils \[Установлен\].*/\1/p' \
    /tmp/keenutils-self-menu.log | head -n 1)
[ -n "$self_index" ]
grep -Fq 'nfqws2' /tmp/keenutils-self-menu.log

# Cancel must preserve every file, including all KeenUtils assets.
printf '88\n%s\nn\n\n\n' "$self_index" |
    script -q -c 'sh ./install' /dev/null \
    >/tmp/keenutils-self-cancel.log
grep -Fq 'Полное удаление KeenUtils' /tmp/keenutils-self-cancel.log
grep -Fq 'Удаление отменено.' /tmp/keenutils-self-cancel.log
[ -f /opt/bin/keenutils ]
[ -L /opt/bin/utils ]
[ "$(readlink /opt/bin/utils)" = /opt/bin/keenutils ]
[ -f /opt/bin/keenutils.backup ]
[ -f /opt/etc/keenutils/sources.conf ]
[ -f /tmp/keenutils-install.sh ]
cmp /opt/etc/crontab /tmp/keenutils-self-cron-original

# An unknown replacement of the backup must BLOCK removal, not delete it.
printf 'FOREIGN BACKUP\n' >/opt/bin/keenutils.backup
printf '88\n%s\n\n\n' "$self_index" |
    script -q -c 'sh ./install' /dev/null \
    >/tmp/keenutils-self-foreign.log
grep -Fq 'не похожа на KeenUtils' /tmp/keenutils-self-foreign.log
[ -f /opt/bin/keenutils ]
grep -Fxq 'FOREIGN BACKUP' /opt/bin/keenutils.backup

# Exact and validated files are removed; unrelated programs remain.
cp ./install /opt/bin/keenutils.backup
printf '88\n%s\ny\n' "$self_index" |
    script -q -c 'sh ./install' /dev/null \
    >/tmp/keenutils-self-confirm.log
grep -Fq 'KeenUtils удалён.' /tmp/keenutils-self-confirm.log
[ ! -e /opt/bin/keenutils ]
[ ! -e /opt/bin/utils ]
[ ! -L /opt/bin/utils ]
[ ! -e /opt/bin/keenutils.backup ]
[ ! -e /opt/etc/keenutils/sources.conf ]
[ ! -e /opt/etc/keenutils ]
[ ! -e /tmp/keenutils-install.sh ]
[ -f /opt/etc/nfqws2/nfqws2.conf ]
grep -Fxq 'OTHER APP CONFIG' /opt/etc/nfqws2/nfqws2.conf
grep -Fxq 'TORR BACKUP' /opt/var/backups/keenutils/torr-settings.test
[ -x /opt/bin/torr_watchdog.sh ]
cmp /opt/etc/crontab /tmp/keenutils-self-cron-original
[ -x /opt/bin/opkg ]
# Unrelated file occupying the short name must not be removed.
cp ./install /opt/bin/keenutils
chmod 755 /opt/bin/keenutils
printf 'FOREIGN SHORT COMMAND\n' >/opt/bin/utils
printf '88\n%s\ny\n' "$self_index" |
    script -q -c 'sh ./install' /dev/null \
    >/tmp/keenutils-self-foreign-utils.log
grep -Fq 'KeenUtils удалён.' /tmp/keenutils-self-foreign-utils.log
[ ! -e /opt/bin/keenutils ]
grep -Fxq 'FOREIGN SHORT COMMAND' /opt/bin/utils
rm -f /opt/bin/utils
echo 'Self-uninstall: safe utils alias removal, foreign-file guard and program data preservation OK.'
