
#!/usr/bin/env bash
set -Eeuo pipefail

image=${1:-localhost/gwn-manager:secure-test}
engine=${ENGINE:-podman}

name=gwn-mysql-default-test
data=gwn-mysql-default-test-data
conf=gwn-mysql-default-test-conf

# Never overwrite an existing test container or volume.
if "$engine" container exists "$name"; then
  echo "Container already exists: $name" >&2
  exit 1
fi

for volume in "$data" "$conf"; do
  if "$engine" volume exists "$volume"; then
    echo "Volume already exists: $volume" >&2
    exit 1
  fi
done

"$engine" volume create "$data" >/dev/null
"$engine" volume create "$conf" >/dev/null

# Initialize fresh volumes.
"$engine" run --rm \
  --entrypoint /bin/bash \
  -v "$data:/gwn/data:z" \
  -v "$conf:/gwn/conf:z" \
  "$image" -euo pipefail -c '
    shopt -s nullglob dotglob

    d=(/gwn/data/*)
    c=(/gwn/conf/*)

    (( ${#d[@]} == 0 && ${#c[@]} == 0 )) || {
      echo "Volumes not empty; refusing" >&2
      exit 1
    }

    cp -a /opt/gwn-defaults/data/. /gwn/data/
    cp -a /opt/gwn-defaults/conf/. /gwn/conf/

    # Do not use the installer-generated active database.
    rm -rf /gwn/data/mysql

    # Initialize active database from vendor default template.
    cp -a /gwn/data/mysql_default /gwn/data/mysql

    /usr/local/bin/pki-bootstrap --fresh

    chown -R 1000:1000 /gwn/data /gwn/conf
  '

# Start isolated test container.
"$engine" run -d \
  --name "$name" \
  -p 18444:8443 \
  -v "$data:/gwn/data:z" \
  -v "$conf:/gwn/conf:z" \
  "$image"

echo "Container: $name"
echo "HTTPS: https://localhost:18444"
echo "Logs: $engine logs -f $name"

