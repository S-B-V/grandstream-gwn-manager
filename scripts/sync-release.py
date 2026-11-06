#!/usr/bin/env python3
"""Keep legacy build inputs and deployment tags consistent with upstream.json."""
import argparse
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION_RE = r"[0-9]+(?:\.[0-9]+){3}"

def read_lock_from_value(lock):
    if not re.fullmatch(VERSION_RE, lock['version']):
        raise ValueError('Invalid four-part upstream version')
    if not re.fullmatch(r'sha256:[a-f0-9]{64}', lock['digest']):
        raise ValueError('Invalid upstream SHA-256')
    return lock

def read_lock(root=ROOT):
    return read_lock_from_value(json.loads((root / 'upstream.json').read_text()))

def synchronize(root=ROOT, check=False):
    lock = read_lock(root)
    version = lock['version']
    generated = {'VERSION': version + '\n', 'SHA256SUM': lock['digest'][7:] + '\n'}
    containerfile = (root / 'Containerfile').read_text()
    updated, count = re.subn(r'^ARG GWN_VERSION=' + VERSION_RE + r'$',
                             'ARG GWN_VERSION=' + version, containerfile, flags=re.M)
    if count != 1:
        raise ValueError('Expected one Containerfile GWN_VERSION default')
    generated['Containerfile'] = updated
    manifest = (root / 'k8s/gwn-manager.yaml').read_text()
    updated, count = re.subn(r'(image: ghcr\.io/s-b-v/grandstream-gwn-manager:)' + VERSION_RE,
                             lambda m: m[1] + version, manifest)
    if count != 2:
        raise ValueError('Expected init and application GWN image references')
    generated['k8s/gwn-manager.yaml'] = updated
    stale = [name for name, text in generated.items() if (root / name).read_text() != text]
    if check and stale:
        raise ValueError('Release inputs out of sync: ' + ', '.join(stale))
    if not check:
        for name in stale:
            (root / name).write_text(generated[name])
    return lock

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    lock = synchronize(check=args.check)
    print('Release inputs consistent: ' + lock['version'])
