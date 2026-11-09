# Vendor-neutral Kubernetes Gateway API example

Copy this directory into your manifests tree. The examples use `.localhost.local` DNS names and intentional placeholders; they do **not** depend on Airlock products.

## Replace before applying

1. Set `REPLACE_CLUSTER_ISSUER` to your cert-manager `ClusterIssuer`, or create an appropriate issuer.
2. Set `REPLACE_GATEWAY_CLASS` in `gateway.yaml` to your installed `GatewayClass`. If you already have a Gateway, omit `gateway.yaml` from `kustomization.yaml` and update both HTTPRoute `parentRefs`.
3. Set `REPLACE_CA_SECRET_IN_TRUST_NAMESPACE` to an issuer CA Secret in the trust-manager trust namespace (the public CA PEM must be present as `tls.crt`), or replace `backend-ca-bundle.yaml` with a pre-existing, declaratively provisioned `ConfigMap/gwn-manager-backend-ca` containing key `ca.crt`.
4. Replace example LoadBalancer address `192.0.2.15` with a real address and your load-balancer-specific IP allocation configuration. The address is documentation-only (TEST-NET-1).
5. Configure `gwn-ui.localhost.local` to resolve to your Gateway and `gwn.localhost.local` to the device LoadBalancer address (adjust DNS and firewall rules).
6. Adjust resource requests and storageClass to your cluster.

The GWN Manager image version is `1.1.39.8`. This example is designed for an already installed cert-manager, Gateway API CRDs, and optionally trust-manager. The existing internal vendor PKI is initialized as before; for web TLS, the init container changes the GWN TLS paths to a Secret-projected keypair. No new proxy or container build change is needed.

The browser authenticates `gwn-ui.localhost.local` at the Gateway; the Gateway separately authenticates `gwn.localhost.local` on the backend using `BackendTLSPolicy`. HTTP requests are redirected to HTTPS using a distinct HTTPRoute.

**Important lifecycle:** The StatefulSet is single-replica and uses `OnDelete`. Certificate Secret rotation may require a controlled Pod restart for the embedded NGINX server to load the changed certificate. Backup PVCs before upgrades; do not delete them. For existing StatefulSets, `spec.serviceName` can be immutable.

**Not verified against a running cluster.** Confirm support for BackendTLSPolicy and the host-header/redirect behavior of GWN Manager.
