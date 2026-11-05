#!/usr/bin/env bash
set -Eeuo pipefail
child=''; stopping=0
shutdown(){
  (( stopping == 0 )) || return 0
  stopping=1; trap - TERM INT
  [[ -z "$child" ]] || { kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; }
  timeout --signal=TERM --kill-after=5s 45s /gwn/gwn stop || true
  exit "${1:-0}"
}
trap 'shutdown 0' TERM INT
[[ -s /gwn/conf/gwn.conf ]] || { echo 'Config volume not initialized' >&2; exit 1; }
[[ -e /gwn/data/.pki-bootstrap-complete ]] || { echo 'PKI not bootstrapped' >&2; exit 1; }
/gwn/gwn start || shutdown 1
for ((i=0;i<30;i++)); do
  if /usr/local/bin/healthcheck; then break; fi
  sleep 10 & child=$!; wait "$child" || true; child=''
  if (( i==29 )); then shutdown 1; fi
done
fail=0
while :; do
  sleep 10 & child=$!; wait "$child" || true; child=''
  if /usr/local/bin/healthcheck; then fail=0; else ((fail+=1)); ((fail<3)) || shutdown 1; fi
done
