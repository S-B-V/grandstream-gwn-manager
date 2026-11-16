# Kubernetes deployment

This repository includes the original standalone `k8s/gwn-manager.yaml` manifest and a separate, vendor-neutral Gateway API example in [`k8s/gateway-api-example/`](k8s/gateway-api-example/).

- The standalone manifest provides a single GWN Manager StatefulSet with PVCs and the vendor's local PKI bootstrap.
- The Gateway API example adds a device-facing LoadBalancer, a GUI-only ClusterIP Service, a Gateway, HTTPRoutes for HTTPS and HTTP-to-HTTPS redirect, a BackendTLSPolicy, two cert-manager Certificates, and a trust-manager Bundle for the issuer's public CA.
- The example uses `gwn.localhost.local` for physical devices and backend TLS, and `gwn-ui.localhost.local` for browser GUI access. Replace the documented GatewayClass/Issuer/CA and load-balancer address placeholders.

See the example README for prerequisites, lifecycle details and renewal limitations. The backup `emptyDir` requires the updated runtime image from the fix package for predictable permissions.

## Temporary local backup directory

Both StatefulSets mount a disk-backed Kubernetes `emptyDir` named `backup` at `/gwn_backup` in the GWN application container, with `sizeLimit: 2Gi`. The GWN application uses this directory when creating backups. No additional PVC is needed; the existing `data` (10Gi) and `conf` (2Gi) PVCs remain unchanged. The `emptyDir` and mount are already present in `k8s/gwn-manager.yaml` and `k8s/gateway-api-example/statefulset.yaml`; no helper script is needed.

The image entrypoint prepares `/gwn_backup` with UID/GID 1000 and mode `0770`. `emptyDir` persists across container restarts in an unchanged Pod, **but is deleted when the Pod is deleted/recreated**, moved to another node, or otherwise replaced. Do not use it as long-term backup retention. Download backups or transfer them to external storage before pod replacement; avoid unattended scheduled backups without an off-cluster copy mechanism. The 2Gi limit consumes node ephemeral storage and can lead to write failures or eviction if exhausted.

No new storage claim is created and no immutable `volumeClaimTemplates` field is changed. The StatefulSets use `OnDelete`; applying a Pod-template update alone does not replace the running Pod.
