#!/usr/bin/env bash
# Fonctions et variables partagées par les scripts scripts/*.sh.
# Ce fichier est fait pour être SOURCÉ (`source scripts/lib.sh`), pas exécuté directement.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env() {
  # Valeurs par défaut sûres pour un usage 100% local (build/sbom/scan), sans compte GitHub.
  # .env.example n'est JAMAIS sourcé directement : il contient des placeholders <...> qui ne
  # sont pas une syntaxe shell valide (ex. `<GITHUB_USERNAME>` serait lu comme une redirection).
  GITHUB_USERNAME="${GITHUB_USERNAME:-local}"
  GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-local/supply-chain-security-project}"
  IMAGE_NAME="${IMAGE_NAME:-scs-demo-app}"
  IMAGE_TAG="${IMAGE_TAG:-0.1.0}"
  COSIGN_IDENTITY="${COSIGN_IDENTITY:-}"
  COSIGN_ISSUER="${COSIGN_ISSUER:-https://token.actions.githubusercontent.com}"
  KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-scs}"
  APP_NAMESPACE="${APP_NAMESPACE:-app}"

  if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
  else
    echo "ℹ️  Pas de .env trouvé — copiez .env.example en .env et personnalisez-le. Valeurs locales par défaut utilisées (GITHUB_USERNAME=local)." >&2
  fi
}

# Bloque avec un message clair si une valeur contient encore un placeholder <...>.
# Usage : require_no_placeholder "$GITHUB_USERNAME" "GITHUB_USERNAME"
require_no_placeholder() {
  local value="$1" name="$2"
  if [[ "$value" == *"<"*">"* ]]; then
    echo "❌ $name contient encore un placeholder (${value})." >&2
    echo "   Copiez .env.example en .env et remplacez les valeurs <...> par les vôtres." >&2
    exit 1
  fi
}

load_env
# Utilisée par les scripts qui sourcent lib.sh (build.sh, sign.sh, deploy.sh, ...).
# shellcheck disable=SC2034
GHCR_IMAGE="ghcr.io/${GITHUB_USERNAME}/${IMAGE_NAME}"
