#!/usr/bin/env bash
# Attache les attestations SBOM + provenance à l'image signée (make attest).
# Usage : DIGEST=sha256:... ./scripts/attest.sh [key|keyless]   (défaut : keyless)
#
# La provenance générée ici est PÉDAGOGIQUE (écrite à la main) — utile pour comprendre
# la mécanique en local (Lab 2). En CI, une provenance plus fiable est produite
# automatiquement par le workflow (voir .github/workflows/supply-chain.yml).
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
SBOM="artifacts/sbom.spdx.json"
PROVENANCE="artifacts/provenance.json"

if [[ ! -f "$SBOM" ]]; then
  echo "❌ ${SBOM} introuvable — lancez 'make sbom' d'abord." >&2
  exit 1
fi

COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
cat > "$PROVENANCE" <<EOF
{
  "buildType": "https://example.com/manual-local-build/v1",
  "builder": { "id": "local:${GITHUB_USERNAME}" },
  "invocation": {
    "configSource": {
      "uri": "git+https://github.com/${GITHUB_REPOSITORY}",
      "digest": { "sha1": "${COMMIT_SHA}" }
    }
  },
  "metadata": { "buildStartedOn": "$(date -u +%Y-%m-%dT%H:%M:%SZ)" }
}
EOF
echo "==> Provenance pédagogique générée : ${PROVENANCE}"

case "$MODE" in
  key)
    if [[ ! -f cosign.key ]]; then
      echo "❌ cosign.key introuvable à la racine du dépôt." >&2
      exit 1
    fi
    echo "==> Attestation SBOM (clé)"
    cosign attest --key cosign.key --yes --predicate "$SBOM" --type spdxjson "$REF"
    echo "==> Attestation provenance (clé)"
    cosign attest --key cosign.key --yes --predicate "$PROVENANCE" --type slsaprovenance "$REF"
    ;;
  keyless)
    echo "==> Attestation SBOM (keyless)"
    COSIGN_EXPERIMENTAL=1 cosign attest --yes --predicate "$SBOM" --type spdxjson "$REF"
    echo "==> Attestation provenance (keyless)"
    COSIGN_EXPERIMENTAL=1 cosign attest --yes --predicate "$PROVENANCE" --type slsaprovenance "$REF"
    ;;
  *)
    echo "❌ Mode inconnu : ${MODE} (attendu : key | keyless)" >&2
    exit 1
    ;;
esac

echo "✅ Attestations attachées à ${REF}"
echo "   Inspection : cosign tree ${REF}"
