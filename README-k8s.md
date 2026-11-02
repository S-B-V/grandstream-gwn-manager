# Kubernetes proof-of-concept (not production ready)

The image comes from the **official** GWN Manager installer. The pod has a single replica. `OnDelete` avoids surprise controller upgrades. Startup, readiness and liveness use the existing healthcheck.

**Do not deploy as-is:** GHCR publishing has not been enabled, the image tag is a placeholder until a verified release exists, controller IP and device traffic ports/protocols must be reviewed, credentials must be rotated, and security/redistribution rights must be reviewed. The vendor services' capability to run without root has not been validated. This manifest intentionally does not declare non-root compatibility. The image runs with the default vendor permissions; init containers require UID 0 to set ownership. Harden once validated.

The init containers populate *truly empty* PVCs from `/opt/gwn-defaults/{data,conf}` in the same image. If a PVC is non-empty, it is left untouched, including partially initialized volumes: inspect those manually before restart. Take backups before any migration. The `fsGroup` may be modified by the CSI implementation. The application owns `/gwn/data` and `/gwn/conf` (vendor UID 1000).

Before applying, choose storage class/size and immutable image digest, review Service ports and the device-access networking (ClusterIP alone does **not** expose the controller to devices). `8000/tcp` is listed only because the local launcher advertised it; all required UDP ports still need verification. An externally reachable controller address must be configured using a supported vendor mechanism.

Deploy only after the image is made available in a registry you control:

```sh
kubectl apply -f k8s/gwn-manager.yaml
kubectl -n gwn-manager get pods,pvc,svc
kubectl -n gwn-manager logs gwn-manager-0 -c init-data
kubectl -n gwn-manager logs gwn-manager-0 -c init-conf
kubectl -n gwn-manager logs gwn-manager-0 -c gwn-manager
```

**Validation:** start from fresh PVCs; verify all vendor services, HTTPS *and* authenticated application functionality; write a canary setting in the UI; delete the Pod (not the PVC or StatefulSet claims); verify the setting persists; gracefully terminate while watching DB logs; test restore from backup. Do not scale above one replica without vendor support and suitable storage/database architecture.
