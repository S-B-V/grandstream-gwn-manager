#!/bin/bash
# Match the vendor's 4 GiB host profile even when /proc/meminfo shows VM RAM.
# Four JVM heaps share the limit with native memory, Node, and MariaDB.
set -euo pipefail
args=()
for arg in "$@"; do
  case "$arg" in
    -Xmx*|-Xms*) ;;
    *) args+=("$arg") ;;
  esac
done
exec /gwn/bin/jre/bin/java -Xms64m -Xmx512m "${args[@]}"
