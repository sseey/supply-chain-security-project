#!/usr/bin/env bash
# Installe Kyverno (version épinglée, pas "latest") et attend qu'il soit prêt (make kyverno-install).
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

# Épinglé pour la reproductibilité de la démo — mettez à jour consciemment si besoin
# (voir https://github.com/kyverno/kyverno/releases). Testé ici avec kind (nœud Kubernetes v1.29) :
# les toutes dernières versions de Kyverno (ex. v1.18.x) embarquent des CRD utilisant le champ
# `selectableFields`, qui exige Kubernetes ≥ 1.31 — incompatible avec un nœud kind par défaut.
# v1.14.5 est la dernière version validée compatible avec Kubernetes 1.29/1.30.
KYVERNO_VERSION="${KYVERNO_VERSION:-v1.14.5}"
INSTALL_URL="https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/install.yaml"

echo "==> Installation de Kyverno ${KYVERNO_VERSION}"
# --server-side (au lieu de apply classique) : les CRD de Kyverno sont volumineux et dépassent
# la limite de 262144 octets de l'annotation kubectl.kubernetes.io/last-applied-configuration.
kubectl apply --server-side --force-conflicts -f "$INSTALL_URL"

echo "==> Attente de la disponibilité de Kyverno (peut prendre 1-2 minutes)..."
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s

echo "==> Création du namespace applicatif '${APP_NAMESPACE}' (si absent)"
kubectl apply -f k8s/namespace.yaml

echo "✅ Kyverno est prêt. Politiques disponibles dans policies/kyverno/ (pas encore appliquées par ce script)."
