#!/usr/bin/env bash
set -Eeuo pipefail

# Ephemeral GitHub Actions Docker test. Never use this against named local volumes.
image="${1:-gwn-manager:installer-test}"
name="gwn-ci-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
data="${name}-data"
conf="${name}-conf"
container="${name}-app"

# Explicitly tested local controller address (vendor rejects localhost here).
export GWN_ACCESS_ADDRESS=127.0.0.1
export GWN_PUBLIC_HOST=localhost
export GWN_PUBLIC_HTTPS_PORT=18447

created_data=0
created_conf=0
created_container=0
cleanup() {
  (( created_container == 0 )) || docker rm -f "$container" >/dev/null 2>&1 || true
  (( created_data == 0 )) || docker volume rm "$data" >/dev/null 2>&1 || true
  (( created_conf == 0 )) || docker volume rm "$conf" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Avoid colliding with existing resources, including unexpected CI leftovers.
if docker container inspect "$container" >/dev/null 2>&1; then
  fail "Container already exists: $container"
fi
for volume in "$data" "$conf"; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    fail "Volume already exists: $volume"
  fi
done

docker volume create "$data" >/dev/null
created_data=1
docker volume create "$conf" >/dev/null
created_conf=1

# Same initialization order as the locally verified test-clean-local.sh:
# defaults -> mysql_default copy -> URL configuration -> PKI -> ownership.
docker run --rm --entrypoint /bin/bash \
  -e GWN_ACCESS_ADDRESS -e GWN_PUBLIC_HOST -e GWN_PUBLIC_HTTPS_PORT \
  -v "$data:/gwn/data" -v "$conf:/gwn/conf" \
  "$image" -euo pipefail -c '
    shopt -s nullglob dotglob
    d=(/gwn/data/*)
    c=(/gwn/conf/*)
    (( ${#d[@]} == 0 && ${#c[@]} == 0 )) || {
      echo "Expected empty CI volumes" >&2; exit 1;
    }
    test ! -e /opt/gwn-defaults/data/mysql
    test -d /opt/gwn-defaults/data/mysql_default/data
    cp -a /opt/gwn-defaults/data/. /gwn/data/
    cp -a /opt/gwn-defaults/conf/. /gwn/conf/
    test ! -e /gwn/data/mysql
    cp -a /gwn/data/mysql_default /gwn/data/mysql
    /usr/local/bin/configure-public-url
    /usr/local/bin/pki-bootstrap --fresh
    chown -R 1000:1000 /gwn/data /gwn/conf
    test -d /gwn/data/mysql/data
    test -s /gwn/conf/nginx/ssl.pem
    test -e /gwn/data/.pki-bootstrap-complete
  '

# Persistent state must not change across container replacement.
docker run --rm --entrypoint /bin/bash \
  -v "$data:/gwn/data" -v "$conf:/gwn/conf" \
  "$image" -euc '
    printf %s persistent-data-marker > /gwn/data/.ci-persistence-marker
    printf %s persistent-conf-marker > /gwn/conf/.ci-persistence-marker
  '

fingerprint() {
  docker run --rm --entrypoint /bin/bash -v "$conf:/gwn/conf:ro" \
    "$image" -euc '
      openssl x509 -in /gwn/conf/nginx/ssl.pem -noout -fingerprint -sha256
    '
}
original_fingerprint="$(fingerprint)"
[[ -n "$original_fingerprint" ]] || fail 'Missing initial certificate fingerprint'

start() {
  docker run -d --name "$container" --memory=4g --memory-swap=4g \
    -p "127.0.0.1:${GWN_PUBLIC_HTTPS_PORT}:8443" \
    -v "$data:/gwn/data" -v "$conf:/gwn/conf" \
    "$image" >/dev/null
  created_container=1

  echo 'Checking application readiness (maximum 300 seconds)...'
  local i
  for i in $(seq 1 60); do
    if [[ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)" != true ]]; then
      docker logs --tail 60 "$container" >&2 || true
      fail 'Container exited before readiness'
    fi
    if docker exec "$container" /usr/local/bin/healthcheck >/dev/null 2>&1; then
      docker exec "$container" /bin/bash -euc '
        count=$(ps -eo args | grep -c "^/gwn/bin/jre/bin/java -Xms64m -Xmx512m " || true)
        [[ "$count" == 4 ]]
      '
      echo 'Application healthcheck and four JVM heap caps passed' 
      return 0
    fi
    sleep 5
  done
  docker logs --tail 60 "$container" >&2 || true
  fail 'Application not healthy within 300 seconds'
}

stop() {
  echo 'Testing graceful shutdown...'
  docker stop --time 90 "$container" >/dev/null || fail 'docker stop failed'
  local code running oom
  code="$(docker inspect -f '{{.State.ExitCode}}' "$container")"
  running="$(docker inspect -f '{{.State.Running}}' "$container")"
  oom="$(docker inspect -f '{{.State.OOMKilled}}' "$container")"
  [[ "$code" == 0 && "$running" == false && "$oom" == false ]] || {
    fail "Unexpected shutdown state: exit=$code running=$running"
  }
  echo 'Graceful shutdown passed'
  docker rm "$container" >/dev/null
  created_container=0
}

verify_persistence() {
  docker run --rm --entrypoint /bin/bash \
    -v "$data:/gwn/data:ro" -v "$conf:/gwn/conf:ro" \
    "$image" -euc '
      [[ "$(cat /gwn/data/.ci-persistence-marker)" == persistent-data-marker ]]
      [[ "$(cat /gwn/conf/.ci-persistence-marker)" == persistent-conf-marker ]]
      [[ -d /gwn/data/mysql/data ]]
      [[ -s /gwn/conf/gwn.conf ]]
      [[ -e /gwn/data/.pki-bootstrap-complete ]]
      [[ -s /gwn/conf/nginx/ssl.pem ]]
    '
  [[ "$(fingerprint)" == "$original_fingerprint" ]] || fail 'TLS certificate changed'
}

start
verify_persistence
stop
verify_persistence

# Simulate idempotent init-container handling of existing persistent volumes.
# It must not rerun URL or PKI generation or replace active database state.
docker run --rm --entrypoint /bin/bash \
  -v "$data:/gwn/data:ro" -v "$conf:/gwn/conf:ro" \
  "$image" -euc '
    [[ -e /gwn/data/.pki-bootstrap-complete ]]
    [[ -d /gwn/data/mysql/data ]]
    [[ -s /gwn/conf/gwn.conf ]]
  '

start
verify_persistence
stop
verify_persistence

echo 'PASS: fresh DB and PKI bootstrap, readiness, graceful shutdown, recreation and TLS persistence'
