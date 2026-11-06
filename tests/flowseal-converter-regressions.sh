#!/bin/sh
# Offline POSIX Shell / AWK regression tests; no Python, router, or network.
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$tmp/source/lists" "$tmp/source/bin" "$tmp/output" "$tmp/output-games" "$tmp/home"
printf 'discord.com\n' > "$tmp/source/lists/list-google.txt"
printf 'google.com\n' > "$tmp/source/lists/list-general.txt"
printf '\001\002\003' > "$tmp/source/bin/tls.bin"
cat > "$tmp/source/general (ALT13).bat" <<'BAT'
@echo off
set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
start "zapret" "%BIN%winws.exe" --wf-tcp=80,443,%GameFilterTCP% --wf-udp=443,%GameFilterUDP% ^
--filter-udp=443 --hostlist="%LISTS%list-general.txt" --dpi-desync=fake --dpi-desync-fake-quic="0x0102" --dpi-desync-repeats=11 --new ^
--filter-tcp=443 --hostlist="%LISTS%list-google.txt" --ip-id=zero --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=www.google.com --new ^
--filter-tcp=80,443 --dpi-desync=fake,hostfakesplit --dpi-desync-fooling=ts --dpi-desync-hostfakesplit-mod=host=mail.ru,altorder=1 --dpi-desync-fake-tls="%BIN%tls.bin" --dpi-desync-repeats=5 --new ^
--filter-tcp=%GameFilterTCP% --dpi-desync=multisplit --dpi-desync-split-pos=1 --dpi-desync-split-seqovl=5
BAT
lua_hex=$(od -An -tx1 -v modules/flowseal/hostfakesplit_alt1.lua | tr -d ' \n')
test -n "$lua_hex"
FLOWSEAL_OUTPUT="$tmp/output" FLOWSEAL_GAMES=no FLOWSEAL_INTERFACE=eth3 \
    FLOWSEAL_ALT_LUA_HEX="$lua_hex" \
    awk -f modules/flowseal/converter.awk "$tmp/source/general (ALT13).bat"
conf="$tmp/output/nfqws2.conf"
test -s "$conf"
sh -n "$conf"
grep -Fq -- '--blob=tls:' "$conf"
grep -Fq -- '--lua-desync=fake:blob=tls:tcp_ts=-600000:repeats=5' "$conf"
grep -Fq -- '--lua-desync=zk_hostfakesplit_alt1:host=mail.ru:tcp_ts=-600000:repeats=5' "$conf"
grep -Fq -- '--hostlist=/opt/etc/nfqws2/lists/user.list' "$conf"
grep -Fq -- '--hostlist=/opt/etc/nfqws2/lists/flowseal-list-google.list' "$conf"
grep -Fq -- '--lua-init=assert(load' "$conf"
grep -Fq -- 'PROFILES_READ=4' "$tmp/output/stats.txt"
grep -Fq -- 'PROFILES_WRITTEN=3' "$tmp/output/stats.txt"
grep -Fq -- 'ALTORDER=1' "$tmp/output/stats.txt"
! grep -Fq -- '--filter-tcp=12' "$conf"
# Game option yes should keep game profile.
FLOWSEAL_OUTPUT="$tmp/output-games" FLOWSEAL_GAMES=yes FLOWSEAL_INTERFACE=eth3 \
    FLOWSEAL_ALT_LUA_HEX="$lua_hex" \
    awk -f modules/flowseal/converter.awk "$tmp/source/general (ALT13).bat"
grep -Fq -- 'PROFILES_WRITTEN=4' "$tmp/output-games/stats.txt"
grep -Fq -- '1024:65535' "$tmp/output-games/nfqws2.conf"
sh -n "$tmp/output-games/nfqws2.conf"
# Unsupported hostfakesplit modifiers must produce failure, never silently pass.
printf 'winws.exe --filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=unsafe=1\n' > "$tmp/unsafe.bat"
mkdir "$tmp/unsafe-output"
if FLOWSEAL_OUTPUT="$tmp/unsafe-output" FLOWSEAL_GAMES=no FLOWSEAL_INTERFACE=eth3 \
    FLOWSEAL_ALT_LUA_HEX="$lua_hex" awk -f modules/flowseal/converter.awk "$tmp/unsafe.bat" 2>/dev/null; then
    echo "Unsupported host modifier was accepted" >&2; exit 1
fi
# Enter returns from the standalone menu without invoking a router service.
printf '\n' | KEENUTILS_FLOWSEAL_HOME="$tmp/home" sh modules/flowseal/menu.sh > "$tmp/menu.log"
grep -Fq 'Назад в KeenUtils' "$tmp/menu.log"
printf 'Shell/AWK conversion, game toggle, Lua and menu regression tests: OK\n'
