import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

def load(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

release = load('release', 'check-release.py')
sync = load('sync', 'sync-release.py')

class ReleaseTests(unittest.TestCase):
    def test_official_archive_links_only_and_four_part_ordering(self):
        html = '''<a href="https://firmware.grandstream.com/GWN_Manager-1.1.9.99-AlmaLinux9.tar.gz">old</a>
        <a href="https://firmware.grandstream.com/GWN_Manager-1.1.40.8-AlmaLinux9.tar.gz">new</a>
        <a href="https://other.example/GWN_Manager-9.9.9.9-AlmaLinux9.tar.gz">ignore</a>
        <a href="https://firmware.grandstream.com/GWN_Manager-8.8.8.8-Ubuntu.tar.gz">ignore</a>
        <a href="https://firmware.grandstream.com/GWN_Manager_9.9.9.9_AlmaLinux9.ova">ignore</a>'''
        self.assertEqual(release.discover(html), '1.1.40.8')
        with self.assertRaises(ValueError):
            release.discover('<html>Layout changed</html>')

    def test_new_release_gets_its_own_checksum(self):
        old = {'version': '1.1.39.8', 'digest': 'sha256:' + 'a' * 64}
        calls = []
        def hasher(version):
            calls.append(version)
            return 'sha256:' + 'b' * 64
        result = release.feed(old, '1.1.40.8', hasher)
        self.assertEqual(calls, ['1.1.40.8'])
        self.assertEqual(result['releases'][1]['digest'], 'sha256:' + 'b' * 64)
        self.assertEqual(release.feed(old, old['version'], hasher), {'releases': [old]})
        self.assertEqual(calls, ['1.1.40.8'])

    def test_release_sync_updates_all_build_and_deployment_references(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'k8s').mkdir()
            for name in ['VERSION', 'SHA256SUM', 'Containerfile', 'upstream.json', 'k8s/gwn-manager.yaml']:
                shutil.copyfile(ROOT / name, root / name)
            lock = {'version': '1.1.40.8', 'digest': 'sha256:' + 'b' * 64}
            (root / 'upstream.json').write_text(json.dumps(lock))
            with self.assertRaises(ValueError):
                sync.synchronize(root, check=True)
            sync.synchronize(root)
            sync.synchronize(root, check=True)
            self.assertEqual((root / 'VERSION').read_text(), '1.1.40.8\n')
            self.assertEqual((root / 'SHA256SUM').read_text(), 'b' * 64 + '\n')
            self.assertIn('ARG GWN_VERSION=1.1.40.8\n', (root / 'Containerfile').read_text())
            self.assertEqual((root / 'k8s/gwn-manager.yaml').read_text().count('grandstream-gwn-manager:1.1.40.8'), 2)
            lock['digest'] = 'invalid'
            (root / 'upstream.json').write_text(json.dumps(lock))
            with self.assertRaises(ValueError):
                sync.synchronize(root)

    def test_heap_caps_override_vendor_flags_without_splitting_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            java = root / 'java'
            java.write_text('#!/bin/bash\nprintf "%s\\0" "$@"\n')
            java.chmod(0o755)
            script = (ROOT / 'scripts/java-memory-limited.sh').read_text()
            launcher = root / 'launcher'
            launcher.write_text(script.replace('/gwn/bin/jre/bin/java', str(java)))
            output = subprocess.check_output(['bash', str(launcher), '-Xmx3g', '-Xms1g', '-jar', 'a path/app.jar', ''])
            self.assertEqual(output.split(b'\0')[:-1], [b'-Xms64m', b'-Xmx512m', b'-jar', b'a path/app.jar', b''])

if __name__ == '__main__':
    unittest.main()
