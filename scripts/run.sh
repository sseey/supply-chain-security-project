#!/usr/bin/env bash
# Lance l'image locale et l'expose sur http://localhost:8080 (make run).
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

REF="${GHCR_IMAGE}:${IMAGE_TAG}"
echo "==> docker run ${REF} sur http://localhost:8080 (Ctrl+C pour arrêter)"
exec docker run --rm -it -p 8080:8080 --name scs-demo-app "$REF"
