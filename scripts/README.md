# Scripts

Handy bash for the local flow. Paths are relative to the repo root so they work
on any clone, not only a specific container path.

| Script | What it does |
|--------|----------------|
| `workspace-up.sh` | start the tool container |
| `cluster-start.sh` | minikube profile `qoves` with Calico, ingress, metrics-server |
| `build-and-load-api.sh` | build `lokeshwarreddyyarava/qoves-api:v1.0.1` and load into minikube |
| `install-sealed-secrets.sh` | one-time Sealed Secrets controller install (bootstrap) |
| `seal-db-secret.sh` | write SealedSecret ciphertext (needs `POSTGRES_PASSWORD` in env) |
| `proof.sh` | dump inventory, Argo apps, curl via ingress, netpol test, PVC check |

```bash
docker compose -f docker/workspace/docker-compose.yml up -d --build
docker exec -it qoves-workspace bash
./scripts/cluster-start.sh
```

Seal (password only in your shell):

```bash
export POSTGRES_PASSWORD="$(openssl rand -base64 24)"
./scripts/seal-db-secret.sh
unset POSTGRES_PASSWORD
```

If the cluster is recreated, seal again — keys are per cluster.
