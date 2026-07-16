#!/usr/bin/env bash
# Vérifie la signature cosign de l'image — mode clé ou keyless (make verify).
# Usage : DIGEST=sha256:... ./scripts/verify.sh [key|keyless]   (défaut : keyless)
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

if [[ -z "${DIGEST:-}" ]]; then
  echo "❌ Variable DIGEST non définie." >&2
  exit 1
fi

MODE="${1:-keyless}"
REF="${GHCR_IMAGE}@${DIGEST}"

case "$MODE" in
  key)
    if [[ ! -f cosign.pub ]]; then
      echo "❌ cosign.pub introuvable à la racine du dépôt." >&2
      exit 1
    fi
    echo "==> Vérification PAR CLÉ de ${REF}"
    cosign verify --key cosign.pub "$REF" | jq '.[].optional'
    ;;
  keyless)
    require_no_placeholder "$COSIGN_IDENTITY" "COSIGN_IDENTITY"
    echo "==> Vérification KEYLESS de ${REF}"
    echo "    Identité attendue : ${COSIGN_IDENTITY}"
    echo "    Émetteur attendu  : ${COSIGN_ISSUER}"
    cosign verify \
      --certificate-identity "${COSIGN_IDENTITY}" \
      --certificate-oidc-issuer "${COSIGN_ISSUER}" \
      "$REF" | jq '.[].optional.Issuer'
    ;;
  *)
    echo "❌ Mode inconnu : ${MODE} (attendu : key | keyless)" >&2
    exit 1
    ;;
esac
