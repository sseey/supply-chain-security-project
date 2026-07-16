# Lab 3 — Le cluster qui refuse l'inconnu (Kyverno) (~1 h 30)

**But :** monter un cluster `kind`, installer **Kyverno**, et appliquer des politiques
d'**admission** qui **exigent** signature + attestations + registry autorisé + pas de `:latest`.

> 🔧 **Automatisation :** `make cluster-create` puis `make kyverno-install` font tout ce qui
> suit (§3.1 à 3.3), avec une version de Kyverno épinglée et testée (voir
> `docs/troubleshooting.md` si vous préférez le faire à la main et rencontrez une erreur
> de CRD trop volumineuse ou d'incompatibilité de version Kubernetes).

## 3.1 Créer le cluster kind

```bash
kind create cluster --name scs --config cluster/kind-config.yaml
kubectl cluster-info --context kind-scs
```

(Voie k3s : `k3s server` / `k3d cluster create scs` fonctionnent aussi — Kyverno s'installe pareil.)

## 3.2 Installer Kyverno

```bash
# ⚠️ N'utilisez PAS `kubectl apply` directement sur ce fichier : les CRD de Kyverno
# dépassent la limite de 262144 octets de l'annotation last-applied-configuration.
# Utilisez --server-side (ou `kubectl create`, qui ne pose pas ce problème) :
kubectl apply --server-side --force-conflicts \
  -f https://github.com/kyverno/kyverno/releases/download/v1.14.5/install.yaml
# Attendre que Kyverno soit prêt :
kubectl -n kyverno rollout status deploy/kyverno-admission-controller
```

> ⚠️ **Version épinglée volontairement** (`v1.14.5`, pas `releases/latest`) : les toutes
> dernières versions de Kyverno utilisent des CRD (`selectableFields`) qui exigent
> Kubernetes ≥ 1.31, incompatibles avec un cluster `kind` par défaut (Kubernetes 1.29).
> Voir `docs/troubleshooting.md` pour le détail de cette incompatibilité, rencontrée et
> corrigée pendant la mise au point de ce dépôt.

> **Kyverno** est un moteur de politiques Kubernetes natif : les règles sont des **objets YAML**
> (`ClusterPolicy`). Il s'insère comme **admission webhook** : *avant* qu'un Pod soit créé, il
> valide la requête et peut la **refuser**.

## 3.3 Créer le namespace applicatif

```bash
kubectl apply -f k8s/namespace.yaml
```

## 3.4 Appliquer les politiques

Les politiques sont fournies dans [`../policies/kyverno/`](../policies/kyverno/). Lisez-les,
**adaptez le registry et l'identité** à votre fork (variables `<votre-user>` dans les fichiers).

```bash
# 1) N'autoriser que votre registry GHCR
kubectl apply -f policies/kyverno/01-allowed-registries.yaml

# 2) Interdire le tag :latest (forcer un tag/digest explicite)
kubectl apply -f policies/kyverno/02-disallow-latest.yaml

# 3) Exiger une signature cosign valide de VOTRE identité
kubectl apply -f policies/kyverno/03-verify-signature.yaml

# 4) Exiger l'attestation de provenance (SLSA)
kubectl apply -f policies/kyverno/04-require-provenance.yaml

# Vérifier l'état des politiques :
kubectl get clusterpolicy
```

Toutes doivent être `Ready: true`.

## 3.5 Comprendre la politique de signature

Extrait de `03-verify-signature.yaml` (voir le fichier complet) :

```yaml
spec:
  validationFailureAction: Enforce      # ← Enforce = REFUSE (Audit = journalise seulement)
  rules:
    - name: verifier-signature-cosign
      match:
        any:
          - resources:
              kinds: [Pod]
      verifyImages:
        - imageReferences:
            - "ghcr.io/<votre-user>/scs-demo-app*"
          attestors:
            - entries:
                - keys:                  # (mode par clé ; en keyless : bloc 'keyless')
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      ...votre cosign.pub...
                      -----END PUBLIC KEY-----
```

> Point clé : `validationFailureAction: Enforce`. C'est **le** réglage qui fait passer du
> « on observe » au « on **bloque** ». Une politique en `Audit` laisse tout passer et se
> contente de logguer — utile pour un déploiement progressif, dangereux si on croit être protégé.

## 3.6 Déployer l'app (image signée) → doit être ACCEPTÉE

🔧 **Automatisation :** `export DIGEST=sha256:...` puis `make deploy`
(`scripts/deploy.sh`) — le script substitue votre digest **en mémoire**, sans jamais
modifier `k8s/deployment.yaml` (le placeholder documenté y reste intact pour les autres
étudiants/relecteurs).

Pour le faire à la main :

```bash
# Remplace le placeholder à la volée, sans toucher au fichier suivi par git :
sed "s|ghcr.io/<votre-user>/scs-demo-app@sha256:REMPLACEZ_PAR_VOTRE_DIGEST|ghcr.io/<votre-user>/scs-demo-app@$DIGEST|" \
  k8s/deployment.yaml | kubectl apply -n app -f -
kubectl apply -n app -f k8s/service.yaml
kubectl get pods -n app -w        # le pod doit démarrer
```

Si tout est en règle (signée + provenance + bon registry + par digest), **le pod tourne** ✅.

## ✅ Critères de sortie du lab

- [ ] Cluster `kind` up + Kyverno `Ready`.
- [ ] Les 4 `ClusterPolicy` sont `Ready` et en `Enforce`.
- [ ] Votre image **signée et conforme** est **acceptée** (pod Running).

➡️ Suite : [`lab4-attaque-defense.md`](lab4-attaque-defense.md)
