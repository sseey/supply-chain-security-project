#!/usr/bin/env bash
# Vérifie que les outils requis par le projet sont installés (cf. docs/01-prerequis-setup.md).
set -Eeuo pipefail

MISSING=0

check() {
  local name="$1"; shift
  if command -v "$name" >/dev/null 2>&1; then
    local out
    out="$("$@" 2>&1 | head -n1)" || true
    printf "✅ %-10s %s\n" "$name" "$out"
  else
    printf "❌ %-10s MANQUANT\n" "$name"
    MISSING=1
  fi
}

check docker   docker version --format '{{.Client.Version}}'
check kind     kind version
check kubectl  kubectl version --client
check syft     syft version
check grype    grype version
check cosign   cosign version
check jq       jq --version
check git      git --version

echo
if command -v kyverno >/dev/null 2>&1; then
  KYVERNO_OUT="$(kyverno version 2>&1 | head -n1)" || true
  printf "✅ %-10s %s\n" "kyverno (CLI, optionnel)" "$KYVERNO_OUT"
else
  echo "ℹ️  kyverno CLI (optionnel, pour tester les policies hors cluster) : absent."
fi

echo
if [[ "$MISSING" -ne 0 ]]; then
  echo "❌ Un ou plusieurs outils requis manquent. Voir docs/01-prerequis-setup.md." >&2
  exit 1
fi

echo "✅ Tous les outils requis sont disponibles."
