#!/usr/bin/env python3
"""Complete an in-repository Renovate version PR using trusted base-branch code.

Never execute PR code. Read its five release files as data, download/hash the
fixed official vendor URL, commit generated references atomically, then dispatch
read-only build/test behavior on the updated branch (publishing is main-only).
"""
import base64
import importlib.util
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent.parent

def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

release = load('release', 'check-release.py')
sync = load('sync_release', 'sync-release.py')
FILES = ['upstream.json', 'VERSION', 'SHA256SUM', 'Containerfile', 'k8s/gwn-manager.yaml']

class GitHub:
    def __init__(self, repo, token):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
            raise ValueError('Invalid repository')
        self.base = f'https://api.github.com/repos/{repo}'
        self.token = token
    def request(self, path, method='GET', data=None):
        payload = None if data is None else json.dumps(data).encode()
        request = urllib.request.Request(self.base + path, data=payload, method=method,
            headers={'Authorization': 'Bearer ' + self.token,
                     'Accept': 'application/vnd.github+json',
                     'X-GitHub-Api-Version': '2022-11-28',
                     'User-Agent': 'gwn-release-pr', 'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    def file(self, name, ref):
        value = self.request('/contents/' + urllib.parse.quote(name, safe='/') + '?ref=' + ref)
        if value.get('encoding') != 'base64':
            raise ValueError('Expected a small base64 release configuration file')
        return base64.b64decode(value['content']).decode('utf-8')

def validate_pr(pr, repo):
    if not (pr['state'] == 'open' and pr['user']['login'] == 'renovate[bot]'
            and pr['head']['repo']['full_name'] == repo
            and pr['head']['ref'].startswith('renovate/')
            and pr['base']['ref'] == 'main'):
        raise ValueError('Only open Renovate PRs in this repository targeting main are supported')

def main():
    repo = os.environ['GITHUB_REPOSITORY']
    number = os.environ['GWN_PR_NUMBER']
    if not number.isdigit():
        raise ValueError('Invalid PR number')
    api = GitHub(repo, os.environ['GITHUB_TOKEN'])
    pr = api.request('/pulls/' + number)
    validate_pr(pr, repo)
    head = pr['head']['sha']
    version = api.file('VERSION', head).strip()
    if not re.fullmatch(sync.VERSION_RE, version):
        raise ValueError('Invalid proposed version')
    current = sync.read_lock()
    if version == current['version']:
        print('No upstream version change; normal PR checks apply.')
        return
    if tuple(map(int, version.split('.'))) < tuple(map(int, current['version'].split('.'))):
        raise ValueError('Refusing an upstream downgrade')
    contents = {name: api.file(name, head) for name in FILES}
    proposed_lock = json.loads(contents['upstream.json'])
    # Already prepared branches retain the approved checksum, rather than silently
    # accepting a changed download for the same version on subsequent events.
    if proposed_lock['version'] == version:
        digest = sync.read_lock_from_value(proposed_lock)['digest']
    else:
        sync.read_lock_from_value(proposed_lock)
        with release.open_official(release.TOOLS_URL) as response:
            links = release.Links()
            links.feed(response.read().decode('utf-8', 'replace'))
        if version not in links.versions:
            raise ValueError('Proposed version has no official AlmaLinux9 tar.gz link')
        digest = release.archive_digest(version)
    with tempfile.TemporaryDirectory(prefix='gwn-release-') as directory:
        root = Path(directory)
        (root / 'k8s').mkdir()
        for name, text in contents.items():
            (root / name).write_text(text)
        (root / 'upstream.json').write_text(json.dumps({'version': version, 'digest': digest}, indent=2) + '\n')
        sync.synchronize(root)
        changes = {name: (root / name).read_text() for name in FILES if (root / name).read_text() != contents[name]}
    if not changes:
        print('Release PR already synchronized; ensuring its build is dispatched.')
        api.request('/actions/workflows/build.yml/dispatches', 'POST', {'ref': pr['head']['ref']})
        return
    commit = api.request('/git/commits/' + head)
    tree = api.request('/git/trees', 'POST', {
        'base_tree': commit['tree']['sha'],
        'tree': [{'path': name, 'mode': '100644', 'type': 'blob', 'content': text} for name, text in changes.items()]})
    new_commit = api.request('/git/commits', 'POST', {
        'message': f'chore: pin GWN Manager {version} archive and build inputs',
        'author': {'name': 'github-actions[bot]',
                   'email': '41898282+github-actions[bot]@users.noreply.github.com'},
        'tree': tree['sha'], 'parents': [head]})
    latest = api.request('/pulls/' + number)
    validate_pr(latest, repo)
    if latest['head']['sha'] != head:
        raise ValueError('PR changed while preparing it; refusing to overwrite concurrent edits')
    branch = pr['head']['ref']
    api.request('/git/refs/heads/' + urllib.parse.quote(branch, safe='/'), 'PATCH',
                {'sha': new_commit['sha'], 'force': False})
    # GITHUB_TOKEN commits do not emit another pull_request run. An explicit
    # workflow_dispatch does run and attaches checks to this updated branch SHA.
    api.request('/actions/workflows/build.yml/dispatches', 'POST', {'ref': branch})
    print(f'Prepared PR #{number}: GWN Manager {version}, {digest}')
    print('Dispatched build/runtime tests for the updated branch.')

if __name__ == '__main__':
    main()
