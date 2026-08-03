#!/usr/bin/env bash
set -euo pipefail

# Build qoves-api and load it into the minikube profile.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${MINIKUBE_PROFILE:-qoves}"
IMAGE="${IMAGE:-lokeshwarreddyyarava/qoves-api:v1.0.1}"

echo "==> Building ${IMAGE} from ${ROOT_DIR}/app"
docker build -t "${IMAGE}" "${ROOT_DIR}/app"

echo "==> Loading into minikube profile ${PROFILE}"
minikube image load "${IMAGE}" -p "${PROFILE}"

echo "==> Images matching qoves-api"
minikube image ls -p "${PROFILE}" | grep qoves-api || true
echo "Done."
