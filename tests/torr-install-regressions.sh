#!/bin/sh
# CI-only simulated Entware service. Never run this test on a real router.
set -eu

mkdir -p /opt/etc/init.d /opt/sbin

# Load only the functions under test (no real menu, package operations or API).
awk '
    /^torr_present\(\) \{/ {copy=1}
    /^# Find the actual USB volume/ {copy=0}
    copy {print}
' install >/tmp/keenutils-torr-service-funcs.sh
awk '
    /^install_watchdog\(\) \{/ {copy=1}
    /^# Nested menu: each operation is independent/ {copy=0}
    copy {print}
' install >>/tmp/keenutils-torr-service-funcs.sh
. /tmp/keenutils-torr-service-funcs.sh

say() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
sleep() { :; }
uname() { [ "$1" = -m ] && { printf 'aarch64\n'; return 0; }; return 1; }
pkg_installed() { test -f /tmp/keenutils-torr-test-pkg; }
install_pkg() {
    [ "$1" = torrserver ] || return 1
    printf 'install\n' >>/tmp/keenutils-torr-test-log
    touch /tmp/keenutils-torr-test-pkg
    printf '#!/bin/sh\nexit 0\n' >/opt/sbin/torrserver
    chmod 755 /opt/sbin/torrserver
}
fetch_and_run() {
    [ "$1" = torrserver ] || return 2
    printf 'update\n' >>/tmp/keenutils-torr-test-log
    [ -f /tmp/keenutils-torr-test-updater-fails ] && return 1
    return 0
}
configure_torr_cache() {
    printf 'cache\n' >>/tmp/keenutils-torr-test-log
}
watchdog_complete() { test -f /tmp/keenutils-torr-test-watchdog; }

cat >/opt/etc/init.d/S90torrserver <<'MOCK_INIT'
#!/bin/sh
case "$1" in
    check|status)
        test -f /tmp/keenutils-torr-test-running ;;
    start)
        printf 'start\n' >>/tmp/keenutils-torr-test-log
        case "$(cat /tmp/keenutils-torr-test-mode)" in
            fail) exit 1 ;;
            false_negative) touch /tmp/keenutils-torr-test-running; exit 1 ;;
            *) touch /tmp/keenutils-torr-test-running; exit 0 ;;
        esac ;;
    *) exit 2 ;;
esac
MOCK_INIT
chmod 755 /opt/etc/init.d/S90torrserver
cat >/opt/etc/init.d/S55torrserver <<'OTHER_SERVICE'
#!/bin/sh
printf 'WRONG_INIT\n' >>/tmp/keenutils-torr-test-log
exit 1
OTHER_SERVICE
chmod 755 /opt/etc/init.d/S55torrserver

reset() {
    rm -f /tmp/keenutils-torr-test-pkg \
      /tmp/keenutils-torr-test-running \
      /tmp/keenutils-torr-test-updater-fails \
      /tmp/keenutils-torr-test-watchdog \
      /opt/sbin/torrserver
    printf 'normal\n' >/tmp/keenutils-torr-test-mode
    : >/tmp/keenutils-torr-test-log
}
cleanup() {
    rm -f /opt/etc/init.d/S90torrserver /opt/etc/init.d/S55torrserver \
      /opt/sbin/torrserver /tmp/keenutils-torr-test-pkg \
      /tmp/keenutils-torr-test-mode /tmp/keenutils-torr-test-running \
      /tmp/keenutils-torr-test-updater-fails \
      /tmp/keenutils-torr-test-watchdog
}
trap cleanup EXIT

# 1. Fresh opkg install: daemon must start and its state must be verified.
reset
install_torrserver >/tmp/keenutils-torr-fresh.log
grep -Fxq install /tmp/keenutils-torr-test-log
grep -Fxq start /tmp/keenutils-torr-test-log
grep -Fq 'запущенная служба проверены' /tmp/keenutils-torr-fresh.log
[ -f /tmp/keenutils-torr-test-running ]
! grep -Fq WRONG_INIT /tmp/keenutils-torr-test-log

# 2. Already running: no package operation and no extra restart.
install_torrserver >/tmp/keenutils-torr-running.log
[ "$(grep -Fc 'start' /tmp/keenutils-torr-test-log)" -eq 1 ]
[ "$(grep -Fc 'install' /tmp/keenutils-torr-test-log)" -eq 1 ]
grep -Fq 'уже запущен' /tmp/keenutils-torr-running.log

# 3. Installed but stopped: repair without reinstall.
rm -f /tmp/keenutils-torr-test-running
install_torrserver >/tmp/keenutils-torr-repair.log
[ "$(grep -Fc 'start' /tmp/keenutils-torr-test-log)" -eq 2 ]
[ "$(grep -Fc 'install' /tmp/keenutils-torr-test-log)" -eq 1 ]
[ -f /tmp/keenutils-torr-test-running ]

# 4. Start truly fails: don't print success or pretend service works.
reset
touch /tmp/keenutils-torr-test-pkg
printf '#!/bin/sh\nexit 0\n' >/opt/sbin/torrserver
chmod 755 /opt/sbin/torrserver
printf 'fail\n' >/tmp/keenutils-torr-test-mode
if install_torrserver >/tmp/keenutils-torr-fail.log 2>&1; then
    echo 'Failed start reported installation success' >&2
    exit 1
fi
grep -Fq 'служба остаётся остановленной' /tmp/keenutils-torr-fail.log
! grep -Fq 'запущенная служба проверены' /tmp/keenutils-torr-fail.log

# 5. Init says failure but process actually started; accept verified state.
printf 'false_negative\n' >/tmp/keenutils-torr-test-mode
install_torrserver >/tmp/keenutils-torr-false-negative.log
grep -Fq 'ошибку запуска' /tmp/keenutils-torr-false-negative.log
[ -f /tmp/keenutils-torr-test-running ]

# 6. No-op updater must restart stopped service and validate result.
rm -f /tmp/keenutils-torr-test-running
printf 'normal\n' >/tmp/keenutils-torr-test-mode
update_torrserver >/tmp/keenutils-torr-update.log
grep -Fq 'после обновления выполнена' /tmp/keenutils-torr-update.log
[ -f /tmp/keenutils-torr-test-running ]

# 7. Updater failure should not be called success or launch the daemon.
rm -f /tmp/keenutils-torr-test-running
touch /tmp/keenutils-torr-test-updater-fails
if update_torrserver >/tmp/keenutils-torr-update-fail.log 2>&1; then
    echo 'Failed updater returned success' >&2
    exit 1
fi
[ ! -f /tmp/keenutils-torr-test-running ]
rm -f /tmp/keenutils-torr-test-updater-fails

# 8. Cache action must start service before attempting an API call.
: >/tmp/keenutils-torr-test-log
setup_torr_cache
[ "$(head -n 1 /tmp/keenutils-torr-test-log)" = start ]
[ "$(tail -n 1 /tmp/keenutils-torr-test-log)" = cache ]

# 9. A failed service start must block changing cache settings.
rm -f /tmp/keenutils-torr-test-running
printf 'fail\n' >/tmp/keenutils-torr-test-mode
: >/tmp/keenutils-torr-test-log
if setup_torr_cache >/tmp/keenutils-torr-cache-fail.log 2>&1; then
    echo 'Dead service reached cache API' >&2
    exit 1
fi
! grep -Fxq cache /tmp/keenutils-torr-test-log

# 10. Existing watchdog installation still verifies/starts the daemon.
printf 'normal\n' >/tmp/keenutils-torr-test-mode
touch /tmp/keenutils-torr-test-watchdog
install_watchdog >/tmp/keenutils-torr-watchdog.log
grep -Fq 'уже установлен' /tmp/keenutils-torr-watchdog.log
[ -f /tmp/keenutils-torr-test-running ]

echo 'TorrServer install/start: fresh, running, repair, failed start, update, cache and watchdog OK.'
