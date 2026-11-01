#!/usr/bin/env python3
"""Check the Grandstream official tools page for published AlmaLinux GWN Manager versions."""
import pathlib
import re
import urllib.request

URL = "https://www.grandstream.com/support/tools"
PATTERN = re.compile(r"GWN_Manager[-_]([0-9]+(?:\.[0-9]+){3})[-_]AlmaLinux9\.(?:tar\.gz|ova)", re.I)

def version_key(text):
    return tuple(int(n) for n in text.split('.'))

with urllib.request.urlopen(urllib.request.Request(URL, headers={"User-Agent": "gwn-manager-release-checker/1.0"}), timeout=30) as resp:
    html = resp.read().decode('utf-8', 'replace')
versions = set(PATTERN.findall(html))
if not versions:
    raise SystemExit("No archive version found on the official page; refusing automatic changes")
latest = max(versions, key=version_key)
current = pathlib.Path('VERSION').read_text().strip()
print(f"Current: {current}; upstream: {latest}")
if version_key(latest) > version_key(current):
    pathlib.Path('VERSION').write_text(latest + '\n')
    # Force new checksum review: never reuse previous archive hash.
    pathlib.Path('SHA256SUM').write_text('# REVIEW REQUIRED: calculate and verify checksum for ' + latest + '\n')
