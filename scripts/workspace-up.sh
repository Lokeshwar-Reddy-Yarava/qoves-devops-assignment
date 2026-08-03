#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker/workspace/docker-compose.yml"

echo "==> Building and starting qoves-workspace"
docker compose -f "${COMPOSE_FILE}" up -d --build

echo "==> Ready"
docker exec -it qoves-workspace bash -lc 'kubectl version --client 2>/dev/null | head -1; minikube version'

echo
echo "Enter with: docker exec -it qoves-workspace bash"
echo "Then: ./scripts/cluster-start.sh"
