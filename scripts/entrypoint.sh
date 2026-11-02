#!/usr/bin/env bash
set -Eeuo pipefail

stopping=0
child_pid=""

shutdown() {
    local exit_code="${1:-0}"
    if (( stopping )); then
        return
    fi
    stopping=1
    trap - TERM INT
    echo 'GWN Manager: shutdown requested' >&2
    if [[ -n "$child_pid" ]]; then
        kill "$child_pid" 2>/dev/null || true
        wait "$child_pid" 2>/dev/null || true
    fi
    # Limit vendor shutdown time so that a hung service cannot block forever.
    if ! timeout --signal=TERM --kill-after=5s 45s /gwn/gwn stop; then
        echo 'GWN Manager: vendor shutdown returned an error or timed out' >&2
        exit 1
    fi
    echo 'GWN Manager: vendor shutdown finished' >&2
    exit "$exit_code"
}
trap shutdown TERM INT

# The vendor launcher starts background services and returns.
echo 'GWN Manager: starting vendor services' >&2
/gwn/gwn start

echo 'GWN Manager: waiting for readiness (up to 180 seconds)' >&2
ready=0
for (( i=0; i<18; i++ )); do
    if /usr/local/bin/healthcheck; then
        ready=1
        break
    fi
    sleep 10 & child_pid=$!
    wait "$child_pid" || true
    child_pid=""
done
if (( ! ready )); then
    echo 'GWN Manager: services did not become healthy in 180 seconds' >&2
    shutdown 1
fi

echo 'GWN Manager: healthy; monitoring services' >&2
failures=0
while true; do
    sleep 10 & child_pid=$!
    wait "$child_pid" || true
    child_pid=""
    if /usr/local/bin/healthcheck; then
        failures=0
    else
        (( failures+=1 ))
        echo "GWN Manager: failed health checks: $failures/3" >&2
        if (( failures >= 3 )); then
            echo 'GWN Manager: persistent health failure; stopping services' >&2
            shutdown 1
        fi
    fi
done
