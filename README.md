# QOVES take-home (minikube)

Public GitOps repo for the QOVES platform exercise.

https://github.com/Lokeshwar-Reddy-Yarava/qoves-devops-assignment

**Writeup (full detail):** [docs/WRITEUP.md](docs/WRITEUP.md)

Small API plus the platform around it: Calico, Argo CD app-of-apps, Postgres + PVC,
Sealed Secrets, default-deny netpol, ingress, HPA, Prometheus + one alert.

## Architecture overview

```text
  You: git commit + push
           │
           ▼
  GitHub repo (source of truth)
           │
           │  Argo CD reconciles (app-of-apps)
           ▼
  minikube (Calico — NetworkPolicy enforced)
  ─────────────────────────────────────────────
  User/curl → Ingress → API (Deployment)
                           │  DATABASE_URL from Secret
                           ▼
                        Postgres (StatefulSet + PVC)

  Sealed Secrets → materializes Secret in qoves-app
  Prometheus (qoves-platform) scrapes qoves-api Service in qoves-app
  metrics-server → HPA scales the API
  App namespace: default-deny; only explicit paths allowed
```

Detail (decisions, storage, runbook, production gaps) is in the writeup.

## Layout

```
app/                 API (main.py, requirements.txt, Dockerfile)
gitops/clusters/     Argo root + child Applications
gitops/manifests/    cluster desired state
docs/WRITEUP.md      how I run it, choices, gaps, runbook
scripts/             start cluster, build image, seal secret, proof
docker/workspace/    optional tool container
```

## App

I kept the three endpoints from the brief. Implementation is FastAPI; the
contract is the same.

| Path | What it does |
|------|----------------|
| `GET /` | hello |
| `GET /healthz` | `SELECT 1` on Postgres → 200 or 503 |
| `GET /metrics` | Prometheus metrics |

`DATABASE_URL` comes from the environment at runtime (Kubernetes Secret). Nothing
DB-related is hard-coded in the app.

Image tag used in cluster: `lokeshwarreddyyarava/qoves-api:v1.0.1` (no floating tags).

```bash
docker build -t lokeshwarreddyyarava/qoves-api:v1.0.1 ./app
# or: ./scripts/build-and-load-api.sh  (also loads into minikube)
```

## Bring-up (short version)

Longer notes and assumptions are in the writeup.

```bash
docker compose -f docker/workspace/docker-compose.yml up -d --build   # optional
docker exec -it qoves-workspace bash                                   # optional

./scripts/cluster-start.sh
./scripts/build-and-load-api.sh

kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.3/manifests/install.yaml
./scripts/install-sealed-secrets.sh   # controller once; SealedSecrets stay in GitOps
kubectl apply -f gitops/clusters/minikube/root-application.yaml

export POSTGRES_PASSWORD="$(openssl rand -base64 24)"
./scripts/seal-db-secret.sh
# commit + push only the SealedSecret yaml
unset POSTGRES_PASSWORD

curl -i -H 'Host: qoves.local' "http://$(minikube ip -p qoves)/"
curl -i -H 'Host: qoves.local' "http://$(minikube ip -p qoves)/healthz"
curl -i -H 'Host: qoves.local' "http://$(minikube ip -p qoves)/metrics"

./scripts/proof.sh
```

After bootstrap, deliver changes by editing `gitops/manifests/`, committing, and
pushing. Argo reconciles. App install is not a manual `kubectl apply` loop.

## Mapping to the brief

| Part | Where |
|------|--------|
| A CNI | Calico via `scripts/cluster-start.sh` |
| B GitOps | `gitops/clusters/minikube/` |
| C App + DB | `gitops/manifests/app/` |
| D Network + ingress | netpol + ingress host `qoves.local` |
| E Secrets | Sealed Secrets under `gitops/manifests/app/secrets/` |
| F Storage | PVC + writeup Decisions → Storage |
| G resources / HPA | requests/limits + HPA in `api.yaml` |
| H metrics / alert | `platform/prometheus` |

## Contact

Take-home only. Re-seal after recreating the cluster. Do not put real cloud
passwords or tokens in this repo.
