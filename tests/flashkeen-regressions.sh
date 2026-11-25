#!/bin/sh
# Isolated filesystem and mocked installers: never operate on real Entware.
set -eu
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT HUP INT TERM
mkdir -p "$root/opt/bin"
awk '/^[a-zA-Z_][a-zA-Z_0-9]*\(\) \{[[:space:]]*$/ {copy=1}
     copy {print}
     /^\}$/ {copy=0}' install |
    sed -e 's|/opt/bin/Flashkeen|/opt/bin/Flashkeen-command|g' -e "s|/opt/|$root/opt/|g" >"$root/functions.sh"
. "$root/functions.sh"
# The test-only alias rename avoids Windows' case-insensitive filenames.
say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }
pkg_installed() { return 1; }
u_torr_cache_path() { return 1; }
fetch_and_run() {
    [ "$1" = flashkeen ] && [ "$2" = Flashkeen ]
    printf '%s\n' installer >>"$root/calls"
    [ "${cancel:-0}" -eq 0 ] || return 2
    [ "${fail:-0}" -eq 0 ] || return 1
    cat >"$root/opt/bin/flashkeen" <<'APP'
#!/bin/sh
printf 'FLASHKEEN MENU umask=%s\n' "$(umask)"
exit 0
APP
    chmod 755 "$root/opt/bin/flashkeen"
}
umask 077
install_flashkeen >"$root/first.log"
grep -q 'FLASHKEEN MENU umask=0022' "$root/first.log"
[ "$(umask)" = 0077 ]
[ "$(wc -l <"$root/calls" | tr -d ' ')" -eq 1 ]
install_flashkeen >"$root/second.log"
grep -q 'FLASHKEEN MENU' "$root/second.log"
[ "$(wc -l <"$root/calls" | tr -d ' ')" -eq 1 ]
# Batch skips menu both on existing installation and first installation.
install_flashkeen install_only >"$root/batch-present.log"
grep -Fq 'Автозапуск меню пропущен' "$root/batch-present.log"
! grep -Fq 'FLASHKEEN MENU' "$root/batch-present.log"
[ "$(wc -l <"$root/calls" | tr -d ' ')" -eq 1 ]
rm -f "$root/opt/bin/flashkeen"
install_flashkeen install_only >"$root/batch-first.log"
grep -Fq 'Автозапуск меню пропущен' "$root/batch-first.log"
! grep -Fq 'FLASHKEEN MENU' "$root/batch-first.log"
[ "$(wc -l <"$root/calls" | tr -d ' ')" -eq 2 ]
u_detect flashkeen
[ "$U_INSTALLED" -eq 1 ]

# Foreign short commands survive; owned wrappers and dangling links are removed.
printf '#!/bin/sh\n%s/opt/bin/flashkeen "$@"\nexit $?\n' "$root" >"$root/opt/bin/flash"
ln -s "$root/opt/bin/flashkeen" "$root/opt/bin/Flashkeen-command"
printf '#!/bin/sh\necho unrelated\n' >"$root/opt/bin/f"
printf '#!/bin/sh\necho unrelated-update\n' >"$root/opt/bin/update"
ask_yes() { return 1; }
u_remove flashkeen
[ -f "$root/opt/bin/flashkeen" ]
ask_yes() { return 0; }
u_remove flashkeen
[ ! -e "$root/opt/bin/flashkeen" ]
[ ! -e "$root/opt/bin/flash" ]
[ ! -L "$root/opt/bin/Flashkeen-command" ]
grep -q unrelated "$root/opt/bin/f"
grep -q unrelated-update "$root/opt/bin/update"
ln -s "$root/opt/bin/flashkeen" "$root/opt/bin/Flashkeen-command"
u_detect flashkeen
[ "$U_INSTALLED" -eq 0 ] && [ "$U_LEFT" -eq 1 ]
u_remove_flashkeen
[ ! -L "$root/opt/bin/Flashkeen-command" ]

cancel=1
install_flashkeen
[ ! -e "$root/opt/bin/flashkeen" ]
cancel=0 fail=1
if install_flashkeen; then echo 'Failed installer accepted' >&2; exit 1; fi
fail=0
printf 'if then\n' >"$root/opt/bin/flashkeen"
chmod 755 "$root/opt/bin/flashkeen"
before=$(wc -l <"$root/calls")
if install_flashkeen; then echo 'Corrupt program accepted' >&2; exit 1; fi
[ "$before" = "$(wc -l <"$root/calls")" ]
grep -q 'if then' "$root/opt/bin/flashkeen"
source_url_allowed flashkeen https://raw.githubusercontent.com/miha75vu-bit/Flashkeen/main/install.sh
source_url_allowed flashkeen https://cdn.jsdelivr.net/gh/miha75vu-bit/Flashkeen@main/install.sh
if source_url_allowed flashkeen https://raw.githubusercontent.com/other/Flashkeen/main/install.sh; then exit 1; fi
sources_validate sources.conf
echo 'Flashkeen: install, launch, return, cancellation, failure, detection and scoped removal OK.'
