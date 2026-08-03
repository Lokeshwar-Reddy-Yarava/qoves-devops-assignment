#!/usr/bin/env bash
set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-qoves}"
CPUS="${MINIKUBE_CPUS:-4}"
MEMORY="${MINIKUBE_MEMORY:-6144}"

echo "==> minikube profile=${PROFILE} CNI=calico"
minikube start \
  -p "${PROFILE}" \
  --driver=docker \
  --cni=calico \
  --cpus="${CPUS}" \
  --memory="${MEMORY}" \
  --kubernetes-version=stable

echo "==> addons: ingress, metrics-server"
minikube addons enable ingress -p "${PROFILE}"
minikube addons enable metrics-server -p "${PROFILE}"

echo "==> status"
kubectl get nodes -o wide
minikube status -p "${PROFILE}"

echo
echo "Profile ${PROFILE} is up (single node, Calico)."
echo "Build the API next: ./scripts/build-and-load-api.sh"
echo "Then install Argo and apply gitops/clusters/minikube/root-application.yaml"
echo "(details in docs/WRITEUP.md)"
