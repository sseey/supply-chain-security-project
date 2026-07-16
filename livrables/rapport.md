# Rapport — Chaîne d'approvisionnement logicielle sécurisée

- **Groupe :** _(à compléter)_
- **Fork :** _(URL GitHub de votre fork — [PREUVE À AJOUTER])_
- **Voie :** ☒ Local (kind) ☐ Azure (AKS/ACR)
- **Date :** _(à compléter)_

> Brouillon de travail basé sur `livrables/TEMPLATE-rapport.md`. Les sorties de commandes
> marquées **[validé localement]** ont réellement été exécutées pendant la mise au point de
> ce dépôt (build, SBOM, scan, chaîne cosign complète sur un registre de test, scénarios
> Kyverno B et C). Les sorties marquées **[PREUVE À AJOUTER]** nécessitent votre propre
> compte GitHub/GHCR — remplacez-les par vos captures réelles avant de rendre ce rapport.

## 1. Contexte & objectif

La chaîne d'approvisionnement logicielle (code → build → registry → déploiement) est la
cible des attaques les plus coûteuses des dernières années : **SolarWinds** (2020, build
compromis, code signé et distribué à 18 000 clients), **Codecov** (2021, script CI modifié
exfiltrant des secrets), et **XZ Utils** (2024, backdoor introduite sur plusieurs années
dans une dépendance de confiance). Dans tous ces cas, un `docker pull` ou une vérification
de checksum classique n'aurait rien détecté : l'attaque a lieu **avant** la publication de
l'artefact final.

L'objectif de ce projet est de prouver, par des commandes vérifiables et non par confiance
implicite, que l'image qui tourne en production est **exactement** celle construite à
partir du code revu, sans altération entre le build et le déploiement.

## 2. Architecture de la chaîne

```
code → tests → build Docker → SBOM (Syft) → scan (Grype, gate CRITICAL)
     → push GHCR → signature (cosign, keyless) → attestation SBOM
     → attestation de provenance (SLSA) → déploiement K8s PAR DIGEST
     → admission control (Kyverno) → Pod accepté ou refusé
```

Voir [`docs/architecture.md`](../docs/architecture.md) pour le schéma détaillé et
[`README.md`](../README.md) pour le diagramme Mermaid.

| Outil | Rôle |
|---|---|
| Syft | Génère le SBOM (inventaire des composants) |
| Grype | Scanne le SBOM, casse la chaîne sur CVE `CRITICAL` corrigeable |
| cosign / Sigstore | Signe l'image et attache les attestations (Fulcio, Rekor) |
| Kyverno | Vérifie signature + attestations + registre + tag à l'admission Kubernetes |

## 3. Mise en œuvre

### SBOM (Syft)

Commande : `make sbom` (`scripts/generate-sbom.sh`), format SPDX JSON.

```
[validé localement] $ ./scripts/generate-sbom.sh
==> SBOM (SPDX JSON) de ghcr.io/local/scs-demo-app:0.1.0
==> 113 paquets détectés — résumé (jq) :
flask@3.0.3
python@3.12.13
...
==> SBOM complet : artifacts/sbom.spdx.json
```

[PREUVE À AJOUTER : sortie de `make sbom` sur VOTRE image `ghcr.io/<votre-user>/scs-demo-app`]

### Scan (Grype)

Politique : [`.grype.yaml`](../.grype.yaml) — `only-fixed: true`, `fail-on-severity: critical`.

```
[validé localement] $ ./scripts/scan.sh
==> Scan Grype de sbom:artifacts/sbom.spdx.json (politique : .grype.yaml)
NAME    INSTALLED  FIXED IN   ...  SEVERITY  ...
python  3.12.13    ...             High
pip     25.0.1     25.3            Medium
flask   3.0.3      3.1.3           Low
...
✅ Aucune vulnérabilité CRITICAL corrigeable — la chaîne peut continuer.
```

Le scénario pédagogique de casse volontaire (rétrograder Flask, voir
[`labs/lab1-build-sbom.md`](../labs/lab1-build-sbom.md) §1.4) n'a pas été rejoué pour ce
rapport — [PREUVE À AJOUTER : capture d'un `make scan` en échec après rétrogradation
temporaire de `app/requirements.txt`, puis restauration].

### Signature (cosign)

Mode testé pendant la validation : **par clé**, contre un registre Docker local temporaire
(`registry:2`), afin de vérifier la mécanique cosign sans dépendre d'un compte GitHub.

```
[validé localement] $ cosign sign --key cosign.key --yes "$REF"
Signing artifact...
Pushing signature to: localhost:5000/scs-demo-app

$ cosign verify --key cosign.pub "$REF"
Verification for localhost:5000/scs-demo-app@sha256:68fb... --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - Existence of the claims in the transparency log was verified offline
  - The signatures were verified against the specified public key
```

En production (CI, `make sign` avec le mode **keyless**), l'identité vérifiée est celle du
workflow GitHub Actions (OIDC), journalisée dans Rekor.
[PREUVE À AJOUTER : sortie de `make sign` puis `make verify` en mode keyless, sur votre
image GHCR, avec le lien Rekor correspondant]

### Attestations (SBOM + provenance)

```
[validé localement] $ cosign attest --key cosign.key --yes --predicate sbom.spdx.json --type spdxjson "$REF"
$ cosign attest --key cosign.key --yes --predicate provenance.json --type slsaprovenance "$REF"
$ cosign tree "$REF"
📦 Supply Chain Security Related artifacts for an image: localhost:5000/scs-demo-app@sha256:68fb...
└── 🔗 https://slsa.dev/provenance/v0.2 artifacts via OCI referrer: ...
└── 🔗 https://spdx.dev/Document artifacts via OCI referrer: ...
└── 🔗 https://sigstore.dev/cosign/sign/v1 artifacts via OCI referrer: ...
```

Les trois artefacts (signature, attestation SBOM, attestation de provenance) sont bien
rattachés au **même digest**, pas stockés comme fichiers isolés à côté de l'image.
[PREUVE À AJOUTER : `cosign tree` sur votre image GHCR + la provenance officielle générée
par `actions/attest-build-provenance` en CI]

### Admission (Kyverno)

```
[validé localement] $ kubectl get clusterpolicy
NAME                             ADMISSION   BACKGROUND   READY   MESSAGE
allowed-registries               true        true         True    Ready
disallow-latest-tag              true        true         True    Ready
require-provenance-attestation   true        false        True    Ready
verify-image-signature           true        false        True    Ready
```

Les 4 politiques sont en `validationFailureAction: Enforce` (bloquant, pas `Audit`).

## 4. Démonstration attaque / défense

| Scénario | Résultat | Contrôle déclenché | Preuve |
|---|---|---|---|
| Image légitime | ✅ acceptée | — | [PREUVE À AJOUTER] |
| Non signée | ❌ refusée | `verifyImages` (03) | [PREUVE À AJOUTER] |
| Modifiée après signature | ❌ refusée | signature/digest (03) | [PREUVE À AJOUTER] |
| Registre non autorisé | ❌ refusée | `allowed-registries` (01) | **[validé localement]** ci-dessous |
| `:latest` | ❌ refusée | `disallow-latest` (02) | **[validé localement]** ci-dessous |
| Sans provenance | ❌ refusée | `require-provenance` (04) | [PREUVE À AJOUTER] |

Sorties réelles obtenues via `make demo` (`scripts/run-demo.sh`) :

```
[validé localement] Test B — Tag :latest
Error from server: admission webhook "mutate.kyverno.svc-fail" denied the request:
resource Pod/app/attack-latest-tag was blocked due to the following policies
disallow-latest-tag:
  interdire-latest: 'validation error: Le tag :latest est interdit — utilisez un tag
    versionné ou un digest (@sha256:...). rule interdire-latest failed at path ...'
✅ DENIED (comme attendu).

[validé localement] Test C — Registre non autorisé
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
resource Pod/app/attack-untrusted-registry was blocked due to the following policies
allowed-registries:
  verifier-registry: 'validation error: Image refusée : seules les images de
    ghcr.io/local/ sont autorisées. rule verifier-registry failed at path ...'
✅ DENIED (comme attendu).
```

[PREUVE À AJOUTER : capture vidéo de la séquence complète A→F sur votre fork, lien inséré ici]

## 5. Positionnement SLSA & limites

- **Niveau visé et argumenté :** SLSA **L2** — build hébergé (GitHub Actions), provenance
  signée par une identité OIDC vérifiable, artefact référencé par digest.
- **Ce qui reste contournable :** un mainteneur disposant des droits d'écriture sur le
  workflow `.github/workflows/supply-chain.yml` pourrait le modifier pour produire une
  fausse provenance qui reste valide (le build n'est pas isolé d'une manipulation humaine
  — c'est précisément ce que SLSA L3 exige de rendre impossible). Le scan Grype ne détecte
  pas les vulnérabilités 0-day ou sans correctif disponible (`only-fixed: true`).
- **Pistes vers L3 :** générateur de provenance isolé et non contournable (ex.
  `slsa-framework/slsa-github-generator` en mode L3), séparation stricte des rôles sur le
  dépôt (revue obligatoire avant modification du workflow).

## 6. Reproductibilité

```bash
cp .env.example .env && $EDITOR .env
make check-prereqs
make build sbom scan
make push                        # nécessite votre compte GHCR
export DIGEST=sha256:...
make sign attest verify
make cluster-create kyverno-install
kubectl apply -f policies/kyverno/   # après avoir adapté <votre-user> / l'identité
make deploy
make demo
```

## 7. Bilan

[PREUVE À AJOUTER : ce que le groupe a appris, ce qu'il ferait différemment, répartition
du travail — spécifique à votre groupe, non pré-remplissable]

## Annexes

- Bugs réellement rencontrés et corrigés pendant la mise au point : voir
  [`docs/troubleshooting.md`](../docs/troubleshooting.md).
- Commandes complètes : voir `scripts/*.sh` et `Makefile`.
- Lien Rekor (mode keyless) : [PREUVE À AJOUTER]
