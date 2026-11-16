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

# GWN Manager writes manual backups to /gwn_backup.
# In Kubernetes this is a pod-scoped emptyDir, not the data PVC.
# An emptyDir starts owned by root; allow the vendor's UID 1000 to write.
[[ -d /gwn_backup && ! -L /gwn_backup ]] || {
  echo 'Backup path /gwn_backup must be a directory, not a symlink' >&2; exit 1;
}
chown 1000:1000 /gwn_backup
chmod 0770 /gwn_backup
runuser -u gwn -- test -w /gwn_backup || {
  echo 'Backup destination /gwn_backup is not writable by gwn' >&2; exit 1;
}

# Service login shells discard container JVM environment variables.
grep -q '^java_bin=' /gwn/conf/gwn.conf
if ! grep -qx 'java_bin=/gwn/conf/java-memory-limited' /gwn/conf/gwn.conf; then
  if [[ ! -e /gwn/conf/gwn.conf.before-memory-profile ]]; then
    cp -p /gwn/conf/gwn.conf /gwn/conf/gwn.conf.before-memory-profile
    chmod 600 /gwn/conf/gwn.conf.before-memory-profile
  fi
fi
install -o 1000 -g 1000 -m 0755 /usr/local/bin/gwn-java-memory /gwn/conf/java-memory-limited
sed -i 's|^java_bin=.*|java_bin=/gwn/conf/java-memory-limited|' /gwn/conf/gwn.conf
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
