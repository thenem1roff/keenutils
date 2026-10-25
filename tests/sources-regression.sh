#!/bin/sh
# Source allowlist, cached fallback and delegated upstream menu smoke tests.
set -eu
awk '
    /^source_url_allowed\(\) \{/ {inside=1}
    /^repo_add\(\) \{/ {inside=0}
    inside {print}
' install >/tmp/keenutils-sources-functions.sh
# shellcheck disable=SC1091
. /tmp/keenutils-sources-functions.sh
say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
ensure_mktemp() { :; }
BASE_URL=https://raw.githubusercontent.com/thenem1roff/keenutils/main
SOURCES_CACHE=/opt/etc/keenutils/sources.conf
SOURCES_READY=0
mkdir -p /opt/etc/keenutils
sources_validate ./sources.conf
cp ./sources.conf /tmp/keenutils-valid-sources
# A host outside the official repo must not be accepted.
sed 's|https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh|https://evil.example/installer.sh|' \
    ./sources.conf >/tmp/keenutils-bad-sources
if sources_validate /tmp/keenutils-bad-sources; then exit 1; fi
# Duplicate and missing keys are rejected.
cat ./sources.conf ./sources.conf > /tmp/keenutils-duplicate-sources
if sources_validate /tmp/keenutils-duplicate-sources; then exit 1; fi
# Rejected downloads cannot poison a valid on-disk snapshot.
cp ./sources.conf "$SOURCES_CACHE"
wget() { cp /tmp/keenutils-bad-sources "$3"; }
curl() { return 1; }
sources_refresh
cmp -s ./sources.conf "$SOURCES_CACHE"
source_get nfqws_menu
[ "$SOURCE_URL" = "https://raw.githubusercontent.com/rndnaame/nfqws-menu/main/nfqws-menu.sh" ]
# GitHub unavailable: use last valid cache without modifying it.
SOURCES_READY=0
wget() { return 1; }
sources_refresh
source_get keenkit
[ -n "$SOURCE_URL" ]
# If no good local catalog and the network fails, refuse the operation.
SOURCES_READY=0
printf 'invalid\n' > "$SOURCES_CACHE"
if sources_refresh; then
    echo 'accepted invalid offline sources' >&2
    exit 1
fi
# Entrypoint 4 runs an installed original upstream menu, without downloading it.
printf '#!/bin/sh\nprintf "UPSTREAM NFQWS MENU OPENED\n"\n' |
    tee /opt/nfqws-menu.sh >/dev/null
chmod 755 /opt/nfqws-menu.sh
printf '4\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-nfqws-menu.log
grep -q 'UPSTREAM NFQWS MENU OPENED' /tmp/keenutils-nfqws-menu.log
grep -q '  4. nfqws-menu' /tmp/keenutils-nfqws-menu.log
grep -q '  8. TorrServer' /tmp/keenutils-nfqws-menu.log
# First run: fetch catalog + install only the original menu from its repository.
rm -f /opt/nfqws-menu.sh "$SOURCES_CACHE"
cp ./sources.conf /tmp/keenutils-ci-sources
cat >/opt/bin/wget <<'MOCK_DOWNLOAD'
#!/bin/sh
[ "$1" = '-q' ] && [ "$2" = '-O' ] || exit 1
case "$4" in
    */sources.conf) cp /tmp/keenutils-ci-sources "$3" ;;
    */nfqws-menu.sh)
        printf '#!/bin/sh\nprintf "UPSTREAM FIRST INSTALL OK\n"\n' > "$3" ;;
    *) exit 1 ;;
esac
MOCK_DOWNLOAD
chmod 755 /opt/bin/wget
printf '4\n\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-first-menu.log
grep -q 'UPSTREAM FIRST INSTALL OK' /tmp/keenutils-first-menu.log
[ -s /opt/nfqws-menu.sh ]
sources_validate "$SOURCES_CACHE"
echo 'Source catalog and delegated nfqws-menu tests passed.'
