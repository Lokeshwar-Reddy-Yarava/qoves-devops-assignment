# Writeup — QOVES take-home

Repo: https://github.com/Lokeshwar-Reddy-Yarava/qoves-devops-assignment

I built a small platform around a trivial API: minikube + Calico, Argo CD
app-of-apps, Postgres with a PVC, Sealed Secrets, default-deny NetworkPolicies,
ingress, HPA, and a small Prometheus setup with one alert.

I stuck to the core path instead of stacking stretch goals. A few deliberate
shortcuts are called out below.

For a short architecture sketch see [README.md](../README.md). This file is the
detailed walkthrough.

---

## 1. How to run it

I used the optional Docker workspace so tools stay consistent on Windows/WSL.
Any host with Docker, minikube, kubectl, and kubeseal works the same way.

### From zero

```bash
# optional workspace
docker compose -f docker/workspace/docker-compose.yml up -d --build
docker exec -it qoves-workspace bash

./scripts/cluster-start.sh
./scripts/build-and-load-api.sh   # lokeshwarreddyyarava/qoves-api:v1.0.1

kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.3/manifests/install.yaml

kubectl apply -f gitops/clusters/minikube/root-application.yaml
```

First sync order is not strict. The Argo child apps (namespaces, sealed-secrets,
secrets, postgres, api, prometheus) reconcile in parallel. Until I seal
credentials and push the SealedSecret, `app-api` can sit in
CreateContainerConfigError waiting for Secret `qoves-db`. That is expected;
selfHeal picks it up once the secret materializes.

After Sealed Secrets is up, seal against **this** cluster. The password stays in
my shell only:

```bash
export POSTGRES_PASSWORD="$(openssl rand -base64 24)"
./scripts/seal-db-secret.sh
git add gitops/manifests/app/secrets/qoves-db.sealedsecret.yaml
git commit -m "Add sealed DB credentials"
git push
unset POSTGRES_PASSWORD
```

Hit the app through ingress (not port-forward):

```bash
curl -i -H 'Host: qoves.local' "http://$(minikube ip -p qoves)/"
curl -i -H 'Host: qoves.local' "http://$(minikube ip -p qoves)/healthz"
curl -i -H 'Host: qoves.local' "http://$(minikube ip -p qoves)/metrics"
```

Proof dump for reviewers:

```bash
./scripts/proof.sh
```

### Layout

```
app/                  API
gitops/clusters/      Argo root + child apps
gitops/manifests/     what lands in the cluster
docs/WRITEUP.md       this file
scripts/              bootstrap + seal + proof
docker/workspace/     optional tool container
```

### Changing something the GitOps way

Edit under `gitops/manifests/`, commit, push. Argo runs automated sync + selfHeal.
I do not hand-edit Deployments as the permanent state.

Example: change HPA `averageUtilization` in
`gitops/manifests/app/base/api.yaml`, push, then
`kubectl -n qoves-app get hpa`.

This is a **single-node** minikube profile (`qoves`). Fine for the exercise; not HA.

If I recreate the cluster, old SealedSecret ciphertext does not decrypt. I reseal
and push again.

---

## 2. Decisions

**Calico.** I needed NetworkPolicy that actually works. minikube's default CNI
does not enforce policies, so part D would have been fake. Calico is what the
brief hints at and is easy to walk through. Cilium would also work; I did not need
extra eBPF features here.

**Argo CD app-of-apps.** The root Application points at
`gitops/clusters/minikube/apps/`, and each child owns one directory under
`manifests/`. That matches the brief and is easy to show in a review. Flux would
do the same job; I already know Argo's Application model well enough for a short
call.

**Sealed Secrets.** Goal: credentials never land in git as plaintext or base64.
Sealed Secrets is the simplest fully local option. I rejected a Secret YAML in
git. SOPS needs an Argo plugin. External Secrets only makes sense with a real
backend (Vault / cloud SM), not a fake provider that puts the value back in a
manifest. Day two I would hang External Secrets off Vault or cloud SM and rotate.

The seal script fails if `POSTGRES_PASSWORD` is missing from the environment. I
do not want a default password string sitting in the repo.

**Postgres as a raw StatefulSet.** Enough to talk about PVC, identity, and restarts
without an operator first. CloudNativePG is better later for HA and backup; I left
it as follow-up work.

**NetworkPolicy.** Default deny ingress + egress in `qoves-app`, then only what the
diagram needs: ingress-nginx to the API, API egress to Postgres and Postgres
ingress from API (established return traffic is allowed automatically), DNS to
kube-system, and Prometheus in `qoves-platform` scraping the API.
`scripts/proof.sh` checks it (DNS works, random egress and random-pod→Postgres
fail, API health still OK).

### Storage decision

**Access mode is ReadWriteOnce.** One node mounts the volume read-write at a time.
That limits where `postgres-0` can schedule (it follows the volume). You cannot run
multiple writers on the same claim.

**Pod dies:** StatefulSet brings `postgres-0` back with the same PVC. Data stays.
I check this in `proof.sh` with a small table and a row called `survives-restart`.

**Node dies:** on this minikube setup the volume is tied to that node. Lose the
node and you restore from backup. On cloud CSI you can usually reattach after the
old attachment is gone, but Postgres is still down until Ready.

**Backup / restore in real life:** scheduled logical dumps or continuous backup to
object storage (encrypted), plus occasional volume snapshots. Restore path: new
claim → restore → start Postgres → point the app via git → verify `/healthz` and
app checks. A PVC that was never deleted is not a backup strategy.

### Scaling decision

The brief asks for metrics-server + HPA, so the API scales on 70% CPU (1–3
replicas). Replica count is **not** hard-coded on the Deployment; the HPA owns it,
and Argo ignores `/spec/replicas` so selfHeal does not fight the scaler.

For this tiny DB-backed API, CPU is a weak demand signal. Longer term I would scale
on request rate / concurrency (adapter or KEDA) or SLO error budget, not "the
process looked busy."

### Alert decision

Alert: `ApiDatabaseUnreachable` when
`(qoves_db_up == 0) or (up{job="qoves-api"} == 0)` for 5 minutes.

Why I care: either Postgres looks down to the app for a sustained window, or
Prometheus cannot scrape the API at all. That is a real outage path (DB, secret,
network policy, volume, or the API pods themselves), not a short CPU blip.

The background database probe updates `qoves_db_up`. The `/healthz` endpoint
independently checks the same PostgreSQL connection path for live requests.

Readiness uses `/` so a DB outage does not empty Service endpoints and kill the
scrape right when the alert needs the gauge. External readiness is still
expressed by `/healthz` through ingress for humans and load balancers that care.

Prometheus runs in `qoves-platform` and scrapes the `qoves-api` Service in
`qoves-app`. With multiple HPA replicas a single static Service target under-
samples backends. I left it simple for this lab; production would use
endpoints/pod discovery.

---

## 3. What minikube did for me

Things minikube quietly handles that I would own on real hardware:

- API server / control plane bootstrap and certs
- etcd (and actually backing it up)
- node OS, kubelet, join flow, patching
- installing and upgrading the CNI (here: Calico)
- something in front of ingress-nginx (LB / edge)
- a real storage provisioner / CSI, not the hostpath-style default
- metrics-server as a maintained component

I used the `ingress` and `metrics-server` addons. Fine for a laptop demo; not a
production bootstrap story.

---

## 4. Production gaps

Before real traffic:

- more than one node, control plane HA
- real Postgres HA (or managed DB) and connection pooling
- backups that leave the machine, plus a restore I have actually run
- secret store with rotation (not Sealed Secrets as the long-term model)
- image digests + signing + admission
- TLS on the edge, auth, rate limits
- Alertmanager / paging, longer metric retention
- upgrade path for cluster and apps
- promotion across environments (dev → staging → prod overlays), not laptop-as-prod
- multi-cluster strategy: cluster failure, traffic routing, config promotion,
  data replication, and disaster recovery (this lab is one minikube profile only)
- scrape configuration that scales cleanly with HPA (pod/endpoints discovery
  instead of a single Service target)

Local disk on a single minikube node means node loss can mean data loss. Fine for
the take-home; not fine in production without backups.

If I had more time: CloudNativePG + backups to MinIO, admit only digests/signed
images, FQDN egress for one external host, and proper Prometheus pod discovery
under HPA. I stopped before that so the core path stays something I can defend
line by line.

---

## 5. Runbook when `/healthz` is 503

Assume ingress still answers but `/healthz` is 503, and the alert may be firing.

1. `kubectl -n argocd get applications` — any OutOfSync / Degraded?
2. `kubectl -n qoves-app get pods` and logs on `deploy/qoves-api`
3. Postgres: sts / pvc / `logs postgres-0`
4. Is Secret `qoves-db` present? Is sealed-secrets controller healthy?
5. Bad NetworkPolicy in git? Revert or fix in git and let Argo heal it
6. Bad deploy commit? `git revert`, push, wait for sync
7. Confirm `/healthz` through ingress is 200 and `qoves_db_up` is 1

I treat git as the fix path, not random live edits that drift from the repo.
