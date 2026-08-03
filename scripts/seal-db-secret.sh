#!/usr/bin/env bash
set -euo pipefail

# Seals DATABASE_URL + POSTGRES_PASSWORD into a SealedSecret.
# Password must come from the environment — nothing secret is stored in git.
#
#   export POSTGRES_PASSWORD="$(openssl rand -base64 24)"
#   ./scripts/seal-db-secret.sh
#   unset POSTGRES_PASSWORD

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-qoves-app}"
SECRET_NAME="${SECRET_NAME:-qoves-db}"
OUT_FILE="${OUT_FILE:-${ROOT_DIR}/gitops/manifests/app/secrets/qoves-db.sealedsecret.yaml}"

if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
  echo "Set POSTGRES_PASSWORD in the environment first." >&2
  echo "  export POSTGRES_PASSWORD=\"\$(openssl rand -base64 24)\"" >&2
  exit 1
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
  DATABASE_URL="postgresql://app:${POSTGRES_PASSWORD}@postgres.${NAMESPACE}.svc.cluster.local:5432/app"
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --dry-run=client -o yaml > "${tmpdir}/secret.yaml"

kubeseal --format=yaml \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  < "${tmpdir}/secret.yaml" > "${OUT_FILE}"

echo "Wrote ${OUT_FILE}"
echo "Commit this SealedSecret only. Do not commit plaintext secrets."
