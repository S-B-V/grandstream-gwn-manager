#!/usr/bin/env bash
set -Eeuo pipefail

image="${1:-gwn-manager:installer-test}"
name="gwn-ci-${GITHUB_RUN_ID:-local}-$$"
data="${name}-data"
conf="${name}-conf"
container="${name}-app"

cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker volume rm "$data" "$conf" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

docker volume create "$data" >/dev/null
docker volume create "$conf" >/dev/null

# Mirror Kubernetes init container behavior: copy defaults only into empty volumes.
for kind in data conf; do
  volume="$data"; [[ "$kind" == conf ]] && volume="$conf"
  docker run --rm --entrypoint /bin/bash -v "$volume:/mnt/target" "$image" \
    -euo pipefail -c '
      shopt -s nullglob dotglob
      files=(/mnt/target/*)
      (( ${#files[@]} == 0 )) || { echo "Expected empty CI volume" >&2; exit 1; }
      cp -a "/opt/gwn-defaults/'"$kind"'/." /mnt/target/
      chown -R 1000:1000 /mnt/target
      test -d /mnt/target
    '
done

# Test data markers. They must survive container replacement and repeated init attempts.
docker run --rm --entrypoint /bin/bash -v "$data:/mnt/data" -v "$conf:/mnt/conf" "$image" \
  -euc 'echo persistent-data-marker > /mnt/data/.ci-persistence-marker; echo persistent-conf-marker > /mnt/conf/.ci-persistence-marker'

start() {
  docker run -d --name "$container" \
    -v "$data:/gwn/data" -v "$conf:/gwn/conf" \
    "$image" >/dev/null
  echo 'Checking application readiness (maximum 300 seconds)...'
  local i
  for i in $(seq 1 60); do
    if ! docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -qx true; then
      fail 'Container exited before readiness'
    fi
    if docker exec "$container" /usr/local/bin/healthcheck >/dev/null 2>&1; then
      echo 'Application healthcheck passed'
      return 0
    fi
    sleep 5
  done
  fail 'Application not healthy within 300 seconds'
}

stop() {
  echo 'Testing graceful shutdown...'
  # Docker will SIGKILL the container when the vendor stop exceeds the timeout.
  docker stop --time 90 "$container" >/dev/null || fail 'docker stop failed'
  local code
  code="$(docker inspect -f '{{.State.ExitCode}}' "$container")"
  [[ "$code" == 0 ]] || fail "Container exit code was $code (expected 0)"
  docker logs "$container" 2>&1 | grep -q 'GWN Manager: vendor shutdown finished' || fail 'Vendor shutdown confirmation missing'
  echo 'Graceful shutdown passed'
  docker rm "$container" >/dev/null
}

start
stop

# Repeat Kubernetes initialization for existing volumes: the marker remains untouched.
for kind in data conf; do
  volume="$data"; [[ "$kind" == conf ]] && volume="$conf"
  docker run --rm --entrypoint /bin/bash -v "$volume:/mnt/target" "$image" \
    -euo pipefail -c '
      shopt -s nullglob dotglob
      files=(/mnt/target/*)
      if (( ${#files[@]} == 0 )); then
        echo "ERROR: previous volume contents vanished" >&2; exit 1
      fi
      test "$(cat /mnt/target/.ci-persistence-marker)" = "persistent-'"$kind"'-marker"
    '
done

start
# Validate retained configuration and data after re-creating the container.
docker exec "$container" /bin/bash -euc '
  [[ "$(cat /gwn/data/.ci-persistence-marker)" == persistent-data-marker ]]
  [[ "$(cat /gwn/conf/.ci-persistence-marker)" == persistent-conf-marker ]]
  [[ -d /gwn/data/mysql/data ]]
  [[ -f /gwn/conf/gwn.conf ]]
'
stop

echo 'PASS: fresh volume bootstrap, runtime readiness, shutdown and persistence recreation'
