# Namespaces

- `qoves-app` — API, Postgres, app NetworkPolicies, sealed secret materialization
- `qoves-platform` — Prometheus

Argo CD itself is installed into `argocd` (bootstrap). Sealed Secrets controller
lives in `kube-system`. Ingress is the minikube addon (`ingress-nginx`).
