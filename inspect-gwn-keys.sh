#!/usr/bin/env bash
set -Eeuo pipefail
image="${1:-gwn-manager:publish-candidate}"
# Execute locally only. Print paths and metadata, never contents.
docker run --rm --entrypoint /bin/bash "$image" -euo pipefail -c '
for root in /gwn/conf /gwn/data /opt/gwn-defaults; do
  [[ -d "$root" ]] || continue
  printf "\n=== %s ===\n" "$root"
  find "$root" -type f \( -iname "*.key" -o -iname "*.pem" -o -iname "*.p12" -o -iname "*.pfx" -o -iname "*.jks" -o -iname "id_rsa" -o -iname "id_ed25519" \) -printf "%p (%s bytes)\n"
  grep -rIlE --include="*.conf" --include="*.pem" --include="*.txt" --include="*.properties" -- "-----BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----" "$root" 2>/dev/null || true
done
' | sort -u
