# Kubernetes deployment

This repository includes the original standalone `k8s/gwn-manager.yaml` manifest and a separate, vendor-neutral Gateway API example in [`k8s/gateway-api-example/`](k8s/gateway-api-example/).

- The standalone manifest provides a single GWN Manager StatefulSet with PVCs and the vendor's local PKI bootstrap.
- The Gateway API example adds a device-facing LoadBalancer, a GUI-only ClusterIP Service, a Gateway, HTTPRoutes for HTTPS and HTTP-to-HTTPS redirect, a BackendTLSPolicy, two cert-manager Certificates, and a trust-manager Bundle for the issuer's public CA.
- The example uses `gwn.localhost.local` for physical devices and backend TLS, and `gwn-ui.localhost.local` for browser GUI access. Replace the documented GatewayClass/Issuer/CA and load-balancer address placeholders.

See the example README for prerequisites, lifecycle details and renewal limitations. These are Kubernetes manifests only; the container image build is unchanged.
