#!/bin/sh
# Root-only CI mocks; no router packages or settings are modified by tests.
set -eu
mkdir -p /opt/bin /opt/etc /opt/sbin
cp ./install /opt/bin/keenutils
chmod 755 /opt/bin/keenutils
cp ./install /tmp/keenutils-header-remote
printf 'nfqws2-keenetic\nnfqws-keenetic-web\nawg-manager\n' \
  >/tmp/keenutils-header-packages
: >/tmp/keenutils-header-network-count
cat >/opt/bin/opkg <<'MOCK_OPKG'
#!/bin/sh
case "$1" in
  list-installed)
    for p in $(cat /tmp/keenutils-header-packages); do
      [ "$#" -eq 1 ] || [ "$2" = "$p" ] || continue
      printf '%s - 1.0\n' "$p"
    done ;;
  remove)
    for arg in "$@"; do
      case "$arg" in remove|--*) continue ;; esac
      grep -vxF "$arg" /tmp/keenutils-header-packages \
        >/tmp/keenutils-header-next || :
      cp /tmp/keenutils-header-next /tmp/keenutils-header-packages
    done ;;
  *) echo 'Unexpected opkg operation' >&2; exit 60 ;;
esac
MOCK_OPKG
chmod 755 /opt/bin/opkg
cat >/opt/bin/ndmc <<'MOCK_NDMC'
#!/bin/sh
[ "$1" = -c ] && [ "$2" = "show version" ] || exit 1
printf '  model: Giga (KN-1012)\n'
MOCK_NDMC
chmod 755 /opt/bin/ndmc
cat >/opt/bin/curl <<'MOCK_CURL'
#!/bin/sh
printf 'called\n' >> /tmp/keenutils-header-network-count
[ "${KEENUTILS_TEST_OFFLINE:-0}" = 1 ] && exit 7
out=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then shift; out=$1; fi
  shift
done
[ -n "$out" ] || exit 1
cp /tmp/keenutils-header-remote "$out"
MOCK_CURL
chmod 755 /opt/bin/curl
rm -f /opt/nfqws-menu.sh /opt/keenkit.sh /opt/sbin/torrserver \
  /opt/bin/torr_watchdog.sh
printf '4 3 * * * root echo keep\n' >/opt/etc/crontab

# Installed local file differs from remote; indicator survives submenu redraw.
printf '# prior version\n' >>/opt/bin/keenutils
printf '77\n0\n00\n' |
  script -q -c 'KEENUTILS_DISABLE_UPDATE_CHECK=0 NO_COLOR=1 sh /opt/bin/keenutils' \
    /dev/null >/tmp/keenutils-header-outdated.log
grep -Fq 'Keenetic Giga (KN-1012) |' /tmp/keenutils-header-outdated.log
grep -Fq 'nfqws2' /tmp/keenutils-header-outdated.log
grep -Fq 'nfqws-web' /tmp/keenutils-header-outdated.log
grep -Fq 'AWG Manager' /tmp/keenutils-header-outdated.log
grep -Fq 'Доступно обновление KeenUtils' /tmp/keenutils-header-outdated.log
test "$(wc -l </tmp/keenutils-header-network-count)" = 1
! grep -Fq ' 99.' /tmp/keenutils-header-outdated.log

# Same bytes: no update notification.
cp ./install /opt/bin/keenutils
printf '00\n' |
  script -q -c 'KEENUTILS_DISABLE_UPDATE_CHECK=0 NO_COLOR=1 sh /opt/bin/keenutils' \
    /dev/null >/tmp/keenutils-header-current.log
! grep -Fq 'Доступно обновление KeenUtils' /tmp/keenutils-header-current.log
test "$(wc -l </tmp/keenutils-header-network-count)" = 2

# Offline: silently fall back to local menus without claiming up-to-date.
printf '# prior version\n' >> /opt/bin/keenutils
printf '00\n' |
  script -q -c 'KEENUTILS_DISABLE_UPDATE_CHECK=0 KEENUTILS_TEST_OFFLINE=1 NO_COLOR=1 sh /opt/bin/keenutils' \
    /dev/null >/tmp/keenutils-header-offline.log
grep -Fq ' 77. Удаление программ' /tmp/keenutils-header-offline.log
! grep -Fq 'Доступно обновление KeenUtils' /tmp/keenutils-header-offline.log
test "$(wc -l </tmp/keenutils-header-network-count)" = 3

# A package removal must be reflected in the next header without another
# remote check. The first detected app in menu 77 is nfqws2.
printf '77\n1\n1\ny\n\n0\n0\n00\n' |
  script -q -c 'KEENUTILS_DISABLE_UPDATE_CHECK=0 KEENUTILS_TEST_OFFLINE=1 NO_COLOR=1 sh /opt/bin/keenutils' \
    /dev/null >/tmp/keenutils-header-refresh.log
test "$(wc -l </tmp/keenutils-header-network-count)" = 4
! grep -Fxq nfqws2-keenetic /tmp/keenutils-header-packages
# nfqws-web and AWG Manager are still there; only nfqws2 is absent from final header.
awk '
  /Установлены:/ {block=1; line=""; next}
  block && /----------------------------------------/ {
    if (line != "") last=line
    block=0
    next
  }
  block {line=line "\n" $0}
  END {
    if (last ~ /nfqws2/) exit 1
    if (last !~ /nfqws-web/ || last !~ /AWG Manager/) exit 1
  }
' /tmp/keenutils-header-refresh.log

printf 'Header status, update indicator, offline behavior and refresh: OK\n'
