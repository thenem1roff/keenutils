#!/bin/sh
# Destructive removal must be tested ONLY against a fake Entware/opkg tree.
set -eu
mkdir -p /opt/bin /opt/etc/opkg /opt/etc/nfqws2 /opt/etc/init.d /opt/sbin
cat >/opt/bin/opkg <<'MOCK_OPKG'
#!/bin/sh
case "$1" in
    list-installed)
        for pkg in $(cat /tmp/keenutils-uninstall-pkgs); do
            if [ "$#" -eq 1 ] || [ "$pkg" = "$2" ]; then
                printf '%s - test\n' "$pkg"
            fi
        done ;;
    remove)
        printf '%s\n' "$*" >>/tmp/keenutils-uninstall-log
        for arg in "$@"; do
            case "$arg" in
                --*|remove) continue ;;
            esac
            grep -vxF "$arg" /tmp/keenutils-uninstall-pkgs \
                >/tmp/keenutils-uninstall-next || :
            cp /tmp/keenutils-uninstall-next /tmp/keenutils-uninstall-pkgs
        done ;;
    *) echo "Unexpected opkg call: $*" >&2; exit 80 ;;
esac
MOCK_OPKG
chmod 755 /opt/bin/opkg
printf 'nfqws2-keenetic\n' >/tmp/keenutils-uninstall-pkgs
: >/tmp/keenutils-uninstall-log
printf 'CUSTOM CONFIG TO KEEP\n' >/opt/etc/nfqws2/nfqws2.conf
printf 'feed\n' >/opt/etc/opkg/nfqws2-keenetic.conf
rm -f /opt/etc/opkg/nfqws-keenetic-web.conf /opt/nfqws-menu.sh /opt/keenkit.sh /opt/bin/keenkit \
    /opt/bin/torr_watchdog.sh /opt/sbin/torrserver
# Scanned list contains only nfqws2; cancelled removal must leave it unchanged.
printf '88\n1\n1\nn\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-cancel.log
grep -Fq '88. Удаление программ' /tmp/u-cancel.log
grep -Fq 'nfqws2 [Установлен]' /tmp/u-cancel.log
grep -Fq 'Продолжить удаление nfqws2? [y/N]' /tmp/u-cancel.log
[ -s /opt/etc/nfqws2/nfqws2.conf ]
[ -s /tmp/keenutils-uninstall-pkgs ]
[ ! -s /tmp/keenutils-uninstall-log ]

# Official package removal is selected explicitly. Its configuration remains
# (the real package postrm asks whether to keep/remove it).
printf '88\n1\n1\ny\n\n4\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-nfqws2.log
grep -Fq 'remove --autoremove nfqws2-keenetic' /tmp/keenutils-uninstall-log
grep -Fq 'Программа удалена или установлена не через opkg' /tmp/u-nfqws2.log
[ -s /opt/etc/nfqws2/nfqws2.conf ]
[ -s /opt/etc/opkg/nfqws2-keenetic.conf ]

# User must confirm cleaning configuration, separate from package removal.
printf '88\n1\n2\nn\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-keep-residue.log
[ -s /opt/etc/nfqws2/nfqws2.conf ]
printf '88\n1\n2\ny\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-clean-residue.log
[ ! -e /opt/etc/nfqws2 ]
[ ! -e /opt/etc/opkg/nfqws2-keenetic.conf ]
grep -Fq 'Удалено: /opt/etc/nfqws2' /tmp/u-clean-residue.log

# Two known watchdog Cron entries can be removed; unrelated entries survive.
printf 'torrserver\n' >/tmp/keenutils-uninstall-pkgs
printf '#!/bin/sh\nexit 0\n' >/opt/sbin/torrserver
chmod 755 /opt/sbin/torrserver
cat >/opt/etc/init.d/S90torrserver <<'TORR_INIT'
#!/bin/sh
printf '%s\n' "$*" >>/tmp/keenutils-torr-stop-log
exit 0
TORR_INIT
chmod 755 /opt/etc/init.d/S90torrserver
printf '#!/bin/sh\nexit 0\n' >/opt/bin/torr_watchdog.sh
chmod 755 /opt/bin/torr_watchdog.sh
printf '1 2 * * * root echo keep\n* * * * * root /opt/bin/torr_watchdog.sh\n* * * * * root sleep 30 && /opt/bin/torr_watchdog.sh\n' >/opt/etc/crontab
# Cancel at watchdog question: no scripts or Cron modified.
cp /opt/etc/crontab /tmp/keenutils-cron-before
printf '88\n1\n1\nn\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-torr-cancel.log
cmp /opt/etc/crontab /tmp/keenutils-cron-before
[ -s /opt/bin/torr_watchdog.sh ]
grep -Fxq torrserver /tmp/keenutils-uninstall-pkgs
# Confirm watchdog disable and removal. Never touch unrelated cron or cache.
printf '88\n1\n1\ny\ny\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-torr-delete.log
grep -Fq 'remove torrserver' /tmp/keenutils-uninstall-log
grep -Fxq '1 2 * * * root echo keep' /opt/etc/crontab
! grep -Fq 'torr_watchdog.sh' /opt/etc/crontab
[ ! -e /opt/bin/torr_watchdog.sh ]
grep -Fq stop /tmp/keenutils-torr-stop-log
ls /opt/var/backups/keenutils/crontab-before-remove.* >/dev/null

# An unfamiliar watchdog entry must BLOCK removal (and keep package/cron).
printf 'torrserver\n' >/tmp/keenutils-uninstall-pkgs
: >/tmp/keenutils-uninstall-log
printf '#!/bin/sh\nexit 0\n' >/opt/bin/torr_watchdog.sh
printf '* * * * * root sleep 17 && /opt/bin/torr_watchdog.sh\n' >/opt/etc/crontab
cp /opt/etc/crontab /tmp/keenutils-custom-cron
printf '88\n1\n1\ny\ny\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-unknown-watchdog.log
cmp /opt/etc/crontab /tmp/keenutils-custom-cron
[ -s /opt/bin/torr_watchdog.sh ]
[ ! -s /tmp/keenutils-uninstall-log ]
grep -Fq 'нестандартные задания watchdog' /tmp/u-unknown-watchdog.log

# HydraRoute: standard opkg packages only, NO full upstream cleanup script.
printf 'hrneo\nhrweb\n' >/tmp/keenutils-uninstall-pkgs
: >/tmp/keenutils-uninstall-log
rm -f /opt/bin/torr_watchdog.sh
printf '%s\n' 'ROUTE CONFIG' > /opt/etc/HydraRoute-test-placeholder
printf '88\n1\n1\ny\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-hydra.log
grep -Fxq 'remove hrweb' /tmp/keenutils-uninstall-log
grep -Fxq 'remove hrneo' /tmp/keenutils-uninstall-log
! grep -q 'hr-uninstall.sh' /tmp/keenutils-uninstall-log
# A service script still present means we must not erase active NFQWS files
# even if opkg metadata is corrupted.
: >/tmp/keenutils-uninstall-pkgs
mkdir -p /opt/etc/nfqws2
printf 'KEEP\n' >/opt/etc/nfqws2/nfqws2.conf
printf '#!/bin/sh\nexit 0\n' >/opt/etc/init.d/S51nfqws2
chmod 755 /opt/etc/init.d/S51nfqws2
printf '88\n1\n2\ny\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-service-guard.log
grep -Fq 'Найдена служба nfqws2' /tmp/u-service-guard.log
grep -Fxq KEEP /opt/etc/nfqws2/nfqws2.conf
rm -f /opt/etc/init.d/S51nfqws2 /opt/etc/nfqws2/nfqws2.conf
rmdir /opt/etc/nfqws2

# AWG removal saves VPN secrets until the user explicitly chooses cleanup.
printf 'awg-manager\n' >/tmp/keenutils-uninstall-pkgs
mkdir -p /opt/etc/awg-manager
printf 'PRIVATE TEST KEY\n' >/opt/etc/awg-manager/keys.conf
printf '88\n1\n1\ny\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-awg-delete.log
grep -Fxq 'remove awg-manager' /tmp/keenutils-uninstall-log
grep -Fxq 'PRIVATE TEST KEY' /opt/etc/awg-manager/keys.conf
printf '88\n1\n2\nn\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-awg-keep.log
[ -s /opt/etc/awg-manager/keys.conf ]
printf '88\n1\n2\ny\n\n0\n0\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/u-awg-clean.log
[ ! -e /opt/etc/awg-manager ]
grep -Fq 'VPN-ключи' /tmp/u-awg-clean.log
echo 'Uninstall menu: cancel/remove/residue/watchdog/unknown-cron/Hydra tests passed.'
