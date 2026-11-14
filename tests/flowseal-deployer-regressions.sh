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
        if [ -f "$KEENUTILS_FLOWSEAL_TEST_ROOT/init-error-while-running" ]; then
            : > "$state"
            exit 1
        fi
        if [ -f "$KEENUTILS_FLOWSEAL_TEST_ROOT/init-success-while-stopped" ]; then
            rm -f "$state"
            exit 0
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
# Existing nfqws2 lists map to multiple Flowseal source files.
for name in user.list exclude.list ipset_exclude.list; do
    printf 'example.org\n' > "$base/lists/$name"
done
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
NFQWS_BASE_ARGS="--lua-init=@/opt/etc/nfqws2/lua/zapret-lib.lua --lua-init=@/opt/etc/nfqws2/lua/zapret-antidpi.lua --blob=fake:@/opt/etc/nfqws2/blobs/$blob"
# Simulate a previously saved ALT12 (converter <= 0.3.0-rc4) with
# repeated canonical list paths within three profiles.
NFQWS_ARGS="--filter-tcp=443
             --hostlist=/opt/etc/nfqws2/lists/user.list
             --hostlist=/opt/etc/nfqws2/lists/user.list
             --hostlist-exclude=/opt/etc/nfqws2/lists/exclude.list
             --hostlist-exclude=/opt/etc/nfqws2/lists/exclude.list
             --ipset-exclude=/opt/etc/nfqws2/lists/ipset_exclude.list
             --ipset-exclude=/opt/etc/nfqws2/lists/ipset_exclude.list
             --payload=tls_client_hello --lua-desync=fake:blob=fake"
NFQWS_ARGS_CUSTOM="--filter-udp=443
             --hostlist=/opt/etc/nfqws2/lists/user.list
             --hostlist=/opt/etc/nfqws2/lists/user.list
             --new
             --filter-tcp=80
             --hostlist=/opt/etc/nfqws2/lists/user.list
             --hostlist=/opt/etc/nfqws2/lists/user.list"
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
# Some devices are missing both libraries from the official nfqws2 package.
# The read-only check must detect them without modifying system files.
rm -f "$base/lua/zapret-lib.lua" "$base/lua/zapret-antidpi.lua"
if sh "$deployer" check "$a" > "$work/missing-lua.log" 2>&1; then
    echo 'Missing stock Lua was accepted without a recovery source' >&2
    exit 1
fi
grep -Fq 'zapret-lib.lua' "$work/missing-lua.log"
grep -Fq 'zapret-antidpi.lua' "$work/missing-lua.log"
# A failed recovery does not touch the working configuration or copy files.
mkdir -p "$work/no-lua-fixtures"
export KEENUTILS_FLOWSEAL_TEST_LUA_DIR="$work/no-lua-fixtures"
if sh "$deployer" apply "$a" > "$work/lua-failed.log" 2>&1; then
    echo 'Missing recovery source was accepted' >&2; exit 1
fi
test "$original" = "$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')"
test ! -e "$base/lua/zapret-lib.lua"
test ! -e "$base/lua/zapret-antidpi.lua"
# Use local fixtures instead of the network, simulating two official files.
mkdir -p "$work/official-lua"
printf 'NFQWS2_COMPAT_VER_REQUIRED=6\n' > "$work/official-lua/zapret-lib.lua"
printf '%s\n' '-- NFQWS2 ANTIDPI LIBRARY' > "$work/official-lua/zapret-antidpi.lua"
export KEENUTILS_FLOWSEAL_TEST_LUA_DIR="$work/official-lua"
# A nonzero init exit code does not mean the daemon failed to start.
: > "$work/opt/init-error-while-running"
sh "$deployer" apply "$a" > "$work/apply-a.log"
rm -f "$work/opt/init-error-while-running"
# Staged normalization must fix legacy saved ALT12 profiles, never
# globally merge lists across --new boundaries or modify the saved template.
test "$(grep -Fc -- '--hostlist=/opt/etc/nfqws2/lists/user.list' "$a/nfqws2.conf")" -eq 6
test "$(grep -Fc -- '--hostlist=/opt/etc/nfqws2/lists/user.list' "$base/nfqws2.conf")" -eq 3
test "$(grep -Fc -- '--hostlist-exclude=/opt/etc/nfqws2/lists/exclude.list' "$base/nfqws2.conf")" -eq 1
test "$(grep -Fc -- '--ipset-exclude=/opt/etc/nfqws2/lists/ipset_exclude.list' "$base/nfqws2.conf")" -eq 1
grep -Fq 'проверяю состояние службы' "$work/apply-a.log"
test -f "$work/opt/running"
test -f "$base/lua/zapret-lib.lua"
test -f "$base/lua/zapret-antidpi.lua"
test "$(stat -c %a "$base/lua/zapret-lib.lua")" = 644
test "$(stat -c %a "$base/lua/zapret-antidpi.lua")" = 644
test "$(stat -c %a "$base/blobs/flowseal-1.10.4-alt12-fake.bin")" = 644
unset KEENUTILS_FLOWSEAL_TEST_LUA_DIR
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
# Explicit per-file merge: keep stock entries and append only new lines.
mkdir -p "$KEENUTILS_FLOWSEAL_HOME/tmp/.stock-plan.merge/lists"
merge_plan="$KEENUTILS_FLOWSEAL_HOME/tmp/.stock-plan.merge"
printf 'merge\tuser.list\n' > "$merge_plan/plan.tsv"
printf 'example.org\nnew.example\nnew.example\n' > "$merge_plan/lists/user.list"
sh "$deployer" apply "$b" "$merge_plan" > "$work/merge-lists.log"
test "$(grep -Fxc example.org "$base/lists/user.list")" -eq 1
test "$(grep -Fxc new.example "$base/lists/user.list")" -eq 1
test -f "$KEENUTILS_FLOWSEAL_HOME/deployments/backups/$(cat "$KEENUTILS_FLOWSEAL_HOME/deployments/latest")/replaced/_opt_etc_nfqws2_lists_user.list"
sh "$deployer" undo > "$work/undo-merge.log"
test "$(cat "$base/lists/user.list")" = example.org
test "$first" = "$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')"
# Explicit replacement must be reversible as well.
mkdir -p "$KEENUTILS_FLOWSEAL_HOME/tmp/.stock-plan.replace/lists"
replace_plan="$KEENUTILS_FLOWSEAL_HOME/tmp/.stock-plan.replace"
printf 'replace\tuser.list\n' > "$replace_plan/plan.tsv"
printf 'from-flowseal.example\n' > "$replace_plan/lists/user.list"
sh "$deployer" apply "$b" "$replace_plan" > "$work/replace-lists.log"
test "$(cat "$base/lists/user.list")" = from-flowseal.example
sh "$deployer" undo > "$work/undo-replace.log"
test "$(cat "$base/lists/user.list")" = example.org
test "$first" = "$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')"
# Without explicit list actions, stock files must stay untouched.
test "$(cat "$base/lists/exclude.list")" = example.org
test ! -e "$base/blobs/flowseal-1.10.4-alt13-fake.bin"
test -e "$base/blobs/flowseal-1.10.4-alt12-fake.bin"
test -f "$work/opt/running"
# Failed service restart must restore previous config and remove new blob.
printf '%s\n' 'NFQWS_ARGS="FORCE_FAIL"' >> "$b/nfqws2.conf"
if sh "$deployer" apply "$b" "$replace_plan" > "$work/failure.log" 2>&1; then
    echo 'Failed daemon restart was accepted' >&2;exit 1
fi
grep -Fq 'восстанавливается прежняя конфигурация' "$work/failure.log"
test "$(cat "$base/lists/user.list")" = example.org
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
grep -Fq 'Сохранённые резервные копии' "$work/history.log"
# An external manual modification must prevent destructive manual rollback.
cp "$base/nfqws2.conf" "$work/last-known-good.conf"
printf '\n# changed outside KeenUtils\n' >> "$base/nfqws2.conf"
if sh "$deployer" undo > "$work/manual-change.log" 2>&1; then
    echo 'Overwrote externally edited configuration' >&2;exit 1
fi
grep -Fq 'Автоматический откат отменён' "$work/manual-change.log"
grep -Fq '# changed outside KeenUtils' "$base/nfqws2.conf"
cp "$work/last-known-good.conf" "$base/nfqws2.conf"
# Multi-level rollback: ALT13 -> ALT12 -> pre-existing nfqws2 (originally stopped).
sh "$deployer" undo > "$work/undo-original.log"
test "$original" = "$(sha256sum "$base/nfqws2.conf" | awk '{print $1}')"
test ! -e "$base/blobs/flowseal-1.10.4-alt12-fake.bin"
# Recovered official package files are not specific to the strategy; undo
# must not remove them if the previous nfqws2 config still needs them.
test -f "$base/lua/zapret-lib.lua"
test -f "$base/lua/zapret-antidpi.lua"
test ! -e "$work/opt/running"
# A zero init exit code without a running daemon must not count as rollback.
sh "$deployer" apply "$a" > "$work/reapply-a.log"
sh "$deployer" apply "$a" > "$work/reapply-a-again.log"
latest=$(cat "$KEENUTILS_FLOWSEAL_HOME/deployments/latest")
: > "$work/opt/init-success-while-stopped"
if sh "$deployer" undo > "$work/undo-dead-daemon.log" 2>&1; then
    echo 'Rollback accepted an init-script success without running service' >&2
    exit 1
fi
grep -Fq 'После восстановления служба nfqws2 не запущена' "$work/undo-dead-daemon.log"
test ! -e "$KEENUTILS_FLOWSEAL_HOME/deployments/backups/$latest/restored"
printf 'Transactional deployment, safe switching, multi-level rollback and failure recovery: OK\n'
