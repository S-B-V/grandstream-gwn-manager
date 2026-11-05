
#!/usr/bin/env bash
set -Eeuo pipefail

# Grandstream GWN Manager - Clean Bootstrap Test
#
# EXPERIMENTAL.
# Not approved for production or redistribution.
#
# Uses fresh persistent volumes.
# Existing containers and volumes are never overwritten.
#
# Example:
#   GWN_ACCESS_ADDRESS=127.0.0.1 \
#   GWN_PUBLIC_HOST=localhost \
#   GWN_PUBLIC_HTTPS_PORT=18447 \
#   bash scripts/test-clean-local.sh \
#     localhost/gwn-manager:access-test

image=${1:-localhost/gwn-manager:access-test}
engine=${ENGINE:-podman}

name=${NAME:-gwn-access-test}
data="${name}-data"
conf="${name}-conf"
port=${PORT:-18447}

export GWN_ACCESS_ADDRESS="${GWN_ACCESS_ADDRESS:-127.0.0.1}"
export GWN_PUBLIC_HOST="${GWN_PUBLIC_HOST:-localhost}"
export GWN_PUBLIC_HTTPS_PORT="${GWN_PUBLIC_HTTPS_PORT:-$port}"

# ------------------------------------------------------------
# Validate test parameters
# ------------------------------------------------------------

[[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
    echo "ERROR: Invalid container name" >&2
    exit 1
}

[[ "$port" =~ ^[0-9]+$ ]] && \
    (( port >= 1 && port <= 65535 )) || {
    echo "ERROR: Invalid host port" >&2
    exit 1
}

# ------------------------------------------------------------
# Never overwrite existing resources
# ------------------------------------------------------------

if "$engine" container exists "$name"; then
    echo "ERROR: Container already exists: $name" >&2
    exit 1
fi

for volume in "$data" "$conf"; do
    if "$engine" volume exists "$volume"; then
        echo "ERROR: Volume already exists: $volume" >&2
        exit 1
    fi
done

# ------------------------------------------------------------
# Verify image contents
# ------------------------------------------------------------

"$engine" run --rm \
    --entrypoint /bin/bash \
    "$image" -euo pipefail -c '
        [[ ! -e /opt/gwn-defaults/data/mysql ]] || {
            echo "ERROR: Installer database embedded" >&2
            exit 1
        }

        [[ -d /opt/gwn-defaults/data/mysql_default ]] || {
            echo "ERROR: mysql_default missing" >&2
            exit 1
        }

        [[ -s /opt/gwn-defaults/conf/gwn.conf ]] || {
            echo "ERROR: gwn.conf missing" >&2
            exit 1
        }

        [[ -s /opt/gwn-defaults/conf/gwn/local_env.cfg ]] || {
            echo "ERROR: local_env.cfg missing" >&2
            exit 1
        }

        [[ -x /usr/local/bin/configure-public-url ]] || {
            echo "ERROR: URL configuration script missing" >&2
            exit 1
        }

        [[ -x /usr/local/bin/pki-bootstrap ]] || {
            echo "ERROR: PKI bootstrap missing" >&2
            exit 1
        }
    '

# ------------------------------------------------------------
# Create dedicated volumes
# ------------------------------------------------------------

"$engine" volume create "$data" >/dev/null
"$engine" volume create "$conf" >/dev/null

# ------------------------------------------------------------
# Initialize empty volumes
# ------------------------------------------------------------

"$engine" run --rm \
    --entrypoint /bin/bash \
    -e GWN_ACCESS_ADDRESS \
    -e GWN_PUBLIC_HOST \
    -e GWN_PUBLIC_HTTPS_PORT \
    -v "$data:/gwn/data:z" \
    -v "$conf:/gwn/conf:z" \
    "$image" -euo pipefail -c '
        shopt -s nullglob dotglob

        d=(/gwn/data/*)
        c=(/gwn/conf/*)

        (( ${#d[@]} == 0 && ${#c[@]} == 0 )) || {
            echo "ERROR: Volumes are not empty" >&2
            exit 1
        }

        # Copy vendor defaults.
        cp -a /opt/gwn-defaults/data/. /gwn/data/
        cp -a /opt/gwn-defaults/conf/. /gwn/conf/

        # Initialize active MariaDB from vendor template.
        [[ -d /gwn/data/mysql_default ]] || {
            echo "ERROR: mysql_default missing" >&2
            exit 1
        }

        [[ ! -e /gwn/data/mysql ]] || {
            echo "ERROR: Active database already present" >&2
            exit 1
        }

        cp -a /gwn/data/mysql_default /gwn/data/mysql

        # Configure controller address and public web URL.
        /usr/local/bin/configure-public-url

        # Generate installation-specific PKI with public SAN.
        /usr/local/bin/pki-bootstrap --fresh

        # Preserve tested UID/GID conventions.
        chown -R 1000:1000 /gwn/data /gwn/conf
    '

# ------------------------------------------------------------
# Start GWN Manager
# ------------------------------------------------------------

"$engine" run -d \
    --name "$name" \
    -p "127.0.0.1:${port}:8443" \
    -v "$data:/gwn/data:z" \
    -v "$conf:/gwn/conf:z" \
    "$image"

echo
echo "Container: $name"
echo "Data volume: $data"
echo "Config volume: $conf"
echo
echo "Controller access address: $GWN_ACCESS_ADDRESS"
echo "Public hostname: $GWN_PUBLIC_HOST"
echo "Public HTTPS port: $GWN_PUBLIC_HTTPS_PORT"
echo
echo "Local HTTPS: https://localhost:$port"
echo
echo "Check services:"
echo "  $engine exec $name /gwn/gwn status"
echo
echo "Check health:"
echo "  $engine exec $name /usr/local/bin/healthcheck"
echo
echo "Inspect logs:"
echo "  $engine logs -f $name"
echo
echo "No automatic cleanup or publication."
