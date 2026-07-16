#!/usr/bin/env bash
# Signe l'image PAR DIGEST avec cosign — mode clé ou keyless (make sign).
# Usage : DIGEST=sha256:... ./scripts/sign.sh [key|keyless]   (défaut : keyless)
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

if [[ -z "${DIGEST:-}" ]]; then
  echo "❌ Variable DIGEST non définie." >&2
  echo "   Exemple : export DIGEST=sha256:... (sortie de scripts/push.sh)" >&2
  exit 1
fi

MODE="${1:-keyless}"
REF="${GHCR_IMAGE}@${DIGEST}"

case "$MODE" in
  key)
    if [[ ! -f cosign.key ]]; then
      echo "❌ cosign.key introuvable à la racine du dépôt." >&2
      echo "   Générez-le : cosign generate-key-pair (cf. labs/lab2-sign-attest.md)." >&2
      exit 1
    fi
    echo "==> Signature PAR CLÉ de ${REF}"
    cosign sign --key cosign.key --yes "$REF"
    ;;
  keyless)
    echo "==> Signature KEYLESS (OIDC) de ${REF}"
    COSIGN_EXPERIMENTAL=1 cosign sign --yes "$REF"
    ;;
  *)
    echo "❌ Mode inconnu : ${MODE} (attendu : key | keyless)" >&2
    exit 1
    ;;
esac

echo "✅ Image signée : ${REF}"
