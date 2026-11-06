#!/bin/sh
# Test first-time module bootstrap, cached launch and offline fallback.
# Executed in its own GitHub Actions Ubuntu job as root; no Python required.
set -eu
ROOT=$PWD
mkdir -p /opt/bin /opt/etc/keenutils
cat > /opt/bin/wget <<EOF
#!/bin/sh
[ "\$1" = -q ] && [ "\$2" = -O ] || exit 1
printf '%s\n' "\$4" >> /tmp/flowseal-bootstrap-fetch.log
case "\$4" in
    https://raw.githubusercontent.com/thenem1roff/keenutils/feature/flowseal-converter-77/*)
        rel=\${4#https://raw.githubusercontent.com/thenem1roff/keenutils/feature/flowseal-converter-77/}
        [ -f "$ROOT/\$rel" ] || exit 1
        cp "$ROOT/\$rel" "\$3"
        ;;
    *) exit 1 ;;
esac
EOF
# For testing offline fallback, curl must not access a real network.
cat > /opt/bin/curl <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 755 /opt/bin/wget /opt/bin/curl
: > /tmp/flowseal-bootstrap-fetch.log
printf '0\n' |
    KEENUTILS_FLOWSEAL_REF=feature/flowseal-converter-77 \
    sh ./flowseal_converter > /tmp/flowseal-bootstrap-first.log
grep -Fq 'Конвертер обновлён:' /tmp/flowseal-bootstrap-first.log
grep -Fq 'Назад в KeenUtils' /tmp/flowseal-bootstrap-first.log
test -f /opt/bin/keenutils-flowseal-dev
installed_version=$(cat /opt/etc/keenutils/flowseal-dev/current.version)
test "$installed_version" = "$(cat flowseal.version)"
test -f "/opt/etc/keenutils/flowseal-dev/runtime/$installed_version/converter.awk"
test ! -e "/opt/etc/keenutils/flowseal-dev/runtime/$installed_version/manager.py"
# No re-download of module files on a repeat launch: only version marker.
: > /tmp/flowseal-bootstrap-fetch.log
printf '0\n' |
    KEENUTILS_FLOWSEAL_REF=feature/flowseal-converter-77 \
    sh /opt/bin/keenutils-flowseal-dev > /tmp/flowseal-bootstrap-repeat.log
test "$(wc -l < /tmp/flowseal-bootstrap-fetch.log)" -eq 1
grep -Fq '/flowseal.version' /tmp/flowseal-bootstrap-fetch.log
grep -Fq 'Назад в KeenUtils' /tmp/flowseal-bootstrap-repeat.log
# No Internet: cached files continue to work without Python.
cat > /opt/bin/wget <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 755 /opt/bin/wget
printf '0\n' |
    KEENUTILS_FLOWSEAL_REF=feature/flowseal-converter-77 \
    sh /opt/bin/keenutils-flowseal-dev > /tmp/flowseal-bootstrap-offline.log
grep -Fq 'GitHub недоступен' /tmp/flowseal-bootstrap-offline.log
grep -Fq 'Назад в KeenUtils' /tmp/flowseal-bootstrap-offline.log
printf 'Flowseal local module install, cached startup, offline fallback: OK\n'
