#!/bin/sh
# CI-only integration test with fake Entware service, process, GitHub and API.
# Must not be run on an actual router.
set -eu
mkdir -p /opt/bin /opt/sbin /opt/etc/init.d

cat >/opt/bin/opkg <<'MOCK_OPKG'
#!/bin/sh
case "$1" in
    list-installed) printf '%s - test\n' "$2" ;;
    *) echo "Unexpected opkg action: $*" >&2; exit 90 ;;
esac
MOCK_OPKG
cat >/opt/bin/uname <<'MOCK_UNAME'
#!/bin/sh
[ "$1" = '-m' ] && { echo aarch64; exit 0; }
exec /usr/bin/uname "$@"
MOCK_UNAME
cat >/opt/bin/date <<'MOCK_DATE'
#!/bin/sh
[ "$1" = '+%S' ] && { echo 03; exit 0; }
exec /usr/bin/date "$@"
MOCK_DATE
cat >/opt/bin/sleep <<'MOCK_SLEEP'
#!/bin/sh
exit 0
MOCK_SLEEP
cat >/opt/bin/pgrep <<'MOCK_PGREP'
#!/bin/sh
[ "$1" = '-x' ] && [ "$2" = torrserver ] || exit 2
test -f /tmp/keenutils-ts-running
MOCK_PGREP
cat >/opt/bin/curl <<'MOCK_CURL'
#!/bin/sh
case "$*" in
    *api.github.com/repos/YouROK/TorrServer/releases/latest*)
        printf '{\n  "tag_name": "MatriX.147.2"\n}\n' ;;
    *releases/download/MatriX.147.2/TorrServer-linux-arm64*)
        dest=''
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -o) shift; dest="$1" ;;
            esac
            shift
        done
        [ -n "$dest" ] || exit 2
        cat >"$dest" <<'NEW_BIN'
#!/bin/sh
echo 'github version MatriX.147.2'
NEW_BIN
        ;;
    *127.0.0.1:8090/echo*)
        mode=$(cat /tmp/keenutils-ts-mode)
        if [ -f /tmp/keenutils-ts-running ]; then
            case "$mode" in
                fail_api) printf '000' ;;
                auth_api) printf '401' ;;
                *) printf '200' ;;
            esac
        else
            printf '000'
        fi ;;
    *) echo "Unexpected curl: $*" >&2; exit 2 ;;
esac
MOCK_CURL
cat >/opt/etc/init.d/S90torrserver <<'MOCK_SERVICE'
#!/bin/sh
mode=$(cat /tmp/keenutils-ts-mode)
case "$1" in
    stop)
        if [ ! -f /tmp/keenutils-ts-running ]; then
            echo 'Checking torrserver... dead.'
            exit 1
        fi
        case "$mode" in
            stuck_stop)
                echo 'Checking torrserver... alive.'
                exit 1 ;;
            *)
                rm -f /tmp/keenutils-ts-running
                echo 'Checking torrserver... dead.'
                # Some init scripts report failure despite successfully stopping.
                [ "$mode" = false_stop ] && exit 1
                exit 0 ;;
        esac ;;
    start)
        if [ "$mode" = fail_new_start ] &&
           /opt/sbin/torrserver --version | grep -q 'MatriX.147.2'; then
            echo 'Failed to start new TorrServer' >&2
            exit 1
        fi
        touch /tmp/keenutils-ts-running
        exit 0 ;;
    *) exit 2 ;;
esac
MOCK_SERVICE
chmod 755 /opt/bin/opkg /opt/bin/uname /opt/bin/date /opt/bin/sleep \
    /opt/bin/pgrep /opt/bin/curl /opt/etc/init.d/S90torrserver

cleanup() {
    rm -f /opt/bin/uname /opt/bin/date /opt/bin/sleep /opt/bin/pgrep \
        /opt/bin/curl /opt/sbin/torrserver /opt/sbin/torrserver.backup \
        /opt/etc/init.d/S90torrserver /tmp/keenutils-ts-running \
        /tmp/keenutils-ts-mode
}
trap cleanup EXIT

reset_binary() {
    cat >/opt/sbin/torrserver <<'OLD_BIN'
#!/bin/sh
echo 'github version MatriX.141'
OLD_BIN
    chmod 755 /opt/sbin/torrserver
    rm -f /tmp/keenutils-ts-running
}

# Clean install: service was never started. An unsuccessful init stop must
# not abort the updater, and the new version must start successfully.
reset_binary
echo normal >/tmp/keenutils-ts-mode
sh ./torrserver >/tmp/keenutils-ts-dead.log 2>&1
grep -Fq 'уже остановлен' /tmp/keenutils-ts-dead.log
grep -Fq 'TorrServer успешно обновлён!' /tmp/keenutils-ts-dead.log
/opt/sbin/torrserver --version | grep -Fq 'MatriX.147.2'
[ -f /tmp/keenutils-ts-running ]
/opt/sbin/torrserver.backup --version | grep -Fq 'MatriX.141'

# Service is active, but init stop returns failure AFTER the process exits.
reset_binary
touch /tmp/keenutils-ts-running
echo false_stop >/tmp/keenutils-ts-mode
sh ./torrserver >/tmp/keenutils-ts-false-stop.log 2>&1
grep -Fq 'вернул ошибку остановки' /tmp/keenutils-ts-false-stop.log
grep -Fq 'TorrServer успешно обновлён!' /tmp/keenutils-ts-false-stop.log

# A stuck process must block replacement: preserve the original executable.
reset_binary
touch /tmp/keenutils-ts-running
echo stuck_stop >/tmp/keenutils-ts-mode
if sh ./torrserver >/tmp/keenutils-ts-stuck.log 2>&1; then
    echo 'Unsafe replacement occurred while process was running' >&2
    exit 1
fi
grep -Fq 'Бинарник НЕ заменён' /tmp/keenutils-ts-stuck.log
/opt/sbin/torrserver --version | grep -Fq 'MatriX.141'
[ -f /tmp/keenutils-ts-running ]

# New binary replacement succeeds, but start fails. Restore original
# atomically and bring the originally running service back up.
reset_binary
touch /tmp/keenutils-ts-running
echo fail_new_start >/tmp/keenutils-ts-mode
if sh ./torrserver >/tmp/keenutils-ts-startfail.log 2>&1; then
    echo 'Failed start incorrectly reported success' >&2
    exit 1
fi
grep -Fq 'Восстановление предыдущей версии' /tmp/keenutils-ts-startfail.log
/opt/sbin/torrserver --version | grep -Fq 'MatriX.141'
[ -f /tmp/keenutils-ts-running ]

# API remains unavailable: restore the original version and its running state.
reset_binary
touch /tmp/keenutils-ts-running
echo fail_api >/tmp/keenutils-ts-mode
if sh ./torrserver >/tmp/keenutils-ts-api-fail.log 2>&1; then
    echo 'Unresponsive API incorrectly reported success' >&2
    exit 1
fi
grep -Fq 'Обновление отменено' /tmp/keenutils-ts-api-fail.log
/opt/sbin/torrserver --version | grep -Fq 'MatriX.141'
[ -f /tmp/keenutils-ts-running ]

# On an authenticated instance, HTTP 401 from loopback proves it is alive.
reset_binary
echo auth_api >/tmp/keenutils-ts-mode
sh ./torrserver >/tmp/keenutils-ts-auth.log 2>&1
grep -Fq 'API: HTTP 401' /tmp/keenutils-ts-auth.log
/opt/sbin/torrserver --version | grep -Fq 'MatriX.147.2'

echo 'TorrServer updater: cold start, stop-code mismatch, blocked swap, rollback, API and auth tests passed.'
