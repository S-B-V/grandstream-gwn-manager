#!/usr/bin/env bash
set -Eeuo pipefail
image=${1:?usage: audit-image.sh IMAGE}
engine=${ENGINE:-podman}
"$engine" run --rm --entrypoint /bin/bash "$image" -euo pipefail -c '
  for root in /opt/gwn-defaults /gwn; do
    [[ -d "$root" ]] || continue
    if find "$root" -type f \( -iname "*.key" -o -iname "*.p12" -o -iname "*.pfx" -o -iname "*.jks" -o -iname "id_rsa" -o -iname "id_ed25519" \) -print -quit | grep -q .; then
      echo "BLOCKED: key-format files found" >&2; exit 1
    fi
    if grep -rIlE --include="*.pem" --include="*.crt" --include="*.conf" --include="*.txt" -- "-----BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----" "$root" 2>/dev/null | grep -q .; then
      echo "BLOCKED: embedded private key" >&2; exit 1
    fi
  done
  echo "Static key check passed; bundled DB secrets and redistribution NOT cleared"
'
