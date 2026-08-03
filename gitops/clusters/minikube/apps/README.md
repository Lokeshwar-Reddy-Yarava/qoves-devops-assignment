# Child Applications

Root Application syncs this folder. Each file is one Argo app:

| App | Path |
|-----|------|
| namespaces | gitops/manifests/namespaces |
| platform-sealed-secrets | gitops/manifests/platform/sealed-secrets |
| platform-prometheus | gitops/manifests/platform/prometheus |
| app-secrets | gitops/manifests/app/secrets |
| app-postgres | gitops/manifests/app/postgres |
| app-api | gitops/manifests/app/base |

After the root is applied, I change things under `gitops/manifests/`, not by
kubectl apply-ing the workloads as day-to-day delivery.
