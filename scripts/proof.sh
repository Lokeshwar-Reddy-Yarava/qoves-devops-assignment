#!/usr/bin/env bash
# Dumps the proof QOVES asks for (they cannot run my cluster).
# Uses sed instead of head so pipefail does not kill the script mid-run.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${MINIKUBE_PROFILE:-qoves}"
HOST_HEADER="${INGRESS_HOST:-qoves.local}"

echo "============================================================"
echo "== context (${ROOT_DIR}) =="
echo "============================================================"
kubectl config current-context || true
kubectl get nodes -o wide || true

echo
echo "============================================================"
echo "== pods,svc,ingress,netpol -A =="
echo "============================================================"
kubectl get pods,svc,ingress,netpol -A

echo
echo "============================================================"
echo "== Argo applications =="
echo "============================================================"
kubectl -n argocd get applications -o wide || true
kubectl -n argocd get applications \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,PATH:.spec.source.path \
  2>/dev/null || true

echo
echo "============================================================"
echo "== ingress (Host ${HOST_HEADER}) =="
echo "============================================================"
INGRESS_IP="$(kubectl get ingress -n qoves-app qoves-api -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
if [[ -z "${INGRESS_IP}" ]]; then
  INGRESS_IP="$(minikube ip -p "${PROFILE}" 2>/dev/null || true)"
fi
if [[ -z "${INGRESS_IP}" ]]; then
  INGRESS_IP="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
fi
echo "INGRESS_IP=${INGRESS_IP}"

echo "-- GET / --"
curl -sS -i -H "Host: ${HOST_HEADER}" "http://${INGRESS_IP}/" | sed -n '1,40p'
echo
echo "-- GET /healthz --"
curl -sS -i -H "Host: ${HOST_HEADER}" "http://${INGRESS_IP}/healthz" | sed -n '1,40p'
echo
echo "-- GET /metrics --"
curl -sS -H "Host: ${HOST_HEADER}" "http://${INGRESS_IP}/metrics" | sed -n '1,25p'
echo

echo "============================================================"
echo "== NetworkPolicy checks =="
echo "============================================================"
kubectl -n qoves-app delete pod netpol-test --ignore-not-found --wait=false >/dev/null 2>&1 || true
kubectl -n qoves-app run netpol-test --image=busybox:1.36 --restart=Never --command -- sleep 120
kubectl -n qoves-app wait --for=condition=Ready pod/netpol-test --timeout=90s

echo "DNS (should work):"
kubectl -n qoves-app exec netpol-test -- nslookup kubernetes.default.svc.cluster.local || true

echo "Egress to example.com (should fail):"
set +e
kubectl -n qoves-app exec netpol-test -- sh -c \
  'wget -T 3 -O- http://example.com >/tmp/out 2>/tmp/err; echo exit=$?; cat /tmp/err'
set -e

echo "Random pod to Postgres (should fail):"
set +e
kubectl -n qoves-app exec netpol-test -- sh -c \
  'wget -T 3 -O- tcp://postgres.qoves-app.svc.cluster.local:5432 >/tmp/pout 2>/tmp/perr; echo exit=$?; cat /tmp/perr'
set -e

echo "API still reaches Postgres (/healthz):"
curl -sS -i -H "Host: ${HOST_HEADER}" "http://${INGRESS_IP}/healthz" | sed -n '1,30p'

kubectl -n qoves-app delete pod netpol-test --wait=false >/dev/null 2>&1 || true

echo
echo "============================================================"
echo "== app workload + secret present =="
echo "============================================================"
kubectl -n qoves-app get deploy,sts,svc,ingress,hpa,netpol,pvc
if kubectl -n qoves-app get secret qoves-db >/dev/null 2>&1; then
  echo "Secret qoves-db is present (values not printed)."
else
  echo "WARNING: Secret qoves-db missing"
fi

echo
echo "============================================================"
echo "== Prometheus (query from inside the cluster) =="
echo "============================================================"
echo "qoves_db_up:"
kubectl -n qoves-platform run prom-query --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --command -- curl -sS \
  "http://prometheus.qoves-platform.svc.cluster.local:9090/api/v1/query?query=qoves_db_up" \
  | sed -n '1,20p' || true
echo
echo "rules:"
kubectl -n qoves-platform run prom-rules --rm -i --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --command -- curl -sS \
  "http://prometheus.qoves-platform.svc.cluster.local:9090/api/v1/rules" \
  | sed -n '1,40p' || true
echo

echo "============================================================"
echo "== Postgres data survives pod restart =="
echo "============================================================"
kubectl -n qoves-app exec postgres-0 -- \
  psql -U app -d app -c \
  "CREATE TABLE IF NOT EXISTS qoves_proof(id int primary key, note text);
   INSERT INTO qoves_proof(id, note) VALUES (1, 'survives-restart')
   ON CONFLICT (id) DO UPDATE SET note=EXCLUDED.note;"
kubectl -n qoves-app delete pod postgres-0 --wait=true
kubectl -n qoves-app rollout status statefulset/postgres --timeout=180s
kubectl -n qoves-app exec postgres-0 -- psql -U app -d app -c "SELECT * FROM qoves_proof;"
echo "-- /healthz after restart --"
curl -sS -o /tmp/hz2 -w 'healthz_http=%{http_code}\n' \
  -H "Host: ${HOST_HEADER}" "http://${INGRESS_IP}/healthz"
cat /tmp/hz2
echo
echo "done."
