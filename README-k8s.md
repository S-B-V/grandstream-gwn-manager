# Kubernetes deployment

Deploy Grandstream GWN Manager in Kubernetes using the included StatefulSet manifest. The deployment uses persistent volumes for application data and configuration and exposes the application through a cluster-internal Service.

## Install

Check the image reference, storage requirements, and the public address settings in [`k8s/gwn-manager.yaml`](k8s/gwn-manager.yaml) before deployment. The supplied address settings target local access; set reachable addresses before connecting physical devices.

```sh
kubectl apply -f k8s/gwn-manager.yaml
kubectl -n gwn-manager get pods,pvc,svc
kubectl -n gwn-manager wait --for=condition=Ready pod/gwn-manager-0 --timeout=400s
```

## Open the web interface locally

```sh
kubectl -n gwn-manager port-forward svc/gwn-manager 18447:8443
```

Open `https://localhost:18447` in a browser. The initial certificate may be self-signed.

The default `ClusterIP` Service does not make the controller accessible to devices outside Kubernetes. Configure suitable external connectivity and the public controller address for device management.

## Check status

```sh
kubectl -n gwn-manager exec gwn-manager-0 -c gwn-manager -- /gwn/gwn status
kubectl -n gwn-manager logs gwn-manager-0 -c gwn-manager
```

## Update an installation

Update **both** container image references in `k8s/gwn-manager.yaml` to the intended published version, commit tag, or digest, then apply the manifest. The StatefulSet uses `OnDelete`, so it does not automatically replace an existing Pod.

```sh
kubectl apply -f k8s/gwn-manager.yaml
kubectl -n gwn-manager delete pod gwn-manager-0
kubectl -n gwn-manager wait --for=condition=Ready pod/gwn-manager-0 --timeout=400s
```

Back up the persistent volumes before an update. Do not delete the PVCs when replacing the Pod. Run only one replica with the supplied manifest.
