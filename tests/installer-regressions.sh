#!/bin/sh
# Simulated Entware checks: user-installed status, confirmations, application list.
set -eu

cat > /tmp/keenutils-test-opkg <<'MOCK_OPKG'
#!/bin/sh
packages='ca-certificates curl wget-ssl nfqws2-keenetic torrserver libc libopenssl grep'
case "$1" in
    list-installed)
        for pkg in $packages; do
            if [ "$#" -eq 1 ] || [ "$2" = "$pkg" ]; then
                printf '%s - 20250419-2\n' "$pkg"
            fi
        done
        ;;
    status)
        for pkg in $packages; do
            if [ "$2" = "$pkg" ]; then
                printf 'Package: %s\nStatus: install user installed\n' "$pkg"
                exit 0
            fi
        done
        ;;
    install|update)
        printf 'Unexpected opkg write: %s\n' "$*" >&2
        exit 93
        ;;
    *) exit 1 ;;
esac
MOCK_OPKG
sudo cp /tmp/keenutils-test-opkg /opt/bin/opkg
sudo chmod 755 /opt/bin/opkg

# User-installed nfqws2 must be detected instead of prompting to install it.
printf '2\n\n1\n\n00\n' |
    script -q -c 'sudo /opt/bin/keenutils' /dev/null > /tmp/keenutils-pkg-detection.log
grep -Fq 'nfqws2 уже установлен.' /tmp/keenutils-pkg-detection.log
grep -Fq 'Установлен nfqws2.' /tmp/keenutils-pkg-detection.log
! grep -Fq 'Примечание: nfqws' /tmp/keenutils-pkg-detection.log
! grep -Fq 'Продолжить установку nfqws?' /tmp/keenutils-pkg-detection.log

# WireGuard prompt defaults to YES and downloader prompt speaks only English Y/n.
printf '6\n\nn\n\n00\n' |
    script -q -c 'sudo /opt/bin/keenutils' /dev/null > /tmp/keenutils-confirm.log
grep -Fq 'Компонент WireGuard установлен? [Y/n]' /tmp/keenutils-confirm.log
grep -Fq 'Запустить официальный внешний установщик AWG-Manager? [Y/n]' /tmp/keenutils-confirm.log
grep -Fq 'ca-certificates: уже установлен.' /tmp/keenutils-confirm.log
! grep -Fq 'ca-certificates отсутствует после установки' /tmp/keenutils-confirm.log

# Detect nfqws2 before warning in nfqws-web branch; prevent source modification.
sudo mkdir -p /opt/etc/opkg
printf 'nonmatching existing config\n' | sudo tee /opt/etc/opkg/nfqws-keenetic-web.conf >/dev/null
printf '3\n\n00\n' |
    script -q -c 'sudo /opt/bin/keenutils' /dev/null > /tmp/keenutils-web-check.log
! grep -Fq 'Внимание: сначала рекомендуется установить nfqws' /tmp/keenutils-web-check.log

# 99 excludes libc, libopenssl, ca-certificates, grep and other support packages.
printf '99\n\n00\n' |
    script -q -c 'sudo /opt/bin/keenutils' /dev/null > /tmp/keenutils-app-list.log
grep -Fq '  nfqws2-keenetic' /tmp/keenutils-app-list.log
grep -Fq '  torrserver' /tmp/keenutils-app-list.log
! grep -Eq '^  (libc|libopenssl|ca-certificates|grep)( |$)' /tmp/keenutils-app-list.log

printf 'Entware user-status and menu regression tests passed.\n'
