#!/usr/bin/env python3
"""Daily link health check. Never executes remote content."""
import csv
import sys
import urllib.error
import urllib.request
from pathlib import Path

CATALOG = Path("sources.conf")
SCRIPT_KEYS = {"nfqws_menu", "keenkit", "hydra", "awg", "torrserver", "torr_watchdog"}
FEEDS = {"nfqws_feed", "nfqws2_feed", "nfqws_web_feed"}

def check(url):
    request = urllib.request.Request(
        url,
        method="HEAD",
        headers={"User-Agent": "KeenUtils-links-check/1.0"}
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as r:
            return 200 <= r.status < 400, f"HTTP {r.status}"
    except urllib.error.HTTPError as e:
        if e.code not in (403, 405):
            return False, f"HTTP {e.code}"
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"

    # Some hosts reject HEAD. Try a short GET, but never execute the script.
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "KeenUtils-links-check/1.0", "Range": "bytes=0-0"}
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as r:
            r.read(1)
            return 200 <= r.status < 400, f"HTTP {r.status}"
    except Exception as e:
        return False, f"{type(e).__name__}: {e}"

failed = False
keys_seen = set()
with CATALOG.open(encoding="utf-8") as catalog:
    for row in csv.reader((line for line in catalog if not line.lstrip().startswith("#")), delimiter="|"):
        if not row or not row[0].strip():
            continue
        if len(row) != 3 or row[0] in keys_seen:
            raise SystemExit("Invalid or duplicate catalog entry")
        key, primary, mirror = row
        keys_seen.add(key)
        # A package-feed URL is a repository base, not a downloadable installer.
        # Test its package index instead of GET /all.
        test_url = primary + "/Packages.gz" if key in FEEDS else primary
        if key not in SCRIPT_KEYS and key not in FEEDS:
            raise SystemExit(f"Unknown catalog key: {key}")
        ok, reason = check(test_url)
        print(f"{key}: {'OK' if ok else 'FAILED'} primary: {reason} ({test_url})")
        if not ok:
            failed = True
            if mirror:
                recovered, msg = check(mirror)
                print(f"  mirror: {'OK' if recovered else 'FAILED'}: {msg}")
if keys_seen != SCRIPT_KEYS | FEEDS:
    raise SystemExit("Missing sources in catalog")
if failed:
    print("One or more primary links failed. Review upstream URL changes.")
    sys.exit(1)
print("All official source links responded.")
