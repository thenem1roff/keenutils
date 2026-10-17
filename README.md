обновление torrserver
```bash
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/torrserver | sh
```
torrserver watchdog
```bash
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/torr_watchdog | sh
```
быстрая установка nfqws
```bash
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/nfqws | sh
```
```bash
opkg update && opkg install ca-certificates wget-ssl jq
opkg remove wget-nossl 2>/dev/null
mkdir -p /opt/etc/opkg
echo "src/gz nfqws-keenetic https://nfqws.github.io/nfqws-keenetic/all" > /opt/etc/opkg/nfqws-keenetic.conf
echo "src/gz nfqws-keenetic-web https://nfqws.github.io/nfqws-keenetic-web/all" > /opt/etc/opkg/nfqws-keenetic-web.conf
opkg update && opkg install nfqws-keenetic nfqws-keenetic-web
```
