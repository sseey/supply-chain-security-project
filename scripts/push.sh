#!/usr/bin/env bash
# Authentifie sur GHCR et pousse l'image, puis affiche son digest (make push).
# Authentification : soit `docker login ghcr.io` déjà fait manuellement, soit
# GITHUB_TOKEN exporté (PAT scope write:packages) pour un login non interactif.
# Ne committez JAMAIS de token — voir docs/01-prerequis-setup.md.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

require_no_placeholder "$GITHUB_USERNAME" "GITHUB_USERNAME"

REF="${GHCR_IMAGE}:${IMAGE_TAG}"

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "==> Authentification à ghcr.io (GITHUB_TOKEN)"
  echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin
else
  echo "ℹ️  GITHUB_TOKEN non défini — on suppose que 'docker login ghcr.io' a déjà été fait."
fi

echo "==> Push de ${REF}"
docker push "$REF"

DIGEST_FULL="$(docker inspect --format='{{index .RepoDigests 0}}' "$REF")"
echo "==> Référence par digest : ${DIGEST_FULL}"
echo "    Pour la suite (sign/attest/deploy) : export DIGEST=\"${DIGEST_FULL#*@}\""
