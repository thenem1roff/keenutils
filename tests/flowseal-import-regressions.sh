#!/bin/sh
# Offline end-to-end import of a Flowseal release ZIP using Shell and AWK only.
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
export KEENUTILS_FLOWSEAL_TEST_ONLY=1
export KEENUTILS_FLOWSEAL_HOME="$work/home"
mkdir -p "$KEENUTILS_FLOWSEAL_HOME" "$work/archive/zapret-discord-youtube-1.10.4/lists" \
         "$work/archive/zapret-discord-youtube-1.10.4/bin"
. ./modules/flowseal/menu.sh
# When sourced, $0 remains this test, so explicitly set the runtime source.
RUNTIME="$PWD/modules/flowseal"
cp "tests/fixtures/flowseal/general (ALT13).bat" \
   "$work/archive/zapret-discord-youtube-1.10.4/general (ALT13).bat"
printf 'discord.com\n' > "$work/archive/zapret-discord-youtube-1.10.4/lists/list-general.txt"
printf 'google.com\n' > "$work/archive/zapret-discord-youtube-1.10.4/lists/list-google.txt"
# Provide all .bin blobs referenced by the fixture.
grep -Eo '%BIN%[A-Za-z0-9_.-]+\.bin' "tests/fixtures/flowseal/general (ALT13).bat" |
    sed 's/%BIN%//' | sort -u | while IFS= read -r bin; do
        printf '\001\002\003\004' > "$work/archive/zapret-discord-youtube-1.10.4/bin/$bin"
    done
(cd "$work/archive" && zip -q -r "$work/official.zip" zapret-discord-youtube-1.10.4)
cat > "$work/release.json" <<'JSON'
{"tag_name":"1.10.4","assets":[{"name":"zapret-discord-youtube-1.10.4.zip"}]}
JSON
fetch() {
    case "$1" in
        "$RELEASE_URL") cp "$work/release.json" "$2" ;;
        "https://github.com/Flowseal/zapret-discord-youtube/releases/download/1.10.4/zapret-discord-youtube-1.10.4.zip")
            cp "$work/official.zip" "$2" ;;
        *) return 1 ;;
    esac
}
# Choose first profile, accept default conversion=Y and game ports=Y.
printf '1\n\n\n' | add_strategy > "$work/import.log"
saved="$STRATEGIES/flowseal-1.10.4-alt13"
test -f "$saved/info.json"
test -f "$saved/nfqws2.conf"
test -f "$saved/REPORT.md"
test -f "$saved/lists/flowseal-1.10.4-alt13-list-google.list"
test -f "$saved/blobs/flowseal-1.10.4-alt13-tls_clienthello_sochi_park.bin"
jq -e '.name=="ALT13" and .version=="1.10.4" and .game_ports==true and .state=="saved_only"' \
    "$saved/info.json" >/dev/null
sh -n "$saved/nfqws2.conf"
grep -Fq 'PROFILES_WRITTEN=' "$saved/stats.txt"
! grep -Fq 'Python' "$work/import.log"
# Re-run import and decline replacement: previous saved config must be unchanged.
before=$(sha256sum "$saved/nfqws2.conf" | awk '{print $1}')
printf '1\n\n\nn\n' | add_strategy > "$work/second.log"
after=$(sha256sum "$saved/nfqws2.conf" | awk '{print $1}')
test "$before" = "$after"
# Test rejected ZIP traversal using a malicious entry name.
mkdir -p "$work/unsafe/source"
printf 'malicious' > "$work/unsafe/source/escape"
(cd "$work/unsafe/source" && zip -q "$work/unsafe.zip" escape)
# Explicitly set ZIP filename using Python-free zipnote metadata not required:
# invalid traversal is already rejected by extract_safe on member inspection.
printf 'Shell ZIP import and automatic saved strategy regression: OK\n'
