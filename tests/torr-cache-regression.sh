#!/bin/sh
# Mock device mount and TorrServer HTTP API without modifying a real router.
set -eu

awk '
    /^filesystem_id\(\) \{/ {include=1}
    /^watchdog_complete\(\) \{/ {include=0}
    include {print}
' install > /tmp/keenutils-cache-functions.sh
. /tmp/keenutils-cache-functions.sh

have() { command -v "$1" >/dev/null 2>&1; }
say() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
ask_yes() { return 0; }

MOCK_DISK=/tmp/mnt/keenutils-cache-test
mkdir -p "$MOCK_DISK" /opt/var/backups/keenutils
# Simulate /opt and USB root on the same device (CI is not a Keenetic).
filesystem_id() {
    case "$1" in
        /opt|"$MOCK_DISK") printf 'dev:keenetic-mock\n' ;;
        *) return 1 ;;
    esac
}
is_mounted_disk() { [ "$1" = "$MOCK_DISK" ]; }
find_entware_disk
[ "$DISK_ROOT" = "$MOCK_DISK" ]

cat > /tmp/keenutils-cache-api.py <<'PY'
import base64
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

db = "/tmp/keenutils-cache-state.json"
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/settings":
            self.send_response(404)
            self.end_headers()
            return
        expected = "Basic " + base64.b64encode(b"tester:testsecret").decode()
        if self.headers.get("Authorization") != expected:
            self.send_response(401)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", "0"))
        req = json.loads(self.rfile.read(length))
        with open(db) as fh:
            current = json.load(fh)
        if req["action"] == "get":
            payload = json.dumps(current).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        elif req["action"] == "set":
            # TorrServer can return HTTP 200 even in read-only DB mode.
            if not os.path.exists("/tmp/keenutils-cache-readonly"):
                with open(db, "w") as fh:
                    json.dump(req["sets"], fh)
            self.send_response(200)
            self.end_headers()
    def log_message(self, fmt, *args):
        pass
HTTPServer(("127.0.0.1", 18090), Handler).serve_forever()
PY
printf '{"UseDisk":false,"TorrentsSavePath":"","CacheSize":67108864,"ReaderReadAHead":90,"PreloadCache":50,"DownloadRateLimit":0,"UploadRateLimit":200,"FriendlyName":"test"}\n' > /tmp/keenutils-cache-state.json
python3 /tmp/keenutils-cache-api.py >/tmp/keenutils-cache-api.log 2>&1 &
api_pid=$!
trap 'kill "$api_pid" 2>/dev/null || :; torr_api_cleanup; rm -rf "$MOCK_DISK"' EXIT
sleep 1
TORR_API_URL=http://127.0.0.1:18090/settings
TORR_RESPONSE_FILE=$(mktemp /tmp/keenutils-response.XXXXXX)
TORR_AUTHFILE=''
if get_torr_settings; then
    echo 'Unauthenticated API unexpectedly succeeded' >&2
    exit 1
fi
[ "$TORR_HTTP_STATUS" = 401 ]
TORR_AUTHFILE=$(mktemp /tmp/.keenutils-mock-auth.XXXXXX)
printf 'user = "tester:testsecret"\n' > "$TORR_AUTHFILE"
chmod 600 "$TORR_AUTHFILE"
get_torr_settings
[ "$(printf '%s' "$TORR_CURRENT_SETTINGS" | jq -r .UseDisk)" = false ]
configure_torr_cache_inner
jq -e '
  .UseDisk == true and
  .TorrentsSavePath == "/tmp/mnt/keenutils-cache-test/tscashe" and
  .CacheSize == 1073741824 and
  .ReaderReadAHead == 95 and
  .PreloadCache == 5 and
  .DownloadRateLimit == 6250 and
  .UploadRateLimit == 200 and .FriendlyName == "test"
' /tmp/keenutils-cache-state.json >/dev/null
test -d "$MOCK_DISK/tscashe"
# A repeated run is a no-op when path, size, ratios and limit match.
cp /tmp/keenutils-cache-state.json /tmp/keenutils-cache-before.json
configure_torr_cache_inner >/tmp/keenutils-cache-noop.log
grep -Fq 'уже совпадают' /tmp/keenutils-cache-noop.log
cmp -s /tmp/keenutils-cache-before.json /tmp/keenutils-cache-state.json
# Path already correct but the speed limit has been changed separately:
# reapplying the preset must not short-circuit on path equality alone.
jq '.DownloadRateLimit=0' /tmp/keenutils-cache-state.json >/tmp/keenutils-cache-rate-mismatch.json
mv /tmp/keenutils-cache-rate-mismatch.json /tmp/keenutils-cache-state.json
configure_torr_cache_inner
jq -e '.DownloadRateLimit==6250 and .CacheSize==1073741824 and .PreloadCache==5' /tmp/keenutils-cache-state.json >/dev/null
# Similarly, an existing disk cache with smaller size must be updated.
jq '.CacheSize=67108864' /tmp/keenutils-cache-state.json >/tmp/keenutils-cache-size-mismatch.json
mv /tmp/keenutils-cache-size-mismatch.json /tmp/keenutils-cache-state.json
configure_torr_cache_inner
jq -e '.CacheSize==1073741824 and .ReaderReadAHead==95' /tmp/keenutils-cache-state.json >/dev/null
# HTTP 200 is NOT sufficient: read-only API must be detected as a failure.
printf '{"UseDisk":false,"TorrentsSavePath":"","CacheSize":67108864,"ReaderReadAHead":95,"PreloadCache":50,"DownloadRateLimit":0}\n' > /tmp/keenutils-cache-state.json
touch /tmp/keenutils-cache-readonly
if configure_torr_cache_inner; then
    echo 'Read-only TorrServer incorrectly reported cache configuration success' >&2
    exit 1
fi
jq -e '.UseDisk == false and .TorrentsSavePath == ""' /tmp/keenutils-cache-state.json >/dev/null
rm -f /tmp/keenutils-cache-readonly
# Do not modify incompatible or truncated settings payloads.
printf '{"UseDisk":false,"TorrentsSavePath":""}\n' > /tmp/keenutils-cache-state.json
if configure_torr_cache_inner; then
    echo 'Malformed settings payload was modified' >&2
    exit 1
fi
jq -e 'has("CacheSize") | not' /tmp/keenutils-cache-state.json >/dev/null
echo 'TorrServer API: authentication, 1024 MiB/95%/5%/6250 KiB/s, preservation, no-op, read-only and validation passed.'
