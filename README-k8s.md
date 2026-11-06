# Kubernetes proof-of-concept (not production ready)

The image comes from the **official** GWN Manager installer. The pod has a single replica. `OnDelete` avoids surprise controller upgrades. Startup, readiness and liveness use the existing healthcheck.

**Do not deploy as-is:** review the automatic GHCR release setup in `README-ci.md`, verify the image tag or digest, and ensure controller IP and device traffic ports/protocols must be reviewed, credentials must be rotated, and security/redistribution rights must be reviewed. The vendor services' capability to run without root has not been validated. This manifest intentionally does not declare non-root compatibility. The image runs with the default vendor permissions; init containers require UID 0 to set ownership. Harden once validated.

The init container populates *truly empty* PVCs from `/opt/gwn-defaults/{data,conf}` in the same image. It preserves existing initialized data and certificates, and refuses partially initialized volumes. On every startup it installs the Java memory launcher and sets `java_bin` in `gwn.conf` as described below. Take backups before any migration. The `fsGroup` may be modified by the CSI implementation. The application owns `/gwn/data` and `/gwn/conf` (vendor UID 1000).

Before applying, choose storage class/size and immutable image digest, review Service ports and the device-access networking (ClusterIP alone does **not** expose the controller to devices). `8000/tcp` is listed only because the local launcher advertised it; all required UDP ports still need verification. An externally reachable controller address must be configured using a supported vendor mechanism.

Deploy only after the image is made available in a registry you control:

```sh
kubectl apply -f k8s/gwn-manager.yaml
kubectl -n gwn-manager get pods,pvc,svc
kubectl -n gwn-manager logs gwn-manager-0 -c initialize-pvcs-and-pki
kubectl -n gwn-manager logs gwn-manager-0 -c gwn-manager
```

## Memory budget and updating an existing deployment

The container retains its **4 GiB** memory limit. Grandstream's service scripts
read `/proc/meminfo` to select heap sizes. In a container this can show the VM's
RAM instead of the container limit; on the observed 12 GiB VM, all four JVMs
started without the vendor's intended 512 MiB heap caps for a 4 GiB machine.

The manifest includes the `gwn-java-memory` ConfigMap. After successful fresh
bootstrap or validation of existing initialized PVCs, the init container copies
its launcher to `/gwn/conf/java-memory-limited` and sets the vendor's `java_bin`
configuration to that path. Each JVM starts with a **64 MiB initial heap and a
512 MiB maximum heap**, leaving the remainder for Java native memory, Node,
MariaDB, Redis, and nginx. These are heap limits, not limits on each process's
total resident memory. Container-level JVM environment variables are insufficient
because the vendor uses login shells to start its services.

The launcher removes pre-existing `-Xms` and `-Xmx` arguments and preserves all
other arguments. Initialization is repeatable and does not reinitialize the
database or PKI. Before first changing `java_bin`, the init container saves
`/gwn/conf/gwn.conf.before-memory-profile` with mode 0600, unless that backup
already exists. Its ConfigMap source is mounted only in the init container;
the executable on the configuration PVC is available to the main container.
No image rebuild is needed for this manifest change.

The StatefulSet uses `OnDelete`: applying the manifest alone does **not** replace
the running pod. To activate this change, allow a brief application interruption:

```sh
kubectl apply -f k8s/gwn-manager.yaml
kubectl -n gwn-manager delete pod gwn-manager-0
# Wait for the replacement pod to appear, then:
kubectl -n gwn-manager wait --for=condition=Ready pod/gwn-manager-0 --timeout=400s
kubectl -n gwn-manager top pod gwn-manager-0 --containers
```

Keep both PVCs. Subsequent ConfigMap changes also require pod replacement so the
init container installs the revised launcher. For a rollback, revert the manifest's
ConfigMap/init changes and restore the previous `java_bin` value from the backup;
restoring only the PVC configuration will be overwritten by the next init run.

The equivalent live fix was checked on version 1.1.39.8: all services healthy,
HTTPS returned 200, and startup memory was about 2.5 GiB with no OOM events in
that observation. This is not a 200-device capacity test or a guarantee against
OOM under load. Monitor actual usage, restarts, and Java out-of-memory logs.

**Validation:** start from fresh PVCs; verify all vendor services, HTTPS *and* authenticated application functionality; write a canary setting in the UI; delete the Pod (not the PVC or StatefulSet claims); verify the setting persists; gracefully terminate while watching DB logs; test restore from backup. Do not scale above one replica without vendor support and suitable storage/database architecture.
