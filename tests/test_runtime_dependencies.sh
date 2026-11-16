#!/usr/bin/env bash
set -euo pipefail

# Run inside the built container (e.g. podman run --rm --entrypoint /bin/bash IMAGE ...).
ldd /gwn/bin/jre/lib/libfontmanager.so | tee /tmp/fontmanager-ldd.txt
if grep -q 'not found' /tmp/fontmanager-ldd.txt; then
  echo 'ERROR: Missing Java font manager native library' >&2
  exit 1
fi
fc-match sans >/dev/null
[ -d /gwn_backup ] && [ ! -L /gwn_backup ]
runuser -u gwn -- test -w /gwn_backup
echo 'Runtime dependencies and backup path OK'
