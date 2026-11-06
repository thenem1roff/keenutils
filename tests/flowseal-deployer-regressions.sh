#!/bin/sh
# End-to-end install/rollback on a completely isolated fake Entware root.
# No writes to real /opt, no network, no Python.
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
export KEENUTILS_FLOWSEAL_TEST_ONLY=1
export KEENUTILS_FLOWSEAL_HOME="$work/keenutils"
export KEENUTILS_FLOWSEAL_TEST_ROOT="$work/opt"
base="$work/opt/etc/nfqws2"
service="$work/opt/etc/init.d/S51nfqws2"
deployer=modules/flowseal/deployer.sh
mkdir -p "$base/lists" "$base/blobs" "$base/lua" "$work/opt/usr/bin" \
         "$work/opt/etc/init.d" "$work/keenutils/strategies"
printf '# stock Lua\n' > "$base/lua/zapret-lib.lua"
printf '# stock Lua\n' > "$base/lua/zapret-antidpi.lua"
cat > "$work/opt/usr/bin/nfqws2" <<'BIN'
#!/bin/sh
exit 0
BIN
chmod 755 "$work/opt/usr/bin/nfqws2"
cat > "$service" <<'SERVICE'
#!/bin/sh
set -u
state="$KEENUTILS_FLOWSEAL_TEST_ROOT/running"
conf="$KEENUTILS_FLOWSEAL_TEST_ROOT/etc/nfqws2/nfqws2.conf"
case "$1" in
    status)
        if [ -f "$state" ]; then echo 'Service NFQWS2 is running'
        else echo 'Service NFQWS2 is stopped';fi ;;
    start|restart)
        if grep -Fq 'FORCE_FAIL' "$conf"; then
            rm -f "$state"
            echo 'Mock nfqws2 refused strategy' >&2
            exit 1
        fi
        : > "$state"
        printf '%s\n' "$1" >> "$KEENUTILS_FLOWSEAL_TEST_ROOT/service-calls"
        echo 'Started NFQWS2 service' ;;
    stop)
        rm -f "$state"
        printf '%s\n' stop >> "$KEENUTILS_FLOWSEAL_TEST_ROOT/service-calls" ;;
    *)exit 1;;
esac
SERVICE
chmod 755 "$service"
cat > "$base/nfqws2.conf" <<'CONF'
ISP_INTERFACE="ppp0"
NFQWS_BASE_ARGS="--lua-init=@/opt/etc/nfqws2/lua/zapret-lib.lua"
NFQWS_ARGS="--filter-tcp=443 --lua-desync=syndata"
NFQWS_ARGS_CUSTOM=""
NFQWS_ARGS_QUIC=""
NFQWS_ARGS_UDP=""
NFQWS_EXTRA_ARGS=""
NFQWS_ARGS_IPSET=""
IPV6_ENABLED=0
TCP_PORTS=443
UDP_PORTS=443
POLICY_NAME="guest-policy"
POLICY_EXCLUDE=1
NFQUEUE_NUM=311
USER=nobody
LOG_LEVEL=0
LOG_DEBUG_PATH="@/opt/var/log/nfqws2-debug.log"
CONFIG_VERSION=1
CONF
original=$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')
make_strategy() {
    name=$1
    blob="flowseal-1.10.4-$name-fake.bin"
    saved="$KEENUTILS_FLOWSEAL_HOME/strategies/flowseal-1.10.4-$name"
    mkdir -p "$saved/blobs" "$saved/lists"
    printf '1234' > "$saved/blobs/$blob"
    printf '{"name":"%s","version":"1.10.4","warnings":0}\n' "$name" > "$saved/info.json"
    cat > "$saved/nfqws2.conf" <<EOF
ISP_INTERFACE="eth3"
NFQWS_BASE_ARGS="--lua-init=@/opt/etc/nfqws2/lua/zapret-lib.lua --blob=fake:@/opt/etc/nfqws2/blobs/$blob"
NFQWS_ARGS="--filter-tcp=443 --payload=tls_client_hello --lua-desync=fake:blob=fake"
NFQWS_ARGS_CUSTOM=""
NFQWS_ARGS_QUIC=""
NFQWS_ARGS_UDP=""
NFQWS_EXTRA_ARGS=""
NFQWS_ARGS_IPSET=""
IPV6_ENABLED=1
TCP_PORTS=443
UDP_PORTS=443
POLICY_NAME="nfqws"
POLICY_EXCLUDE=0
NFQUEUE_NUM=300
USER=nobody
LOG_LEVEL=0
LOG_DEBUG_PATH="@/opt/var/log/nfqws2-debug.log"
CONFIG_VERSION=1
EOF
}
make_strategy alt12
a="$saved"
make_strategy alt13
b="$saved"
# Refuse missing files, no mutation.
rm "$a/blobs/flowseal-1.10.4-alt12-fake.bin"
if sh "$deployer" check "$a" > "$work/missing.log" 2>&1; then
    echo 'Missing resource was accepted' >&2;exit 1
fi
test "$original" = "$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')"
printf '1234' > "$a/blobs/flowseal-1.10.4-alt12-fake.bin"
sh "$deployer" check "$a" > "$work/check.log"
grep -Fq 'Подготовлен для копирования' "$work/check.log"
sh "$deployer" preview "$a" > "$work/preview.log"
grep -Fq 'guest-policy' "$work/preview.log"
test ! -e "$work/opt/running"
sh "$deployer" apply "$a" > "$work/apply-a.log"
test -f "$work/opt/running"
test -f "$base/blobs/flowseal-1.10.4-alt12-fake.bin"
grep -Fq 'ISP_INTERFACE="ppp0"' "$base/nfqws2.conf"
grep -Fq 'POLICY_NAME="guest-policy"' "$base/nfqws2.conf"
grep -Fq 'NFQUEUE_NUM=311' "$base/nfqws2.conf"
first=$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')
sh "$deployer" status > "$work/status.log"
grep -Fq 'flowseal-1.10.4-alt12' "$work/status.log"
# Switch between strategies, then return to the previous one.
sh "$deployer" apply "$b" > "$work/apply-b.log"
test -f "$base/blobs/flowseal-1.10.4-alt13-fake.bin"
grep -Fq 'flowseal-1.10.4-alt13' "$KEENUTILS_FLOWSEAL_HOME/deployments/active"
sh "$deployer" undo > "$work/undo.log"
test "$first" = "$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')"
test ! -e "$base/blobs/flowseal-1.10.4-alt13-fake.bin"
test -e "$base/blobs/flowseal-1.10.4-alt12-fake.bin"
test -f "$work/opt/running"
# Failed service restart must restore previous config and remove new blob.
printf '%s\n' 'NFQWS_ARGS="FORCE_FAIL"' >> "$b/nfqws2.conf"
if sh "$deployer" apply "$b" > "$work/failure.log" 2>&1; then
    echo 'Failed daemon restart was accepted' >&2;exit 1
fi
grep -Fq 'восстанавливается прежняя конфигурация' "$work/failure.log"
test "$first" = "$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')"
test ! -e "$base/blobs/flowseal-1.10.4-alt13-fake.bin"
test -f "$work/opt/running"
# Existing resources with different bytes must be blocked, never overwritten.
printf 'DIFFERENT' > "$base/blobs/flowseal-1.10.4-alt13-fake.bin"
if sh "$deployer" apply "$b" > "$work/conflict.log" 2>&1; then
    echo 'Resource overwrite was allowed' >&2;exit 1
fi
test "$(cat "$base/blobs/flowseal-1.10.4-alt13-fake.bin")" = DIFFERENT
test "$first" = "$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')"
sh "$deployer" history > "$work/history.log"
grep -Fq 'Резервные копии' "$work/history.log"
printf 'Transactional deployment, safe switching, rollback and failure recovery: OK\n'
