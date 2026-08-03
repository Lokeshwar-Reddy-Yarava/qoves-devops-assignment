#!/usr/bin/env bash
# One-time install of the Sealed Secrets controller (bootstrap, same idea as Argo CD).
# SealedSecret CRs for the app remain under GitOps (gitops/manifests/app/secrets/).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${ROOT_DIR}/gitops/manifests/platform/sealed-secrets/controller.yaml"

echo "==> Applying Sealed Secrets controller from ${MANIFEST}"
kubectl apply -f "${MANIFEST}"

echo "==> Waiting for controller"
kubectl -n kube-system rollout status deploy/sealed-secrets-controller --timeout=180s
kubectl -n kube-system get deploy,pods -l name=sealed-secrets-controller
echo "Done. Seal app secrets with: export POSTGRES_PASSWORD=... && ./scripts/seal-db-secret.sh"
