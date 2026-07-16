#!/usr/bin/env bash
# Démo attaque/défense : exécute de VRAIES requêtes Kubernetes et affiche les VRAIS messages
# de Kyverno. Ne simule jamais un résultat — un test non réalisable ici est signalé comme tel.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

PASS=0
FAIL=0

section() { echo; echo "════════════════════════════════════════════════════════"; echo "$1"; echo "════════════════════════════════════════════════════════"; }

# Applique un manifeste (déjà rendu si besoin) et vérifie que Kubernetes le refuse.
# Affiche le VRAI message du serveur (webhook Kyverno) — jamais un résultat simulé.
apply_expect_denied() {
  local name="$1" content="$2"
  echo "--- kubectl apply -f - (${name}) ---"
  if echo "$content" | kubectl apply -f - 2>&1; then
    echo "❌ INATTENDU : la requête a été ACCEPTÉE (devrait être DENIED)."
    FAIL=$((FAIL+1))
  else
    echo "✅ DENIED (comme attendu)."
    PASS=$((PASS+1))
  fi
}

skip() {
  echo "⏭️  NON EXÉCUTÉ : $1"
}

section "Pré-vérifications"
kubectl cluster-info --context "kind-${KIND_CLUSTER_NAME}" >/dev/null || {
  echo "❌ Cluster kind '${KIND_CLUSTER_NAME}' injoignable. Lancez 'make cluster-create'." >&2
  exit 1
}
READY_COUNT="$(kubectl get clusterpolicy -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -ci true || true)"
echo "Politiques Kyverno Ready : ${READY_COUNT}/4"
if [[ "$READY_COUNT" -lt 4 ]]; then
  echo "⚠️  Moins de 4 politiques Ready. Appliquez policies/kyverno/*.yaml (Lab 3) avant la démo." >&2
fi

section "Test A — Image légitime (doit être ACCEPTED)"
if kubectl -n "${APP_NAMESPACE}" get pods -l app=scs-demo-app --no-headers 2>/dev/null | grep -q Running; then
  echo "✅ ACCEPTED — pod(s) en cours d'exécution :"
  kubectl -n "${APP_NAMESPACE}" get pods -l app=scs-demo-app
  PASS=$((PASS+1))
else
  echo "⏭️  Aucun pod scs-demo-app Running dans '${APP_NAMESPACE}'. Lancez 'make deploy' (DIGEST requis) d'abord."
fi

section "Test B — Tag :latest (doit être DENIED)"
apply_expect_denied "tag latest" "$(sed "s|ghcr.io/<votre-user>/scs-demo-app|${GHCR_IMAGE}|" k8s/attacks/latest.yaml)"

section "Test C — Registre non autorisé (doit être DENIED)"
apply_expect_denied "registre non autorisé" "$(cat k8s/attacks/untrusted-registry.yaml)"

section "Test D — Image non signée (doit être DENIED)"
if [[ -n "${UNSIGNED_DIGEST:-}" ]]; then
  rendered="$(sed "s|ghcr.io/<votre-user>/scs-demo-app|${GHCR_IMAGE}|; s|@sha256:REMPLACEZ_PAR_LE_DIGEST_NON_SIGNE|@${UNSIGNED_DIGEST}|" k8s/attacks/unsigned-image.yaml)"
  apply_expect_denied "image non signée" "$rendered"
else
  skip "export UNSIGNED_DIGEST=sha256:... requis (cf. labs/lab4-attaque-defense.md, Attaque 1)"
fi

section "Test E — Sans attestation de provenance (doit être DENIED)"
if [[ -n "${NO_PROVENANCE_DIGEST:-}" ]]; then
  rendered="$(sed "s|ghcr.io/<votre-user>/scs-demo-app|${GHCR_IMAGE}|; s|@sha256:REMPLACEZ_PAR_LE_DIGEST_SANS_PROVENANCE|@${NO_PROVENANCE_DIGEST}|" k8s/attacks/missing-provenance.yaml)"
  apply_expect_denied "sans provenance" "$rendered"
else
  skip "export NO_PROVENANCE_DIGEST=sha256:... requis (cf. labs/lab4-attaque-defense.md, Attaque 5)"
fi

section "Test F — Digest modifié après signature (doit être DENIED)"
if [[ -n "${TAMPERED_DIGEST:-}" ]]; then
  rendered="$(sed "s|ghcr.io/<votre-user>/scs-demo-app|${GHCR_IMAGE}|; s|@sha256:REMPLACEZ_PAR_LE_DIGEST_MODIFIE|@${TAMPERED_DIGEST}|" k8s/attacks/wrong-digest.yaml)"
  apply_expect_denied "digest modifié" "$rendered"
else
  skip "export TAMPERED_DIGEST=sha256:... requis (cf. labs/lab4-attaque-defense.md, Attaque 2)"
fi

section "Vérification finale : aucun Pod interdit n'a été créé"
kubectl -n "${APP_NAMESPACE}" get pods

section "Résumé"
echo "✅ Réussis : ${PASS}   ❌ Échecs inattendus : ${FAIL}"
[[ "$FAIL" -eq 0 ]]
