# Writeup — QOVES take-home

Repo: https://github.com/Lokeshwar-Reddy-Yarava/qoves-devops-assignment

I built this as a small platform around a trivial API: minikube + Calico, Argo CD
app-of-apps, Postgres with a PVC, Sealed Secrets, default-deny NetworkPolicies,
ingress, HPA, and a small Prometheus setup with one alert.

I did the core path carefully rather than stacking stretch goals. A few places I
took a shortcut on purpose and called it out below.

---

## 1. How to run it

I mainly used the optional Docker workspace so tooling stays consistent on
Windows/WSL, but anything with Docker, minikube, kubectl, and kubeseal works.

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

After Sealed Secrets is up, seal credentials on **this** cluster (password stays
in my shell only, never in the repo):

```bash
export POSTGRES_PASSWORD="$(openssl rand -base64 24)"
./scripts/seal-db-secret.sh
git add gitops/manifests/app/secrets/qoves-db.sealedsecret.yaml
git commit -m "Add sealed DB credentials"
git push
unset POSTGRES_PASSWORD
```

Then hit the app through ingress (not port-forward):

```bash
curl -i -H 'Host: qoves.local' "http://$(minikube ip -p qoves)/"
curl -i -H 'Host: qoves.local' "http://$(minikube ip -p qoves)/healthz"
curl -i -H 'Host: qoves.local' "http://$(minikube ip -p qoves)/metrics"
```

Proof dump I use for reviewers:

```bash
./scripts/proof.sh
```

### Layout

```
app/                  API
gitops/clusters/      Argo root + child apps
gitops/manifests/     what actually lands in the cluster
docs/WRITEUP.md       this file
scripts/              bootstrap + seal + proof
docker/workspace/     optional tool container
```

### Changing something the GitOps way

I edit under `gitops/manifests/`, commit, push. Argo is on automated sync +
selfHeal. I don't hand-edit running Deployments as the permanent state.

Example: tweak HPA CPU target in `gitops/manifests/app/base/api.yaml`, push, then
check `kubectl -n qoves-app get hpa`.

Note: this is a **single-node** minikube profile (`qoves`). Fine for the exercise;
I would not pretend it is HA.

If I wipe the cluster, Sealed Secrets ciphertext from the old cluster does not
decrypt. I re-run the seal script and push again.

---

## 2. Decisions

**Calico** — I wanted NetworkPolicy that actually works. minikube's default CNI
does not enforce policies, which would make part D fake. Calico is what the brief
hints at and is easy to explain. Cilium would also be fine; I did not need extra
eBPF features here.

**Argo CD app-of-apps** — root Application points at `gitops/clusters/minikube/apps/`,
and each child owns one directory under `manifests/`. Matches the brief and makes
the tree easy to show in a review. Flux would get the same job done; I already
know Argo's Application model well enough for a walkthrough.

**Sealed Secrets** — goal was "credentials are not in git as plaintext or base64."
Sealed Secrets is the simplest fully local option. I rejected putting a Secret
YAML in git. SOPS needs an Argo plugin. External Secrets only makes sense with
a real backend (Vault / cloud SM), not a fake provider that puts the value back
in a manifest. Day two at work I would hang External Secrets off Vault or the
cloud secret manager and rotate credentials.

I generate the password at seal time from the environment. The seal script fails
if you forget to export `POSTGRES_PASSWORD` — I do not want a "default" password
sitting in the repo.

**Postgres as a raw StatefulSet** — enough to talk about PVC, identity, and restarts
without bringing an operator in early. CloudNativePG is useful later for HA and
backup; I left it as "what I would do next."

**HPA on CPU** — assignment asks for metrics-server + HPA, so I put one on the API
(70% CPU, 1–3 replicas). For a tiny DB-backed API, CPU is a weak demand signal.
Longer term I would scale on request rate / concurrency (adapter or KEDA) or SLO
error budget, not "the process looked busy."

**NetworkPolicy** — default deny ingress + egress in `qoves-app`. Then only what
the diagram needs: ingress-nginx to the API, API to Postgres both ways, DNS to
kube-system, Prometheus scrape from `qoves-platform`. I check that with
`scripts/proof.sh` (DNS works, random egress and pod→db for a random pod fails,
API health still OK).

---

## 3. What minikube did for me

Stuff minikube quietly handles that I would own on real hardware:

- API server / control plane bootstrap and certs
- etcd (and actually backing it up)
- node OS, kubelet, join flow, patching
- installing and upgrading the CNI (here: Calico)
- something in front of ingress-nginx (LB / edge)
- a real storage provisioner / CSI, not the hostpath-ish default
- metrics-server as a maintained component

I used the `ingress` and `metrics-server` addons. That is fine for a laptop demo;
it is not a production platform bootstrap story.

---

## 4. Production gaps

Before I would put real traffic on something like this:

- more than one node, control plane HA
- real Postgres HA (or managed DB) and connection pooling
- backups that leave the machine, plus a restore I have actually run
- secret store with rotation (not just Sealed Secrets as the long-term model)
- image digests + signing + admission
- TLS on the edge, auth, rate limits
- Alertmanager / paging, longer metric retention
- upgrade path for cluster and apps
- promotion across environments, not "laptop is prod"

Local disk on a single minikube node means node loss can mean data loss. That is
fine for the take-home; it is not fine in production without backups.

---

## 5. Storage

**Access mode is ReadWriteOnce.** One node mounts the volume read-write at a
time. That limits where `postgres-0` can schedule — it follows the volume. You
cannot run multiple writers on the same claim.

**Pod dies:** StatefulSet brings `postgres-0` back with the same PVC. Data stays.
I check this in `proof.sh` with a small table and a row called `survives-restart`.

**Node dies:** on this minikube setup the volume is tied to that node. Lose the
node and you are recovering from backup, not magic. On cloud CSI you often can
reattach to another node after the old attachment is gone, but there is still
downtime until Postgres is Ready again.

**Backup / restore in real life:** scheduled logical dumps or continuous backup
to object storage (encrypted), plus occasional volume snapshots. Restore path:
new claim → restore → start Postgres → point the app via git → verify `/healthz`
and app checks. A PVC that was never deleted is not a backup strategy.

---

## 6. Alert

Alert: `ApiDatabaseUnreachable` when `qoves_db_up == 0` for 5 minutes.

Why I care: that means users have been getting readiness failures for a while.
Root cause is somewhere on the data path (DB, secret, network policy, volume) —
worth waking someone — not a short CPU spike.

Prometheus lives in `qoves-platform` and scrapes the API `/metrics`. The API
updates `qoves_db_up` with a small background probe as well as the `/healthz`
path itself.

---

## 7. Runbook when `/healthz` is 503

Assume ingress still answers but body says DB is down / HTTP 503, and the alert
may be firing.

1. `kubectl -n argocd get applications` — is anything out of sync or degraded?
2. `kubectl -n qoves-app get pods` and logs on `deploy/qoves-api`
3. Postgres: sts / pvc / `logs postgres-0`
4. Is Secret `qoves-db` present? Is sealed-secrets controller happy?
5. Did we ship a bad NetworkPolicy? If yes, fix in git and let Argo repair it
6. If the bad change was a commit: `git revert`, push, wait for sync
7. Confirm `/healthz` through ingress is 200 again and `qoves_db_up` is 1

I treat git as the fix path, not random live edits that drift from the repo.

---

## What I would do if I had more time

CloudNativePG + backups to MinIO, admit only digests/signed images, and tighter
FQDN egress for one external host. I stopped before that so the core path stays
something I can defend line by line in a call.
