# Rapport — Chaîne d'approvisionnement logicielle sécurisée

- **Groupe :** HMLA - SMAIL Hicham, KHABIR Arshath, CARIOU Léon, KERBRAT Maxime
- **Fork :** `https://github.com/sseey/supply-chain-security-project` (branche `main`)
- **Voie :** ☒ Local (kind + Kyverno) ☐ Azure (AKS/ACR)
- **Date :** 16 juillet 2026

> Toutes les sorties de commandes de ce rapport ont été **réellement exécutées** — soit
> sur le poste de développement (build/SBOM/scan), soit dans GitHub Actions (CI), soit sur
> le cluster `kind` local (admission Kyverno). Aucune sortie n'est inventée. Les
> emplacements marqués `[CAPTURE D'ÉCRAN À INSÉRER ICI]` indiquent précisément où coller vos
> captures avant l'export en PDF.

---

## 1. Contexte & objectif

Les attaques de chaîne d'approvisionnement logicielle (SolarWinds 2020, Codecov 2021, XZ
Utils 2024) ne visent plus l'application elle-même mais le **processus qui la construit et
la publie**. Dans ces trois cas, l'artefact final semblait normal : aucun scan de
vulnérabilités classique, aucune vérification de checksum n'aurait détecté l'altération,
parce qu'elle a eu lieu **avant** la publication.

L'objectif de ce projet est de transformer un pipeline CI/CD classique en **chaîne
vérifiable** : chaque garantie (intégrité, authenticité, provenance) doit être prouvable
par une commande, et le cluster Kubernetes cible doit **refuser activement** tout artefact
qu'il ne peut pas prouver digne de confiance — pas seulement scanner et espérer.

---

## 2. Architecture de la chaîne

```
code → tests (pytest) → build Docker → SBOM (Syft) → scan (Grype, gate CRITICAL)
     → push GHCR → signature (cosign, keyless/OIDC) → attestation SBOM
     → attestation de provenance (SLSA, pédagogique + officielle GitHub) → push
     → déploiement Kubernetes PAR DIGEST → admission control (Kyverno)
     → Pod accepté (garanties prouvées) ou refusé (message d'admission explicite)
```

| Outil | Rôle | Où |
|---|---|---|
| pytest | Tests unitaires de l'app Flask | CI, job `test` |
| Syft | Génère le SBOM (SPDX JSON) | CI + local (`make sbom`) |
| Grype | Scanne le SBOM, casse sur CVE `CRITICAL` corrigeable | CI + local (`make scan`) |
| cosign / Sigstore | Signe l'image, attache les attestations (Fulcio, Rekor) | CI (keyless) + local (clé ou keyless) |
| GitHub Artifact Attestations | Provenance SLSA officielle, native GitHub | CI uniquement |
| Kyverno | Vérifie signature + attestations + registre + tag à l'admission | Cluster `kind` |

Schéma détaillé : `docs/architecture.md`.

```mermaid
flowchart TD
    A[Code source] --> B[Tests pytest]
    B --> C[Build Docker]
    C --> D[SBOM · Syft]
    D --> E{Scan Grype<br/>CRITICAL corrigeable ?}
    E -- oui --> X[❌ Pipeline cassé]
    E -- non --> F[Push GHCR]
    F --> G[Signature cosign<br/>keyless / OIDC]
    G --> H[Attestation SBOM]
    G --> I[Attestation provenance SLSA]
    H --> J[Image + preuves dans GHCR]
    I --> J
    J --> K[kubectl apply PAR DIGEST]
    K --> L{Admission Kyverno}
    L -- registre autorisé ?<br/>pas de :latest ?<br/>signature valide ?<br/>provenance présente ? --> M[✅ Pod ACCEPTED]
    L -- un contrôle échoue --> N[❌ Pod DENIED]

    style X fill:#c0392b,color:#fff
    style N fill:#c0392b,color:#fff
    style M fill:#27ae60,color:#fff
```

*(Rendu natif sur GitHub. Version texte de repli, pour l'export PDF/impression :)*

```
 code ──► build ──► SBOM (Syft) ──► scan (Grype) ──► SIGNATURE (cosign/Sigstore)
                                                        │
                                                        ├─► attestation SBOM
                                                        └─► attestation de PROVENANCE (SLSA)
                                                                    │
                                                             push ──► GHCR (registry)
                                                                    │
   ┌────────────────────────────────────────────────────────────────┘
   ▼
Cluster Kubernetes (kind / k3s) + KYVERNO (admission control)
   ├─ image signée par NOTRE identité ?          sinon ─► ❌ REFUSÉE
   ├─ attestation de provenance présente ?        sinon ─► ❌ REFUSÉE
   ├─ registry autorisé + tag par digest ?        sinon ─► ❌ REFUSÉE
   └─ pas de vulnérabilité CRITICAL non corrigée ? sinon ─► ❌ REFUSÉE
```

---

## 3. Mise en œuvre

### 3.1 Tests & build

L'application Flask (`app/`) expose `/health`, `/api/hello`, `/metrics`. Le `Dockerfile` est
multi-stage, tourne en utilisateur non-root (`appuser`, UID 10001), avec un healthcheck
Docker natif. Les tests (`pytest`) sont exécutés **avant** tout build dans un job CI dédié :
si les tests échouent, le job `build-sign-attest` ne démarre même pas (`needs: test`).

Run CI complet, réel, entièrement vert (`test` puis `build-sign-attest`, 2 min 11 s, 2
artefacts publiés) :

![Run GitHub Actions réussi](livrables/images/CI.png)

### 3.2 SBOM (Syft)

Génération réelle dans la CI, sur l'image poussée par ce run (par digest, pas par tag) :

![Étape Generate SBOM dans la CI](livrables/images/SBOM.png)

Résumé lisible du SBOM réel (téléchargé depuis les artefacts du run), lu avec `jq` :

```bash
jq -r '.packages[] | "\(.name)@\(.versionInfo // "?")"' sbom.spdx.json | sort -u | head -20
jq '.packages | length' sbom.spdx.json
```

![Résumé jq du SBOM réel — 113 paquets](livrables/images/SBOM-jq.png)

**113 paquets** confirmés (ligne finale de la capture), cohérent avec le SBOM généré côté CI.

### 3.3 Scan (Grype) et gate sur CRITICAL

Politique : [`.grype.yaml`](../.grype.yaml) — `only-fixed: true`, `fail-on-severity: critical`.
En CI, le scan est exécuté avec un `grype` installé et **épinglé à une version précise**
(voir §5 — un incident réel nous a appris à ne pas dépendre d'une action tierce qui embarque
un binaire figé).

```
NAME    INSTALLED  FIXED IN   SEVERITY
python  3.12.13    ...        High
pip     25.0.1     25.3       Medium
flask   3.0.3      3.1.3      Low
✅ Aucune vulnérabilité CRITICAL corrigeable — la chaîne peut continuer.
```

**Scénario pédagogique de casse volontaire, réellement rejoué en CI** (branche
`scenarios/sbom-critical-cve`) : ajout de `PyYAML==5.3.1` à `app/requirements.txt`
(dépendance non utilisée par le code — aucun impact sur les tests, seulement sur le scan).
Avant de choisir cette version, plusieurs candidats ont été testés en local avec `grype`
pour confirmer qu'ils produisent une vraie **CRITICAL corrigeable** (`Flask==2.0.1` seul ne
suffisait pas : uniquement du High/Medium dans la base actuelle). PyYAML 5.3.1 confirmé :
`GHSA-8q59-q68h-6hv4`, Critical, corrigé en 5.4.

![Scan Grype cassé en CI sur PyYAML 5.3.1 (CRITICAL)](livrables/images/CI-SBOM.png)

Le job s'arrête à cette étape (`Error: Process completed with exit code 2`) — la CI ne
va jamais jusqu'à la signature avec cette version. Version saine restaurée sur les autres
branches.

### 3.4 Signature (cosign, keyless)

Le workflow CI signe l'image avec l'identité OIDC du workflow lui-même — aucune clé privée
stockée :

```yaml
permissions:
  contents: read
  packages: write
  id-token: write        # OIDC → signature keyless (Fulcio/Rekor)
  attestations: write
```

Étape réelle de signature dans la CI (keyless, aucune clé stockée) — noter la ligne
`tlog entry created with index: 2172960058`, la preuve d'inscription dans **Rekor**, le
registre de transparence public :

![Étape Sign image keyless dans la CI](livrables/images/cosign.png)

Entrée Rekor correspondante, consultable publiquement (**https://search.sigstore.dev/?logIndex=2172960058**)
— le certificat éphémère Fulcio y est visible en clair : émetteur `sigstore-intermediate`,
validité de 10 minutes, identité `subject alternative name` = l'URL exacte du workflow
CI sur `features/LABS`, `OIDC Issuer` = `https://token.actions.githubusercontent.com`,
`Build Trigger` = `push`. C'est la preuve publique et immuable que cette signature a bien
été produite par ce workflow, à cet instant, sans qu'aucune clé privée n'ait été manipulée :

![Entrée Rekor complète avec certificat Fulcio](livrables/images/rekor.png)

Vérification, avec l'identité exacte du workflow attendue (repo + branche `main`) :

```bash
cosign verify \
  --certificate-identity "https://github.com/sseey/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/sseey/scs-demo-app@sha256:37a9f3e0d7e3be266863a7be7a2dbabf0759982b5e7e472150907f299fd8734c
```

### 3.5 Attestations (SBOM + provenance)

Le **Step Summary** du job `build-sign-attest` confirme les trois vérifications
(signature, attestation SBOM, attestation provenance) directement dans l'interface GitHub,
sans commande à taper :

![Step Summary du job build-sign-attest](livrables/images/CI-summary.png)

Preuve la plus forte : la page **Attestations** native de GitHub (générée par
`actions/attest-build-provenance`, en plus de l'attestation `cosign attest --type spdxjson`
et d'une provenance pédagogique manuelle conservée dans le workflow pour comprendre la
structure d'un predicate SLSA). Elle expose un **certificate summary** complet — issuer
OIDC, digest du commit source, référence du workflow, visibilité du dépôt — vérifiable par
n'importe qui via `gh attestation verify` :

![Page d'attestation officielle GitHub](livrables/images/GH-attestation.png)

*(Capture prise pendant le développement sur la branche `features/LABS` — la ligne
"Workflow File" y référence donc `@refs/heads/features/LABS`. Après le merge sur `main` et
un nouveau run CI, régénérez cette capture : elle référencera `@refs/heads/main`, cohérent
avec les policies Kyverno mises à jour au §3.6.)*

### 3.6 Admission (Kyverno)

Cluster `kind` local, Kyverno v1.14.5 (version épinglée — voir incident §5.2), 4 policies
en mode **`Enforce`** (bloquant, jamais `Audit`) :

```
$ kubectl get clusterpolicy
NAME                             ADMISSION   BACKGROUND   READY   MESSAGE
allowed-registries               true        true         True    Ready
disallow-latest-tag              true        true         True    Ready
require-provenance-attestation   true        false        True    Ready
verify-image-signature           true        false        True    Ready
```

Les policies 03/04 sont configurées en variante **keyless**, avec l'identité exacte du
workflow CI (`subject: https://github.com/sseey/.../supply-chain.yml@refs/heads/main`).

---

## 4. Démonstration attaque / défense

### Deux pipelines complémentaires, pas redondants

Le projet démontre les 6 scénarios **deux fois, par deux mécanismes différents**, qui ne
prouvent pas la même chose :

| | Pipeline **local** (`make demo`) | Pipeline **CI** (branches `scenarios/*`) |
|---|---|---|
| Où | Terminal, sur ce poste | GitHub Actions, runner **self-hosted** |
| Ce qu'il prouve | Le cluster refuse **en direct**, devant témoin | La chaîne complète (build→sign→attest→**déploie**) tient sans intervention manuelle |
| Déclenchement | Commande tapée à la demande | `git push` sur une branche dédiée |
| Valeur pour la soutenance | La preuve **live**, la plus convaincante | La preuve de **reproductibilité industrielle** |

**Pourquoi un runner self-hosted et pas `ubuntu-latest` pour le déploiement ?** Un runner
GitHub-hosted est une VM éphémère dans le cloud de GitHub : elle n'a **aucune route
réseau** vers le cluster `kind` de ce poste. Le job `deploy` du workflow tourne donc sur un
**runner self-hosted** (l'agent GitHub Actions installé sur cette VM Vagrant elle-même),
qui a accès à `kubectl`, au `kubeconfig` et au cluster local — exactement comme un
`gitlab-runner` en executor *shell*. Point de vigilance documenté et assumé : un runner
self-hosted sur un dépôt **public** accepte l'exécution de n'importe quel workflow
déclenché par une PR d'un tiers — il n'est donc démarré (`./run.sh`) que pendant les
sessions de test, jamais laissé actif en permanence.

**Comment les scénarios d'attaque sont simulés en CI, sans dupliquer le code du
workflow ?** Un seul fichier `.github/workflows/supply-chain.yml`, avec des conditions
`if: github.ref_name == 'scenarios/...'` sur les steps concernées (l'équivalent GitHub
Actions des `rules:`/`only:` GitLab). Le nom de la branche suffit à activer/désactiver
signature, attestations ou registre cible — aucun fichier à modifier pour créer un nouveau
scénario, juste une branche :

```bash
git checkout -b scenarios/unsigned-image main   # ex. : saute la signature sur cette branche
git push origin scenarios/unsigned-image
```

### Pipeline local : `make demo`

Script unique, réel, aucun résultat simulé : `make demo` (`scripts/run-demo.sh`). Résumé
final obtenu : **✅ Réussis : 6 — ❌ Échecs inattendus : 0**.

| # | Scénario | Résultat | Contrôle déclenché | Menace réelle correspondante |
|---|---|---|---|---|
| A | Image légitime, signée, attestée | ✅ **ACCEPTED** | — (toutes vérifications passées) | Cas nominal |
| B | Tag `:latest` | ❌ **DENIED** | `verify-image-signature` + `require-provenance-attestation` (manifeste introuvable) | Substitution silencieuse sous tag mutable |
| C | Registre non autorisé (`docker.io/nginx`) | ❌ **DENIED** | `allowed-registries` | Typosquatting / registre pirate |
| D | Image jamais signée | ❌ **DENIED** | `verify-image-signature` : `no signatures found` | Déploiement d'artefact non autorisé |
| E | Signée mais sans attestation de provenance | ❌ **DENIED** | `require-provenance-attestation` : `no matching attestations` | Absence de traçabilité |
| F | Image reconstruite après signature (digest différent) | ❌ **DENIED** | `verify-image-signature` : `no signatures found` pour ce digest | **SolarWinds** (artefact substitué) |

### Test A — image légitime acceptée

```
$ kubectl -n app get pods
NAME                            READY   STATUS    RESTARTS   AGE
scs-demo-app-7d447cdb44-82s2d   1/1     Running   0          28m
scs-demo-app-7d447cdb44-mhnvv   1/1     Running   0          28m
```

Vérification applicative, depuis le terminal et depuis le navigateur (via le NodePort du
Service, mappé sur `localhost:8080` par `cluster/kind-config.yaml`) :

![curl localhost:8080/health](livrables/images/curl.png)

![Navigateur sur localhost:8080](livrables/images/localhost.png)

### Tests B à F — refus réels avec message Kyverno

Sortie complète et réelle de `make demo` (`scripts/run-demo.sh`), en 3 captures
successives — pré-vérifications + Tests A/B/C, puis D/E/F, puis vérification finale et
résumé :

![make demo — partie 1 : pré-vérifications, Test A, B, C](livrables/images/demo1.png)

![make demo — partie 2 : Test D, E, F](livrables/images/demo2.png)

![make demo — partie 3 : vérification finale et résumé (6 réussis, 0 échec)](livrables/images/demo3.png)

Transcript texte des messages Kyverno (pour référence/recherche, contenu identique aux captures) :

```
Test B — Tag :latest
Error from server: admission webhook "mutate.kyverno.svc-fail" denied the request:
require-provenance-attestation:
  verifier-provenance: 'image attestations verification failed, verifiedCount: 0,
    requiredCount: 1, error: not found'
verify-image-signature:
  verifier-signature-cosign: 'failed to verify image ghcr.io/sseey/scs-demo-app:latest:
    image tag not found: MANIFEST_UNKNOWN: manifest unknown'
✅ DENIED (comme attendu).

Test C — Registre non autorisé
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
allowed-registries:
  verifier-registry: 'validation error: Image refusée : seules les images de
    ghcr.io/sseey/ sont autorisées.'
✅ DENIED (comme attendu).

Test D — Image non signée
verify-image-signature:
  verifier-signature-cosign: 'failed to verify image ...@sha256:c0bb0660...:
    no signatures found'
✅ DENIED (comme attendu).

Test E — Sans attestation de provenance
require-provenance-attestation:
  verifier-provenance: 'image attestations verification failed ... error: no matching attestations: '
✅ DENIED (comme attendu).

Test F — Digest modifié après signature
verify-image-signature:
  verifier-signature-cosign: 'failed to verify image ...@sha256:4722d215b825...:
    no signatures found'
✅ DENIED (comme attendu).

Vérification finale : aucun Pod interdit n'a été créé
NAME                            READY   STATUS    RESTARTS   AGE
scs-demo-app-7d447cdb44-82s2d   1/1     Running   0          28m
scs-demo-app-7d447cdb44-mhnvv   1/1     Running   0          28m
```

### Pipeline CI : les mêmes scénarios rejoués via `git push`, sans intervention manuelle

Pipeline nominal complet sur `main` — 3 jobs enchaînés, tous verts (`test` → `build-sign-attest`
→ `deploy`, ce dernier sur le runner self-hosted) :

![Pipeline complet vert sur main (test → build-sign-attest → deploy)](livrables/images/CI-main.png)

| Branche | Résultat CI | Cause exacte (log réel) |
|---|---|---|
| `main` | ✅ 3 jobs verts, déploiement ACCEPTED | — |
| `scenarios/sbom-critical-cve` | ❌ `build-sign-attest` casse au scan | PyYAML 5.3.1, CRITICAL corrigeable |
| `scenarios/unsigned-image` | ❌ `deploy` refusé | Signature absente (voir remarque ci-dessous) |
| `scenarios/wrong-registry` | ❌ `deploy` refusé | `allowed-registries` : `docker.io/library/nginx` hors `ghcr.io/sseey/` |
| `scenarios/missing-provenance` | ❌ `deploy` refusé | Provenance absente + identité de branche non reconnue (combiné, voir remarque) |
| `scenarios/tampered-digest` | ❌ `deploy` refusé | Digest reconstruit après coup, jamais signé (`no signatures found`) |

**`scenarios/wrong-registry`** — aucun build/push nécessaire : réutilise directement le
manifeste d'attaque `k8s/attacks/untrusted-registry.yaml` (image publique `nginx`, aucune
credential requise) :

![Refus CI — registre non autorisé](livrables/images/CI-wrong-registry.png)

**`scenarios/tampered-digest`** — un second build (contenu modifié via un `ARG CACHEBUST`
dans `app/Dockerfile`, jamais signé) est tenté au déploiement à la place du build normal
signé de cette branche. Résultat propre, une seule cause (`no signatures found`) :

![Refus CI — digest tamponné jamais signé](livrables/images/CI-tampered-digest.png)

**`scenarios/missing-provenance`** — même nuance que le Test E local : le message combine
`no matching attestations` (la raison recherchée) et `subject mismatch` (la policy attend
`main`, cette branche signe sous `scenarios/missing-provenance`) :

![Refus CI — provenance absente (cause combinée)](livrables/images/CI-missingprovenence.png)

**`scenarios/unsigned-image`** — `[PREUVE À VÉRIFIER : la capture actuellement dans
images/CI-unsigned.png est identique à celle de missing-provenance (même digest
fd369f1bf..., mêmes deux violations). Reprenez la vraie capture de ce scénario — elle doit
normalement montrer une seule cause, `no signatures found`, digest 479745e6..., sans
mention de subject mismatch, comme obtenu lors du premier test en direct.]`

### Honnêteté sur une nuance technique (esprit critique)

- **Test E** : le message combine "provenance absente" et "signature non reconnue", car
  l'image de test a été signée **manuellement en local avec une identité OIDC personnelle**
  (compte GitHub individuel), différente de l'identité du workflow CI que les policies
  attendent. Impossible d'usurper l'identité d'un workflow CI depuis un poste personnel —
  c'est une propriété de sécurité de Sigstore, pas une limite du projet.

---

## 5. Incidents réellement rencontrés et corrigés

Documentés en détail dans `docs/troubleshooting.md`. Résumé pour le rapport :

### 5.1 Kyverno incompatible avec Kubernetes du cluster kind

`kubectl apply` sur les CRD Kyverno échouait (`Too long: must have at most 262144 bytes`),
et la version la plus récente de Kyverno exigeait Kubernetes ≥ 1.31 (champ CRD
`selectableFields`), incompatible avec le nœud `kind` par défaut (Kubernetes 1.29).
**Correctif :** installation via `kubectl apply --server-side --force-conflicts` et
version de Kyverno épinglée (`v1.14.5`), validée compatible.

### 5.2 Faux positif de scan CRITICAL en CI

```
db could not be loaded: the vulnerability database was built 18 weeks ago (max allowed age is 5 days)
Error: Failed minimum severity level. Found vulnerabilities with level 'critical' or higher
```

`anchore/scan-action@v4` embarquait un `grype` figé (v0.80.0) dont la base de
vulnérabilités compatible avait expiré — **aucun paquet n'a réellement été scanné**, le
message était trompeur. **Correctif :** installation directe de `grype` en version
épinglée (`v0.115.0`), scan du SBOM déjà généré — identique en local et en CI.

### 5.3 `CreateContainerConfigError` puis `CrashLoopBackOff` au déploiement

Deux problèmes successifs, sans rapport avec Kyverno/la signature (l'annotation
`kyverno.io/verify-images: {"...":"pass"}` prouvait que l'admission avait déjà réussi) :

1. `runAsNonRoot: true` sans `runAsUser` explicite alors que le `Dockerfile` déclare
   `USER appuser` (un nom, pas un UID numérique) → le kubelet ne peut pas vérifier que
   l'utilisateur n'est pas root. **Correctif :** `runAsUser: 10001` explicite dans
   `k8s/deployment.yaml`.
2. `readOnlyRootFilesystem: true` empêchait gunicorn d'écrire son fichier temporaire de
   worker (`tempfile.mkstemp`). **Correctif :** volume `emptyDir` monté sur `/tmp`.

Ces deux correctifs ont été appliqués **sans reconstruire ni re-signer l'image** — preuve
que la sécurité du pod (securityContext) et la sécurité de la chaîne (signature/attestations)
sont deux couches indépendantes.

---

## 6. Positionnement SLSA & limites

| | Visé | Atteint | Justification |
|---|---|---|---|
| Provenance existe (L1) | ✅ | ✅ | Attestation `slsaprovenance` (pédagogique + officielle GitHub) attachée à chaque image |
| Build hébergé + provenance signée (L2) | ✅ | ✅ | GitHub Actions, signature keyless OIDC, `actions/attest-build-provenance` |
| Build isolé infalsifiable (L3) | — | ✗ | Un mainteneur avec accès au workflow peut encore le modifier pour produire une fausse provenance qui reste valide |

**Ce qui reste contournable dans notre setup**, honnêtement :
- Le scan Grype (`only-fixed: true`) ne couvre pas les 0-day ni les CVE sans correctif.
- Aucun RBAC dédié n'empêche un utilisateur du cluster de modifier/supprimer les
  `ClusterPolicy` Kyverno elles-mêmes (hors périmètre du POC).
- La provenance pédagogique manuelle (`cosign attest --type slsaprovenance` avec un
  predicate écrit à la main) n'a de valeur que doublée par la provenance officielle
  GitHub — elle est conservée uniquement à des fins pédagogiques (comprendre la structure).

Table complète menaces → contrôles → couverture : `livrables/threat-model.md`.

---

## 7. Reproductibilité

```bash
git clone https://github.com/sseey/supply-chain-security-project.git
cd supply-chain-security-project
cp .env.example .env               # puis éditer GITHUB_USERNAME=sseey, etc.
make check-prereqs
make build sbom scan
make push                          # nécessite docker login ghcr.io (PAT write:packages)
export DIGEST=sha256:...
make sign attest verify
make cluster-create kyverno-install
# adapter policies/kyverno/03 et 04 (subject keyless = votre identité + branche)
kubectl apply -f policies/kyverno/
make deploy
make demo
```

Chaque étape est scriptée (`scripts/*.sh`, `Makefile`) — aucune commande manuelle
non documentée n'a été nécessaire pour reconstruire la démo de zéro.

---

## 8. Bilan

**Ce que ce projet nous a apporté.** Avant ce module, nos pipelines s'arrêtaient à
`lint → build → scan (Trivy) → push → deploy` — une chaîne qui *scanne et espère*. Ce
projet nous a fait réaliser qu'il manquait des maillons entiers à ce schéma, invisibles
tant qu'on ne se pose pas la question « qu'est-ce qui prouve que l'image déployée est
celle qui a été scannée ? » :

- **La signature (cosign/Sigstore)** — un scan vert ne prouve rien sur l'artefact
  *déployé* si rien ne relie cryptographiquement l'image en production au résultat du scan.
  Avant, rien n'empêchait un `docker push` par-dessus le même tag après le scan.
- **Le SBOM comme attestation, pas comme simple fichier** — on savait générer un SBOM,
  mais pas qu'un fichier isolé ne prouve rien : il faut l'**attacher au digest** par une
  attestation signée pour qu'il ait une valeur de preuve.
- **Les règles sur le registre et le tag** — on déployait par tag sans y penser. Ce projet
  nous a montré concrètement (l'incident du §5) qu'un tag mutable réintroduit exactement le
  risque qu'on croit avoir éliminé avec le scan.
- **L'admission control** — la vraie différence avec ce qu'on faisait avant : on avait un
  `deploy` en fin de pipeline qui appliquait sans jamais vérifier quoi que ce soit côté
  cluster. Kyverno déplace le contrôle **au moment du déploiement**, pas seulement au
  moment du build.

**Ce qu'on fera différemment à l'avenir** : ajouter systématiquement signature +
attestations + admission control à nos pipelines existants, pas seulement le scan — et
déployer par digest par défaut, plus jamais par tag, même en interne.

**Où est réellement passé le temps.** La majorité du temps de mise au point a été
consacrée au débogage d'incompatibilités d'infrastructure (Kyverno/Kubernetes, action CI
obsolète, `securityContext`) plutôt qu'à la logique de sécurité elle-même (signature,
attestations, policies) — ce qui illustre concrètement que la difficulté d'un projet
supply-chain n'est pas uniquement cryptographique, mais aussi opérationnelle.

`[PREUVE À AJOUTER : répartition du travail entre membres du groupe]`

## Annexes

- Incidents et correctifs détaillés : `docs/troubleshooting.md`
- Guide de démo pas à pas : `docs/demo-guide.md`
- Notes de soutenance et Q/R anticipées : `livrables/soutenance-notes.md`
- Threat model complet : `livrables/threat-model.md`
- Lien Rekor (signature keyless) : https://search.sigstore.dev/?logIndex=2172960058
- Lien de l'attestation officielle GitHub : https://github.com/sseey/supply-chain-security-project/attestations/35448887
- Lien du run CI de référence : https://github.com/sseey/supply-chain-security-project/actions/runs/29416460505
  *(run réalisé sur `features/LABS` avant merge — après le merge sur `main`, remplacez par l'URL du run correspondant sur `main`)*

---

# 🔐 Projet — Sécuriser la chaîne d'approvisionnement logicielle (Software Supply Chain Security / SLSA)

> **Module : Projet Technique — 5ᵉ année DevOps, Cloud & Infrastructure**
> Format : **3 jours** · ~**1,5 jour de projet** + **QCM** + **soutenance** (après-midi du dernier jour).

## Le pitch en une phrase

Vous avez déjà construit des pipelines CI/CD. Ici, on répond à la question que se
posent aujourd'hui toutes les équipes DevSecOps : **« comment prouver qu'une image
qui tourne en production est bien celle que *nous* avons construite, à partir du code
que *nous* avons revu — et pas une version piégée ? »**

Vous allez transformer un pipeline classique en **chaîne d'approvisionnement vérifiable**,
et déployer un cluster qui **refuse activement** toute image qu'il ne peut pas prouver
digne de confiance.

```
 code ──► build ──► SBOM (Syft) ──► scan (Grype) ──► SIGNATURE (cosign/Sigstore)
                                                        │
                                                        ├─► attestation SBOM
                                                        └─► attestation de PROVENANCE (SLSA)
                                                                    │
                                                             push ──► GHCR (registry)
                                                                    │
   ┌────────────────────────────────────────────────────────────────┘
   ▼
Cluster Kubernetes (kind / k3s) + KYVERNO (admission control)
   ├─ image signée par NOTRE identité ?          sinon ─► ❌ REFUSÉE
   ├─ attestation de provenance présente ?        sinon ─► ❌ REFUSÉE
   ├─ registry autorisé + tag par digest ?        sinon ─► ❌ REFUSÉE
   └─ pas de vulnérabilité CRITICAL non corrigée ? sinon ─► ❌ REFUSÉE
```

**La démo de soutenance :** vous déployez votre image signée → ✅ elle tourne.
Vous déployez une image *non signée* ou *modifiée après signature* → ❌ **le cluster la bloque**,
en direct.

### Diagramme d'architecture

```mermaid
flowchart TD
    A[Code source] --> B[Tests pytest]
    B --> C[Build Docker]
    C --> D[SBOM · Syft]
    D --> E{Scan Grype<br/>CRITICAL corrigeable ?}
    E -- oui --> X[❌ Pipeline cassé]
    E -- non --> F[Push GHCR]
    F --> G[Signature cosign<br/>keyless / OIDC]
    G --> H[Attestation SBOM]
    G --> I[Attestation provenance SLSA]
    H --> J[Image + preuves dans GHCR]
    I --> J
    J --> K[kubectl apply PAR DIGEST]
    K --> L{Admission Kyverno}
    L -- registre autorisé ?<br/>pas de :latest ?<br/>signature valide ?<br/>provenance présente ? --> M[✅ Pod ACCEPTED]
    L -- un contrôle échoue --> N[❌ Pod DENIED]

    style X fill:#c0392b,color:#fff
    style N fill:#c0392b,color:#fff
    style M fill:#27ae60,color:#fff
```

## En quoi c'est nouveau (≠ CI/CD que vous avez déjà fait)

| Vous savez déjà faire | Ce projet ajoute (le vrai sujet) |
|---|---|
| Build une image dans un pipeline | Prouver **qui** l'a construite et **comment** (provenance SLSA) |
| Lancer Trivy dans la CI | Produire un **SBOM** signé et **attaché** à l'image comme attestation |
| `kubectl apply` d'un Deployment | Un cluster à **admission control** qui *rejette* l'inconnu (Kyverno) |
| « le scan est vert » | **Vérifier la signature** au moment du déploiement (zero-trust) |
| Sécurité = étape du pipeline | Sécurité = **propriété vérifiable** de bout en bout |

## Pourquoi ça compte (contexte réel)

Les attaques 2020-2024 ne visent plus votre app : elles visent **votre chaîne de build**.
- **SolarWinds (2020)** — du code malveillant injecté dans le *build*, signé par l'éditeur, poussé à 18 000 clients.
- **Codecov (2021)** — un script CI modifié exfiltrant les secrets des pipelines de milliers de projets.
- **dependency confusion (2021)** — de faux paquets internes publiés sur les registries publics.
- **XZ Utils / `liblzma` (2024)** — une backdoor introduite sur *3 ans* dans une dépendance open source.

La réponse de l'industrie : **SLSA**, **Sigstore/cosign**, **SBOM**, **attestations**, et
**policy-as-code à l'admission**. C'est exactement ce que vous allez mettre en œuvre.

## Structure du dépôt

```
supply-chain-security-project/
├── README.md                    ← vous êtes ici
├── docs/                        présentation, prérequis, planning, évaluation, architecture,
│                                 guide de démo, dépannage, fiche de révision
├── app/                         application fournie (API Flask) — le sujet, c'est la chaîne autour
├── labs/                        les 5 labs guidés (le cœur des 1,5 jour)
│   ├── lab0-setup.md
│   ├── lab1-build-sbom.md
│   ├── lab2-sign-attest.md
│   ├── lab3-cluster-admission.md
│   ├── lab4-attaque-defense.md
│   └── lab5-ci-bout-en-bout.md  (bonus / intégration finale)
├── scripts/                     automatisation de la chaîne (voir Makefile ci-dessous)
├── artifacts/                   SBOM/provenance générés localement (ignorés par git)
├── cluster/                     config kind + install Kyverno
├── policies/kyverno/            les politiques d'admission (le "gardien" du cluster)
├── k8s/                         manifs de déploiement de l'app + k8s/attacks/ (scénarios de refus)
├── .github/workflows/           pipeline supply-chain complet (référence)
├── evaluation/                  QCM + corrigé + grilles (soutenance & rapport)
├── livrables/                   rapport, threat model, notes de soutenance
├── .env.example                 paramètres non secrets à copier en .env et personnaliser
└── Makefile                     toutes les étapes de la chaîne en une commande (make help)
```

## Par où commencer

1. Lisez [`docs/00-presentation-projet.md`](docs/00-presentation-projet.md) puis [`docs/02-planning-3-jours.md`](docs/02-planning-3-jours.md).
2. Installez les outils : [`docs/01-prerequis-setup.md`](docs/01-prerequis-setup.md).
3. Copiez `.env.example` en `.env` et remplacez les placeholders `<...>` par vos valeurs (voir
   [`docs/01-prerequis-setup.md`](docs/01-prerequis-setup.md)).
4. Enchaînez les labs [`labs/lab0-setup.md`](labs/lab0-setup.md) → `lab4` — chaque lab explique la
   commande brute **et** le script `make`/`scripts/*.sh` équivalent.
5. Préparez vos [livrables](docs/03-livrables-evaluation.md) et votre démo
   ([`docs/demo-guide.md`](docs/demo-guide.md)).

## Automatisation (`make`)

Toutes les étapes de la chaîne sont scriptées dans `scripts/` et exposées via `make` :

```bash
make help             # liste toutes les cibles
make check-prereqs    # vérifie les outils installés (ou : ./scripts/check-prerequisites.sh)
make build sbom scan  # build → SBOM → scan (100% local, aucun compte requis)
make push             # authentification GHCR + push (nécessite votre compte)
make sign attest       # signature keyless + attestations (export DIGEST=sha256:... requis)
make verify           # vérifie signature + identité
make cluster-create kyverno-install   # cluster kind + Kyverno
make deploy           # déploie PAR DIGEST (export DIGEST=sha256:...)
make demo             # scénarios d'attaque/défense réels (kubectl + Kyverno)
```

Aucune cible ne masque un échec : un scan qui casse, une signature invalide ou une politique
qui refuse font échouer la commande avec le vrai message d'erreur.

> **Voies d'exécution :** tout tourne **en local** (Docker + `kind` ou `k3s`), *aucun cloud requis*.
> Une variante **Azure** (AKS + Azure Container Registry + politiques) est indiquée en encart pour
> les groupes disposant de la licence Student.
