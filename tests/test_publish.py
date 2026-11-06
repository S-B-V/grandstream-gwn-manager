import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

class PublishTests(unittest.TestCase):
    def run_publish(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stub = root / 'docker'
            stub.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$CALL_LOG"
if [[ "$1 $2" == 'manifest inspect' ]]; then
  case "$REGISTRY_MODE" in
    missing) echo 'manifest unknown' >&2; exit 1 ;;
    unavailable) echo 'network timeout' >&2; exit 1 ;;
    existing) exit 0 ;;
  esac
fi
if [[ "$1 $2" == 'image inspect' ]]; then echo 'ghcr.io/owner/repo@sha256:abc'; fi
''')
            stub.chmod(0o755)
            log = root / 'calls'
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       CALL_LOG=str(log), REGISTRY_MODE=mode, REPO='Owner/Repo',
                       GWN_VERSION='1.1.39.8', GITHUB_SHA='a' * 40,
                       GITHUB_STEP_SUMMARY=str(root / 'summary'))
            result = subprocess.run(['bash', str(ROOT / 'scripts/publish-image.sh'), 'candidate'],
                                    env=env, capture_output=True, text=True)
            return result, log.read_text()

    def test_registry_outage_never_becomes_permission_to_publish(self):
        result, calls = self.run_publish('unavailable')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('push ', calls)

    def test_new_release_publishes_commit_version_and_latest(self):
        result, calls = self.run_publish('missing')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sum(line.startswith('push ') for line in calls.splitlines()), 3)

    def test_rerun_preserves_existing_commit_and_version_images(self):
        result, calls = self.run_publish('existing')
        self.assertEqual(result.returncode, 0, result.stderr)
        pushes = [line for line in calls.splitlines() if line.startswith('push ')]
        self.assertEqual(pushes, ['push ghcr.io/owner/repo:latest'])

if __name__=='__main__': unittest.main()
