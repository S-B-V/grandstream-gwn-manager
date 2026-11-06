import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('prepare', ROOT / 'scripts/prepare-release-pr.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)

class PrepareTests(unittest.TestCase):
    def pr(self):
        return {'state': 'open', 'user': {'login': 'renovate[bot]'},
                'head': {'repo': {'full_name': 'owner/repo'}, 'ref': 'renovate/gwn-manager-1.x', 'sha': 'a' * 40},
                'base': {'ref': 'main'}}

    def test_forks_and_other_authors_are_rejected(self):
        pr = self.pr()
        prepare.validate_pr(pr, 'owner/repo')
        pr['head']['repo']['full_name'] = 'someone/fork'
        with self.assertRaises(ValueError):
            prepare.validate_pr(pr, 'owner/repo')
        pr = self.pr()
        pr['user']['login'] = 'someone'
        with self.assertRaises(ValueError):
            prepare.validate_pr(pr, 'owner/repo')

    def test_new_release_commit_and_explicit_test_dispatch(self):
        pr = self.pr()
        source = {name: (ROOT / name).read_text() for name in prepare.FILES}
        source['VERSION'] = '1.1.40.8\n'
        calls = []
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self):
                return b'<a href="https://firmware.grandstream.com/GWN_Manager-1.1.40.8-AlmaLinux9.tar.gz">new</a>'
        class FakeAPI:
            def __init__(self, *args): pass
            def file(self, name, ref): return source[name]
            def request(self, path, method='GET', data=None):
                calls.append((path, method, data))
                if path.startswith('/pulls/'): return pr
                if path.startswith('/git/commits/') and method=='GET': return {'tree': {'sha': 'old-tree'}}
                if path=='/git/trees': return {'sha': 'new-tree'}
                if path=='/git/commits': return {'sha': 'b' * 40}
                return None
        with patch.dict(os.environ, {'GITHUB_REPOSITORY': 'owner/repo', 'GWN_PR_NUMBER': '5', 'GITHUB_TOKEN': 'fake'}), \
             patch.object(prepare, 'GitHub', FakeAPI), \
             patch.object(prepare.release, 'open_official', return_value=Response()), \
             patch.object(prepare.release, 'archive_digest', return_value='sha256:' + 'b' * 64):
            prepare.main()
        tree = next(data for path, method, data in calls if path=='/git/trees')
        files = {entry['path']: entry['content'] for entry in tree['tree']}
        self.assertEqual(json.loads(files['upstream.json'])['digest'], 'sha256:' + 'b' * 64)
        self.assertEqual(files['SHA256SUM'], 'b' * 64 + '\n')
        self.assertEqual(files['k8s/gwn-manager.yaml'].count('grandstream-gwn-manager:1.1.40.8'), 2)
        self.assertEqual(calls[-1], ('/actions/workflows/build.yml/dispatches', 'POST', {'ref': pr['head']['ref']}))
        update = next(data for path, method, data in calls if path.startswith('/git/refs/'))
        self.assertIs(update['force'], False)

if __name__=='__main__': unittest.main()
