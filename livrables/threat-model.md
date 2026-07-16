# Threat model — Chaîne d'approvisionnement logicielle

- **Groupe :** _(à compléter)_ · **Date :** _(à compléter)_

> Brouillon basé sur `livrables/TEMPLATE-threat-model.md`, complété avec les contrôles
> réellement implémentés dans ce dépôt (policies, scripts, workflow CI).

## 1. Actif à protéger

L'image Docker qui tourne dans le cluster Kubernetes doit être **exactement** celle
produite à partir du code revu, par la chaîne CI, sans altération entre le build et le
déploiement. Propriétés visées : **intégrité**, **authenticité**, **traçabilité**
(provenance).

## 2. Surface & acteurs de menace

- Dépendances tierces (amont) — ex. backdoor XZ Utils.
- Étape de CI compromise ou modifiée — ex. SolarWinds, Codecov.
- Registre compromis / image remplacée après publication.
- Accès cluster non autorisé (déploiement direct d'une image pirate).
- Développeur négligent (tag `:latest`, image non signée, digest non vérifié).
- Politique d'admission mal configurée ou contournée.

## 3. Table menaces → contrôles → couverture (STRIDE adapté)

| # | Menace | Catégorie STRIDE | Vecteur | Contrôle dans ce dépôt | Couverture | Résiduel |
|---|---|---|---|---|---|---|
| T1 | Développeur compromis pousse du code malveillant | Tampering | Commit/push | Revue de code (hors périmètre technique du POC), historique Git par membre | Faible | Dépend du process d'équipe, pas outillé ici |
| T2 | Dépôt Git compromis | Tampering | Accès GitHub | Branch protection (non configurée par ce POC), 2FA GitHub | Faible | Hors périmètre — à documenter comme limite |
| T3 | Dépendance malveillante (amont) | Tampering | `requirements.txt` | SBOM (Syft) + scan Grype (`fail-on-severity: critical`, `.grype.yaml`) | Moyenne | 0-day, vulnérabilité sans correctif |
| T4 | Runner CI compromis | Tampering / Elevation | GitHub Actions | Permissions minimales (`contents: read`, `packages: write`, `id-token: write`, `attestations: write`), pas de `continue-on-error` sur les gates | Moyenne | Un runner GitHub compromis reste un risque accepté (hors contrôle du dépôt) |
| T5 | Secret CI exfiltré | Information Disclosure | Logs/step CI | Signature **keyless** (aucune clé stockée) ; `GITHUB_TOKEN` scoping automatique | Forte | Un PAT personnel mal géré (mode par clé) reste un risque |
| T6 | Registre compromis / image remplacée | Tampering | Push direct au registre | Signature cosign liée au **digest**, `verifyImages` Kyverno | Forte | Compromission du build lui-même (avant signature) |
| T7 | Tag mutable substitué silencieusement | Tampering | `:latest` ou tag réutilisé | Policy `02-disallow-latest` + déploiement **par digest uniquement** | Forte | — |
| T8 | Accès Kubernetes détourné (déploiement direct) | Elevation | RBAC cluster | Admission Kyverno `Enforce` (signature + provenance + registre requis) | Forte | RBAC applicatif à durcir (hors périmètre POC) |
| T9 | Policy Kyverno modifiée ou désactivée | Elevation / Repudiation | Accès `ClusterPolicy` | RBAC Kubernetes limitant l'édition des `ClusterPolicy` (non implémenté dans ce POC — limite documentée) | Faible | À durcir : RBAC dédié + `PolicyException` auditées |
| T10 | Identité OIDC keyless trop permissive | Spoofing | `subject`/`issuer` mal configuré | Policy 03/04 exige un `subject` **exact** (repo + workflow + branche), pas de regex large | Forte | Une erreur de configuration (`subject` trop large) annulerait ce contrôle |
| T11 | Faux SBOM (fabriqué, non lié à l'image réelle) | Spoofing / Repudiation | Attestation forgée | Attestation SBOM **signée et liée au digest** (`cosign attest --type spdxjson`), pas un fichier isolé | Forte | Nécessite que la clé/l'identité de signature reste saine |
| T12 | Fausse provenance (prétendre un build hébergé qui n'a pas eu lieu) | Spoofing | Provenance fabriquée à la main | Provenance **officielle** en CI (`actions/attest-build-provenance`, infrastructure GitHub) en plus de la provenance pédagogique manuelle | Moyenne-Forte | Un mainteneur avec accès au workflow peut encore le modifier (limite SLSA L2 vs L3) |
| T13 | Déni de service par policy trop stricte | (hors STRIDE classique) | Erreur de policy bloquant tout déploiement légitime | `background: true` sur les policies de validation simple ; policies `verifyImages` ciblées uniquement sur `ghcr.io/<votre-user>/scs-demo-app*` (pas de blocage des namespaces système `kube-system`/`kyverno`) | Moyenne | Une erreur de configuration reste possible ; prévoir un mode `Audit` de repli documenté |

## 4. Ce qui reste hors périmètre / non couvert

- Compromission du **build** lui-même avant signature (viser SLSA L3 : build isolé et
  non contournable par un humain).
- Sécurité du poste développeur, gestion des secrets personnels (PAT), 2FA GitHub.
- Vulnérabilités **0-day** ou sans correctif disponible (le scan ne peut pas les bloquer).
- RBAC Kubernetes fin sur qui peut modifier les `ClusterPolicy` Kyverno (le POC suppose un
  cluster de démo à usage unique, pas un cluster multi-équipes en production).

## 5. Niveau SLSA visé vs atteint

| | Visé | Atteint | Justification |
|---|---|---|---|
| Provenance existe (L1) | ✅ | ✅ | Attestation `slsaprovenance` attachée à chaque image (pédagogique + officielle en CI) |
| Build hébergé + provenance signée (L2) | ✅ | ✅ | GitHub Actions + signature keyless OIDC + `actions/attest-build-provenance` |
| Build isolé infalsifiable (L3) | — | ✗ | Le workflow reste modifiable par un mainteneur ; pas de générateur de provenance isolé dédié |
