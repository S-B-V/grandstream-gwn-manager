#!/usr/bin/env python3
"""Safely inventory a downloaded Grandstream installer without executing it."""
import hashlib
import json
import os
import pathlib
import re
import sys
import tarfile

archive = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
sha = hashlib.sha256(archive.read_bytes()).hexdigest()
listed = []
suspicious = []
scripts = []
patterns = re.compile(r'(?i)(systemctl|service |dnf |yum |rpm |postgres|mysql|maria|mongo|redis|nginx|firewall|/gwn|useradd|chown|chmod|sudo|docker|podman|selinux|setenforce)')
with tarfile.open(archive, 'r:gz') as tar:
    for member in tar:
        name = member.name
        p = pathlib.PurePosixPath(name)
        if p.is_absolute() or '..' in p.parts or member.issym() or member.islnk() or member.isdev():
            suspicious.append(name)
        listed.append({'path': name, 'bytes': member.size, 'kind': member.type.decode('ascii', 'replace')})
        if member.isfile() and member.size < 2_000_000 and (p.name in {'install','uninstall','gwn'} or p.suffix in {'.sh','.service'}):
            fileobj = tar.extractfile(member)
            if fileobj:
                data = fileobj.read().decode('utf-8', 'replace')
                matches = [{'line': n, 'text': line[:400]} for n, line in enumerate(data.splitlines(), 1) if patterns.search(line)]
                scripts.append({'path': name, 'matches': matches[:300]})
summary = {'sha256': sha, 'total_members': len(listed), 'unsafe_or_link_members': suspicious, 'files': listed, 'script_references': scripts}
(out / 'inventory.json').write_text(json.dumps(summary, indent=2))
with (out / 'summary.md').open('w') as f:
    f.write(f'# GWN installer inspection\n\nArchive SHA-256: `{sha}`\n\nEntries: {len(listed)}\n\n')
    f.write('## Links / unsafe entries\n\n' + ('\n'.join(f'- `{s}`' for s in suspicious) if suspicious else 'None identified') + '\n\n')
    for script in scripts:
        f.write(f"## {script['path']}\n\n")
        for m in script['matches']:
            f.write(f"- L{m['line']}: `{m['text'].replace('`', '')}`\n")
print(f'Wrote {out}/inventory.json and summary.md')
