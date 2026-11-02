#!/usr/bin/env bash
set -Eeuo pipefail
image="${1:?usage: audit-image.sh IMAGE}"
# Never print file contents, filenames of secrets, or credentials to CI logs.
docker run --rm --entrypoint /bin/bash "$image" -euo pipefail -c '
  fail=0
  for root in /opt/gwn-defaults /gwn/conf /gwn/data; do
    [[ -d "$root" ]] || continue
    # Vendor installer may generate private keys/cert stores. Fail closed until
    # the image is changed so runtime secrets are generated on first start.
    if find "$root" -type f \( -iname "*.key" -o -iname "*.p12" -o -iname "*.pfx" -o -iname "*.jks" -o -iname "id_rsa" -o -iname "id_ed25519" \) -print -quit | grep -q .; then
      echo "BLOCKED: key material detected in image runtime/default directories" >&2
      fail=1
    fi
    if grep -rIlE --include="*.conf" --include="*.pem" --include="*.txt" --include="*.properties" \
      -- "-----BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----" "$root" 2>/dev/null | grep -q .; then
      echo "BLOCKED: PEM private key detected in image" >&2
      fail=1
    fi
  done
  if [[ "$fail" -ne 0 ]]; then exit 1; fi
  echo "Static key-material checks passed; manual credential and redistribution review still required"
'
