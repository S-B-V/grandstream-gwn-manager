#!/usr/bin/env bash
set -euo pipefail
status=$(/gwn/gwn status 2>&1) || exit 1
for service in Redis Mysql Nginx User router Email Gateway Link Web Checker; do
  printf '%s\n' "$status" | grep -Eiq "^${service} .*is running" || { echo "Unhealthy service: $service" >&2; exit 1; }
done
curl -kfsS --max-time 5 -o /dev/null https://127.0.0.1:8443/
