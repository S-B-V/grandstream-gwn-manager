#!/usr/bin/env python3
"""Create a Renovate datasource with versions and SHA-256 from official downloads."""
import argparse
import hashlib
from html.parser import HTMLParser
import json
import pathlib
import re
import urllib.parse
import urllib.request
import importlib.util

spec = importlib.util.spec_from_file_location('sync_release', pathlib.Path(__file__).with_name('sync-release.py'))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)
TOOLS_URL = 'https://www.grandstream.com/support/tools'
ARCHIVE_RE = re.compile(r'^https://firmware\.grandstream\.com/GWN_Manager-([0-9]+(?:\.[0-9]+){3})-AlmaLinux9\.tar\.gz$')

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.versions = set()
    def handle_starttag(self, tag, attrs):
        if tag.lower() != 'a':
            return
        for key, value in attrs:
            if key.lower() == 'href' and value:
                match = ARCHIVE_RE.fullmatch(urllib.parse.urljoin(TOOLS_URL, value))
                if match:
                    self.versions.add(match[1])

def discover(html):
    links = Links()
    links.feed(html)
    if not links.versions:
        raise ValueError('No official AlmaLinux9 tar.gz links found; refusing changes')
    return max(links.versions, key=lambda v: tuple(map(int, v.split('.'))))

def open_official(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'gwn-manager-renovate/2.0'})
    response = urllib.request.urlopen(request, timeout=60)
    parsed = urllib.parse.urlparse(response.url)
    if parsed.scheme != 'https' or parsed.hostname not in {'www.grandstream.com', 'firmware.grandstream.com'}:
        response.close()
        raise ValueError('Unexpected upstream redirect')
    return response

def archive_digest(version):
    url = f'https://firmware.grandstream.com/GWN_Manager-{version}-AlmaLinux9.tar.gz'
    digest = hashlib.sha256()
    total = 0
    with open_official(url) as response:
        while block := response.read(1024 * 1024):
            total += len(block)
            if total > 4 * 1024**3:
                raise ValueError('Upstream archive exceeds 4 GiB')
            digest.update(block)
    if not total:
        raise ValueError('Empty upstream archive')
    return 'sha256:' + digest.hexdigest()

def feed(current, latest, hasher=archive_digest):
    releases = [dict(current)]
    if tuple(map(int, latest.split('.'))) > tuple(map(int, current['version'].split('.'))):
        releases.append({'version': latest, 'digest': hasher(latest)})
    return {'releases': releases}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('/tmp/gwn-releases.json'))
    args = parser.parse_args()
    current = sync.read_lock()
    with open_official(TOOLS_URL) as response:
        latest = discover(response.read().decode('utf-8', 'replace'))
    result = feed(current, latest)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f"Pinned: {current['version']}; official latest: {latest}")
    print(f'Renovate datasource: {args.output}')
