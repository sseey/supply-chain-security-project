#!/usr/bin/env bash
# Construit l'image Docker de l'application et vérifie /health (Lab 0 / make build).
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

REF="${GHCR_IMAGE}:${IMAGE_TAG}"
echo "==> Build de l'image ${REF}"
docker build -t "$REF" ./app
echo "==> Image construite : $REF"

echo "==> Vérification rapide (health check sur un conteneur éphémère)"
HOST_PORT="${HEALTHCHECK_PORT:-18080}"
CONTAINER_ID="$(docker run --rm -d -p "${HOST_PORT}:8080" "$REF")"
# shellcheck disable=SC2317
cleanup() { docker stop "$CONTAINER_ID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for _ in $(seq 1 10); do
  if curl -sf "http://localhost:${HOST_PORT}/health" >/dev/null; then
    echo "✅ /health répond 200 sur le port ${HOST_PORT}"
    curl -s "http://localhost:${HOST_PORT}/health"; echo
    exit 0
  fi
  sleep 1
done

echo "❌ /health n'a pas répondu à temps" >&2
docker logs "$CONTAINER_ID" >&2 || true
exit 1
