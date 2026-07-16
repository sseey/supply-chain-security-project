#!/usr/bin/env bash
# Crée (ou réutilise) le cluster kind local pour la démo. Idempotent (make cluster-create).
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

if kind get clusters 2>/dev/null | grep -qx "${KIND_CLUSTER_NAME}"; then
  echo "✅ Cluster kind '${KIND_CLUSTER_NAME}' déjà présent — rien à faire."
else
  echo "==> Création du cluster kind '${KIND_CLUSTER_NAME}'"
  kind create cluster --name "${KIND_CLUSTER_NAME}" --config cluster/kind-config.yaml
fi

kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}"
