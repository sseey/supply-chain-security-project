#!/usr/bin/env bash
# Déploie l'application dans le cluster, PAR DIGEST — jamais par tag mutable (make deploy).
#
# Mécanisme d'injection du digest : ce script NE MODIFIE JAMAIS k8s/deployment.yaml.
# Il effectue une substitution contrôlée en mémoire (sed) du placeholder documenté
# vers votre digest réel, puis envoie le résultat à `kubectl apply -f -`.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

if [[ -z "${DIGEST:-}" ]]; then
  echo "❌ Variable DIGEST non définie." >&2
  echo "   Exemple : export DIGEST=sha256:... (récupéré au Lab 0, via cosign, ou dans la CI)" >&2
  exit 1
fi

PLACEHOLDER="ghcr.io/<votre-user>/scs-demo-app@sha256:REMPLACEZ_PAR_VOTRE_DIGEST"
IMAGE_REF="${GHCR_IMAGE}@${DIGEST}"

echo "==> Déploiement de ${IMAGE_REF} dans le namespace ${APP_NAMESPACE}"
kubectl apply -f k8s/namespace.yaml

sed "s|${PLACEHOLDER}|${IMAGE_REF}|" k8s/deployment.yaml | kubectl apply -n "${APP_NAMESPACE}" -f -
kubectl apply -n "${APP_NAMESPACE}" -f k8s/service.yaml

echo "==> Statut du déploiement :"
kubectl -n "${APP_NAMESPACE}" get pods -l app=scs-demo-app
