обновление torrserver
```bash
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/torrserver | sh
```
torrserver watchdog
```bash
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/torr_watchdog | sh
```
стратегия general11 1.10.3 от flowseal (nfqws)
```bash
curl -fsSL https://raw.githubusercontent.com/thenem1roff/keenutils/main/nfqws | sh
```
```bash
opkg update && opkg install ca-certificates wget-ssl jq
opkg remove wget-nossl 2>/dev/null
mkdir -p /opt/etc/opkg
echo "src/gz nfqws2-keenetic https://nfqws.github.io/nfqws2-keenetic/all" > /opt/etc/opkg/nfqws2-keenetic.conf
echo "src/gz nfqws-keenetic-web https://nfqws.github.io/nfqws-keenetic-web/all" > /opt/etc/opkg/nfqws-keenetic-web.conf
opkg update && opkg install nfqws2-keenetic nfqws-keenetic-web
```
