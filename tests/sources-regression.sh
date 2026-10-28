#!/bin/sh
# Source allowlist, cached fallback and delegated upstream menu smoke tests.
set -eux
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
# Entrypoint 4 runs the installed upstream menu without downloading it.
# The delegated process must create hostlists/blobs readable by nfqws
# (runs as nobody), even though KeenUtils itself uses umask 077.
cat >/opt/nfqws-menu.sh <<'MOCK_MENU'
#!/bin/sh
printf 'UPSTREAM NFQWS MENU OPENED\n'
printf 'example.org\n' >/opt/etc/keenutils-test-nfqws.list
printf 'fake blob\n' >/opt/etc/keenutils-test-nfqws.bin
selection=''
IFS= read -r selection || :
printf 'UPSTREAM EXIT=%s\n' "$selection"
exit 0
MOCK_MENU
chmod 755 /opt/nfqws-menu.sh
# 00 in nfqws-menu, Enter at KeenUtils pause, then 00 exits KeenUtils.
printf '4\n00\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-nfqws-menu.log
grep -Fq 'UPSTREAM NFQWS MENU OPENED' /tmp/keenutils-nfqws-menu.log
grep -Fq 'UPSTREAM EXIT=00' /tmp/keenutils-nfqws-menu.log
grep -Fq '  4. nfqws-menu' /tmp/keenutils-nfqws-menu.log
grep -Fq '  8. TorrServer' /tmp/keenutils-nfqws-menu.log
grep -Fq 'Выход.' /tmp/keenutils-nfqws-menu.log
[ "$(stat -c %a /opt/etc/keenutils-test-nfqws.list)" = 644 ]
[ "$(stat -c %a /opt/etc/keenutils-test-nfqws.bin)" = 644 ]
# Enter in upstream menu also returns to KeenUtils (without exiting it).
printf '4\n\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-nfqws-menu-enter.log
grep -Fq 'UPSTREAM EXIT=' /tmp/keenutils-nfqws-menu-enter.log
grep -Fq 'Выход.' /tmp/keenutils-nfqws-menu-enter.log
# The parent's mask remains strict after the delegated call finishes.
awk '/^launch_nfqws_menu\(\) \{/ {copy=1}
     /^install_keenkit\(\) \{/ {copy=0}
     copy {print}' install >/tmp/keenutils-launch-nfqws-test.sh
. /tmp/keenutils-launch-nfqws-test.sh
umask 077
launch_nfqws_menu </dev/null >/tmp/keenutils-nfqws-direct.log
[ "$(umask)" = 0077 ]
rm -f /opt/etc/keenutils-test-nfqws.list /opt/etc/keenutils-test-nfqws.bin
# First run: fetch catalog + install only the original menu from its repository.
rm -f /opt/nfqws-menu.sh "$SOURCES_CACHE"
cp ./sources.conf /tmp/keenutils-ci-sources
cat >/opt/bin/wget <<'MOCK_DOWNLOAD'
#!/bin/sh
[ "$1" = '-q' ] && [ "$2" = '-O' ] || exit 1
case "$4" in
    */sources.conf) cp /tmp/keenutils-ci-sources "$3" ;;
    */nfqws-menu.sh)
        cat >"$3" <<'FIRST_INSTALL_MENU'
#!/bin/sh
printf 'UPSTREAM FIRST INSTALL OK\n'
printf 'example.org\n' >/opt/etc/keenutils-first-install.list
FIRST_INSTALL_MENU
        ;;
    *) exit 1 ;;
esac
MOCK_DOWNLOAD
chmod 755 /opt/bin/wget
printf '4\n\n\n00\n' |
    script -q -c 'sh ./install' /dev/null >/tmp/keenutils-first-menu.log
grep -q 'UPSTREAM FIRST INSTALL OK' /tmp/keenutils-first-menu.log
grep -Fq 'Выход.' /tmp/keenutils-first-menu.log
[ -s /opt/nfqws-menu.sh ]
[ "$(stat -c %a /opt/etc/keenutils-first-install.list)" = 644 ]
rm -f /opt/etc/keenutils-first-install.list
sources_validate "$SOURCES_CACHE"
echo 'Source catalog, nfqws-menu permissions and return-navigation tests passed.'
