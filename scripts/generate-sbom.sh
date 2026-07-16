#!/usr/bin/env bash
# Génère le SBOM (SPDX JSON) de l'image avec Syft (Lab 1 / make sbom).
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

if ! command -v syft >/dev/null 2>&1; then
  echo "❌ syft n'est pas installé — voir docs/01-prerequis-setup.md" >&2
  exit 1
fi

REF="${1:-${GHCR_IMAGE}:${IMAGE_TAG}}"
mkdir -p artifacts

echo "==> SBOM (SPDX JSON) de ${REF}"
syft "$REF" -o spdx-json > artifacts/sbom.spdx.json

COUNT="$(jq '.packages | length' artifacts/sbom.spdx.json)"
echo "==> ${COUNT} paquets détectés — résumé (jq) :"
jq -r '.packages[] | "\(.name)@\(.versionInfo // "?")"' artifacts/sbom.spdx.json | sort -u | head -n 20
echo "==> SBOM complet : artifacts/sbom.spdx.json"
