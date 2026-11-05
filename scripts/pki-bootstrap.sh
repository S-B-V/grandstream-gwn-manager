
#!/usr/bin/env bash
set -Eeuo pipefail

# Grandstream GWN Manager - PKI Bootstrap
#
# EXPERIMENTAL - interoperability not fully validated.
#
# Operates exclusively on persistent:
#   /gwn/data
#   /gwn/conf
#
# Never generates private keys in the immutable container image.
#
# Usage:
#   GWN_PUBLIC_HOST=localhost pki-bootstrap --fresh
#
# --fresh is mandatory.
# Existing private keys or completed installations are never overwritten.

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

[[ "${1:-}" == "--fresh" ]] || {
    echo "ERROR: --fresh required" >&2
    exit 1
}

: "${GWN_PUBLIC_HOST:?GWN_PUBLIC_HOST is required}"

export GWN_PUBLIC_HOST

# ------------------------------------------------------------
# Validate public hostname or IP address
# ------------------------------------------------------------

SAN_TYPE=$(python3 - <<'PY'
import ipaddress
import os
import re

host = os.environ["GWN_PUBLIC_HOST"]

try:
    ipaddress.ip_address(host)
    print("IP")
except ValueError:
    if (
        len(host) > 253
        or not re.fullmatch(
            r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?",
            host
        )
        or any(
            not label or len(label) > 63
            for label in host.split(".")
        )
    ):
        raise SystemExit("Invalid GWN_PUBLIC_HOST")

    print("DNS")
PY
)

# ------------------------------------------------------------
# Validate persistent installation
# ------------------------------------------------------------

required_dirs=(
    /gwn/data/gwn/cert
    /gwn/data/nginx/cert
    /gwn/conf/nginx
    /gwn/conf/gwn/certs
)

for dir in "${required_dirs[@]}"; do
    [[ -d "$dir" ]] || {
        echo "ERROR: Missing vendor directory: $dir" >&2
        exit 1
    }
done

[[ ! -e /gwn/data/.pki-bootstrap-complete ]] || {
    echo "ERROR: PKI already bootstrapped" >&2
    exit 1
}

# ------------------------------------------------------------
# Never overwrite existing private keys
# ------------------------------------------------------------

private_keys=(
    /gwn/data/gwn/cert/ca.key
    /gwn/data/gwn/cert/gwn.manager.key
    /gwn/data/nginx/cert/ca.key
    /gwn/data/nginx/cert/gwn.manager.key
    /gwn/conf/nginx/ssl.key
    /gwn/conf/gwn/certs/sp-private-key.pem
)

for key in "${private_keys[@]}"; do
    [[ ! -e "$key" ]] || {
        echo "ERROR: Existing private key: $key" >&2
        exit 1
    }
done

# Validate vendor-provided public certificate chain.
# These files must not be replaced with generated certificates.

vendor_certs=(
    /gwn/data/gwn/router/cert/serverCert.pem
    /gwn/data/gwn/router/cert/grandstream_intermediate_crt_chain2.pem
)

for cert in "${vendor_certs[@]}"; do
    [[ -s "$cert" ]] || {
        echo "ERROR: Missing vendor router certificate: $cert" >&2
        exit 1
    }
done

umask 077

# ------------------------------------------------------------
# Temporary files and cleanup
# ------------------------------------------------------------

tmpdir=$(mktemp -d)

cleanup() {
    rm -rf "$tmpdir"
}

trap cleanup EXIT

# ------------------------------------------------------------
# Generate internal CA and controller certificates
# ------------------------------------------------------------

make_ca_and_leaf() {
    local dir="$1"
    local root="$dir/ca"
    local csr="$tmpdir/$(basename "$(dirname "$dir")")-$(basename "$dir").csr"

    # Generate installation-specific CA.
    openssl req \
        -new \
        -x509 \
        -newkey rsa:3072 \
        -nodes \
        -sha256 \
        -days 3650 \
        -subj '/CN=GWN Local Root CA' \
        -keyout "$root.key" \
        -out "$root.pem" \
        >/dev/null 2>&1

    # Generate controller key and CSR.
    openssl req \
        -new \
        -newkey rsa:3072 \
        -nodes \
        -sha256 \
        -subj '/CN=gwn.manager' \
        -keyout "$dir/gwn.manager.key" \
        -out "$csr" \
        >/dev/null 2>&1

    # Sign controller certificate.
    openssl x509 \
        -req \
        -in "$csr" \
        -CA "$root.pem" \
        -CAkey "$root.key" \
        -CAcreateserial \
        -sha256 \
        -days 825 \
        -out "$dir/gwn.manager.crt" \
        >/dev/null 2>&1

    # Validate certificate chain.
    openssl verify \
        -CAfile "$root.pem" \
        "$dir/gwn.manager.crt" \
        >/dev/null
}

make_ca_and_leaf /gwn/data/gwn/cert
make_ca_and_leaf /gwn/data/nginx/cert

# ------------------------------------------------------------
# Generate HTTPS certificate with SAN
# ------------------------------------------------------------

SSL_KEY=/gwn/conf/nginx/ssl.key
SSL_CERT=/gwn/conf/nginx/ssl.pem
SSL_CSR="$tmpdir/nginx.csr"
SSL_EXT="$tmpdir/nginx.ext"

cat > "$SSL_EXT" <<EOF
[v3_server]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=${SAN_TYPE}:${GWN_PUBLIC_HOST}
EOF

openssl req \
    -new \
    -newkey rsa:3072 \
    -nodes \
    -sha256 \
    -subj '/CN=gwn.manager' \
    -keyout "$SSL_KEY" \
    -out "$SSL_CSR" \
    >/dev/null 2>&1

openssl x509 \
    -req \
    -in "$SSL_CSR" \
    -CA /gwn/data/nginx/cert/ca.pem \
    -CAkey /gwn/data/nginx/cert/ca.key \
    -CAcreateserial \
    -sha256 \
    -days 825 \
    -extfile "$SSL_EXT" \
    -extensions v3_server \
    -out "$SSL_CERT" \
    >/dev/null 2>&1

# Verify certificate chain.
openssl verify \
    -CAfile /gwn/data/nginx/cert/ca.pem \
    "$SSL_CERT" \
    >/dev/null

# Verify certificate matches configured hostname/IP.
if [[ "$SAN_TYPE" == "IP" ]]; then
    openssl x509 \
        -in "$SSL_CERT" \
        -noout \
        -checkip "$GWN_PUBLIC_HOST" \
        | grep -q "does match certificate"
else
    openssl x509 \
        -in "$SSL_CERT" \
        -noout \
        -checkhost "$GWN_PUBLIC_HOST" \
        | grep -q "does match certificate"
fi

# ------------------------------------------------------------
# Generate service provider certificate
# ------------------------------------------------------------

openssl req \
    -new \
    -x509 \
    -newkey rsa:3072 \
    -nodes \
    -sha256 \
    -days 825 \
    -subj '/CN=*.gwn.manager' \
    -keyout /gwn/conf/gwn/certs/sp-private-key.pem \
    -out /gwn/conf/gwn/certs/sp-certificate.pem \
    >/dev/null 2>&1

# ------------------------------------------------------------
# File permissions
# ------------------------------------------------------------

chmod 600 \
    /gwn/data/gwn/cert/ca.key \
    /gwn/data/gwn/cert/gwn.manager.key \
    /gwn/data/nginx/cert/ca.key \
    /gwn/data/nginx/cert/gwn.manager.key \
    /gwn/conf/nginx/ssl.key \
    /gwn/conf/gwn/certs/sp-private-key.pem

chmod 644 \
    /gwn/data/gwn/cert/ca.pem \
    /gwn/data/gwn/cert/gwn.manager.crt \
    /gwn/data/nginx/cert/ca.pem \
    /gwn/data/nginx/cert/gwn.manager.crt \
    /gwn/conf/nginx/ssl.pem \
    /gwn/conf/gwn/certs/sp-certificate.pem

# ------------------------------------------------------------
# Completion marker
# ------------------------------------------------------------

: > /gwn/data/.pki-bootstrap-complete

printf 'PKI bootstrap completed (EXPERIMENTAL).\n'
printf 'Public hostname: %s\n' "$GWN_PUBLIC_HOST"
printf 'SAN type: %s\n' "$SAN_TYPE"
printf 'Certificate: %s\n' "$SSL_CERT"
