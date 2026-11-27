#!/usr/bin/env python3
"""Check all official downloads and mirrors without executing remote code."""
import csv
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

CATALOG = Path("sources.conf")
SCRIPT_KEYS = {"nfqws_menu", "keenkit", "flashkeen", "hydra", "awg", "torrserver", "torr_watchdog"}
FEEDS = {"nfqws_feed", "nfqws2_feed", "nfqws_web_feed"}


def check(url, kind):
    # A HEAD 200 alone can mean an HTML error page or a stale redirect.
    # Inspect the start of the actual download; never execute it.
    request = urllib.request.Request(
        url, headers={"User-Agent": "KeenUtils-links-check/2.0"}
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            prefix = response.read(4096)
            if not 200 <= response.status < 300:
                return False, f"HTTP {response.status}"
            if kind == "feed" and not prefix.startswith(b"\x1f\x8b"):
                return False, "response is not a gzip package index"
            if kind == "script" and not prefix.lstrip(b"\xef\xbb\xbf \t\r\n").startswith(b"#!"):
                return False, "response has no script shebang"
            return True, f"HTTP {response.status}, {kind} verified"
    except Exception as exc:
        return False, f"{type(exc).__name__}: {exc}"


def targets():
    seen = set()
    with CATALOG.open(encoding="utf-8") as catalog:
        for row in csv.reader((line for line in catalog if not line.lstrip().startswith("#")), delimiter="|"):
            if not row or not row[0].strip():
                continue
            if len(row) != 3 or row[0] in seen:
                raise SystemExit("Invalid or duplicate catalog entry")
            key, primary, mirror = row
            seen.add(key)
            if key not in SCRIPT_KEYS | FEEDS or not primary.startswith("https://"):
                raise SystemExit(f"Unknown key or invalid primary URL: {key}")
            kind = "feed" if key in FEEDS else "script"
            for label, url in (("primary", primary), ("mirror", mirror)):
                if url:
                    if not url.startswith("https://"):
                        raise SystemExit(f"Invalid URL for {key} {label}")
                    yield key, label, url.rstrip("/") + ("/Packages.gz" if kind == "feed" else ""), kind
    if seen != SCRIPT_KEYS | FEEDS:
        raise SystemExit("Missing sources in catalog")

    # AWG Manager's official install.sh delegates package downloads to its
    # documented HTTP Entware feed, rather than GitHub releases directly.
    # Check the three supported architectures too; do not change router feeds.
    for arch in ("aarch64-k3.10", "mips-k3.4", "mipsel-k3.4"):
        yield "awg_repo", arch, f"http://repo.hoaxisr.ru/{arch}/Packages.gz", "feed"


def run_target(target):
    key, label, url, kind = target
    ok, reason = check(url, kind)
    return ok, f"{key}: {'OK' if ok else 'FAILED'} {label}: {reason} ({url})"


def main():
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(run_target, list(targets())))
    for _, message in results:
        print(message)
    if not all(ok for ok, _ in results):
        print("One or more official sources or mirrors failed. Review upstream URLs.")
        return 1
    print("All official sources, mirrors and AWG package feeds responded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
