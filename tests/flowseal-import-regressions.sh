#!/bin/sh
# Offline release-tag import: no ZIP, no unzip, no Python, no router writes.
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
export KEENUTILS_FLOWSEAL_TEST_ONLY=1
export KEENUTILS_FLOWSEAL_HOME="$work/home"
mkdir -p "$KEENUTILS_FLOWSEAL_HOME" "$work/upstream/lists" "$work/upstream/bin"
. ./modules/flowseal/menu.sh
RUNTIME="$PWD/modules/flowseal"

cp "tests/fixtures/flowseal/general (ALT13).bat" \
   "$work/upstream/general (ALT13).bat"
cp "tests/fixtures/flowseal/general (ALT12).bat" \
   "$work/upstream/general (ALT12).bat"
grep -Eo '%LISTS%[A-Za-z0-9_.-]+\.txt' \
    "tests/fixtures/flowseal/general (ALT13).bat" |
    sed 's/%LISTS%//' | sort -u | while IFS= read -r name; do
        printf 'example.org\n' > "$work/upstream/lists/$name"
    done
grep -Eo '%BIN%[A-Za-z0-9_.-]+\.bin' \
    "tests/fixtures/flowseal/general (ALT13).bat" |
    sed 's/%BIN%//' | sort -u | while IFS= read -r name; do
        printf '\001\002\003\004' > "$work/upstream/bin/$name"
    done
printf 'must not download' > "$work/upstream/bin/winws.exe"
find "$work/upstream" -type f |
    sed "s#^$work/upstream/##" |
    jq -R -s --arg sha '176f56dc3f11ce5915c26abcdde903f93d835b64' \
      '{sha:$sha,truncated:false,tree:(split("\n")|map(select(length>0)|{path:.,type:"blob"}))}' \
      > "$work/tree.json"
cat > "$work/release.json" <<'JSON'
{"tag_name":"1.10.4"}
JSON
: > "$work/requests.log"
fetch() {
    printf '%s\n' "$1" >> "$work/requests.log"
    case "$1" in
        "$RELEASE_URL") cp "$work/release.json" "$2" ;;
        "https://api.github.com/repos/Flowseal/zapret-discord-youtube/git/trees/1.10.4?recursive=1")
            cp "$work/tree.json" "$2" ;;
        https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/1.10.4/*)
            requested=${1#https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/1.10.4/}
            requested=$(printf '%s' "$requested" | sed 's/%20/ /g;s/%28/(/g;s/%29/)/g')
            [ -f "$work/upstream/$requested" ] || return 1
            cp "$work/upstream/$requested" "$2" ;;
        *) echo "Unexpected download URL: $1" >&2; return 1 ;;
    esac
}
printf '2\n\n\n' | add_strategy > "$work/import.log"
saved="$STRATEGIES/flowseal-1.10.4-alt13"
test -f "$saved/info.json"
test -f "$saved/nfqws2.conf"
test -f "$saved/REPORT.md"
test -f "$saved/lists/flowseal-1.10.4-alt13-list-google.list"
test -f "$saved/blobs/flowseal-1.10.4-alt13-tls_clienthello_sochi_park.bin"
jq -e '.name=="ALT13" and .version=="1.10.4" and .game_ports==true
        and .state=="saved_only" and .release_tree_sha=="176f56dc3f11ce5915c26abcdde903f93d835b64"' \
    "$saved/info.json" >/dev/null
sh -n "$saved/nfqws2.conf"
validation=0
sh "$RUNTIME/validator.sh" "$saved" > "$work/validation.log" || validation=$?
[ "$validation" -eq 2 ]
grep -Fq 'Требует переноса:' "$work/validation.log"
grep -Fq 'Применение пока отключено' "$work/validation.log"
grep -Fq 'PROFILES_WRITTEN=' "$saved/stats.txt"
! grep -Fq 'Python' "$work/import.log"
! grep -Eq '(releases/download|\.zip|unzip|winws\.exe)' "$work/requests.log"
grep -Fq 'general%20%28ALT13%29.bat' "$work/requests.log"
before=$(sha256sum "$saved/nfqws2.conf" | awk '{print $1}')
printf '2\n\n\nn\n' | add_strategy > "$work/second.log"
after=$(sha256sum "$saved/nfqws2.conf" | awk '{print $1}')
[ "$before" = "$after" ]
printf 'Tagged Flowseal tree and selective raw import: OK\n'
