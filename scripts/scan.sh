#!/usr/bin/env bash
# Scanne le SBOM avec Grype et fait échouer la chaîne sur CRITICAL corrigeable (Lab 1 / make scan).
# Lit automatiquement .grype.yaml (only-fixed: true, fail-on-severity: critical) depuis la racine.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

if ! command -v grype >/dev/null 2>&1; then
  echo "❌ grype n'est pas installé — voir docs/01-prerequis-setup.md" >&2
  exit 1
fi

SBOM="artifacts/sbom.spdx.json"
if [[ ! -f "$SBOM" ]]; then
  echo "❌ ${SBOM} introuvable — lancez d'abord 'make sbom' (scripts/generate-sbom.sh)." >&2
  exit 1
fi

echo "==> Scan Grype de sbom:${SBOM} (politique : .grype.yaml)"
set +e
grype "sbom:${SBOM}" -o table
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "❌ Vulnérabilité(s) CRITICAL corrigeable(s) détectée(s) — la chaîne s'arrête ici (voir .grype.yaml)." >&2
else
  echo "✅ Aucune vulnérabilité CRITICAL corrigeable — la chaîne peut continuer."
fi
exit $STATUS
