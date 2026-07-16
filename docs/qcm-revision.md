# Fiche de révision personnelle (QCM)

Ceci est une fiche de révision des **concepts** du module, rédigée pour préparer le QCM
individuel. Ce n'est **pas** le QCM lui-même (distribué par l'encadrant le jour de
l'épreuve, cf. `docs/03-livrables-evaluation.md`).

## SLSA

- **SLSA** = *Supply-chain Levels for Software Artifacts*, référentiel de maturité OpenSSF.
- **L1** : la provenance existe (un enregistrement de comment l'artefact a été construit).
- **L2** : build **hébergé** (pas sur un poste de dev) + provenance **signée**.
- **L3** : build **isolé et infalsifiable**, paramètres non contournables même par un
  mainteneur ayant des droits d'écriture.
- Ce projet vise **L2** : GitHub Actions (hébergé) + provenance signée par OIDC. Ce qui
  manque pour L3 : un mainteneur avec accès au workflow pourrait encore le modifier pour
  produire une fausse provenance — le build n'est pas isolé d'une manipulation humaine.

## SBOM

- *Software Bill of Materials* : liste exhaustive des composants (paquets, versions) d'un
  artefact.
- Formats principaux : **SPDX** et **CycloneDX**.
- Généré ici avec **Syft**, scanné avec **Grype**.
- Un SBOM répond à « qu'est-ce qui tourne chez moi ? », pas « est-ce vulnérable ? » (c'est
  le rôle du scanner).

## Sigstore / cosign

- **cosign** : outil de signature d'artefacts OCI (images, SBOM, provenance).
- **Fulcio** : autorité de certification qui émet des certificats **éphémères** liés à une
  identité OIDC (pas de clé privée à gérer en mode keyless).
- **Rekor** : journal de transparence **public et immuable** qui enregistre chaque
  signature keyless — preuve que la signature a bien eu lieu à un instant donné.
- Mode **par clé** : simple à comprendre, mais la clé privée est un secret à protéger.
- Mode **keyless** : l'identité vérifiée est celle du **workflow CI** (émetteur OIDC +
  sujet exact), pas une personne physique.

## Attestations

- Une **attestation** = une affirmation **signée** rattachée à un artefact (pas un fichier
  isolé à côté de l'image).
- Deux attestations utilisées ici : le **SBOM** (`--type spdxjson`) et la **provenance**
  (`--type slsaprovenance`).
- Différence clé : un fichier `sbom.json` seul ne prouve rien sur son origine ; une
  attestation SBOM est **cryptographiquement liée au digest exact** de l'image.

## Admission control / Kyverno

- Kyverno s'installe comme **admission webhook** : il intercepte la création d'un Pod
  **avant** qu'il existe, et peut la refuser.
- `validationFailureAction: Enforce` = bloque. `Audit` = journalise sans bloquer.
- `verifyImages` vérifie signature/attestations ; `validate` avec `pattern` vérifie le
  texte de la référence d'image (registre, tag).
- **Scan ≠ vérification à l'admission** : un scan (Grype) détecte des vulnérabilités
  *au moment du build* ; l'admission control vérifie *au moment du déploiement* que
  l'artefact correspond bien à ce qui a été prouvé plus tôt (signature, provenance).

## Digest vs tag

- Un tag (`:latest`, `:v1`) est **mutable** : il peut être réassigné à un nouveau contenu
  sans que la référence change.
- Un digest (`@sha256:...`) est le **hash du contenu** : s'il change, la référence change.
- Signer par digest et déployer par digest empêche la substitution silencieuse (scénario
  SolarWinds : remplacer le contenu sans que personne ne le remarque).

## Attaques réelles citées dans le cours

- **SolarWinds (2020)** : build compromis, code malveillant signé et distribué.
- **Codecov (2021)** : script CI modifié, secrets exfiltrés en masse.
- **Dependency confusion (2021)** : paquets internes usurpés côté registry public.
- **XZ Utils (2024)** : backdoor introduite sur plusieurs années dans une dépendance
  open source de confiance.

## Questions à se poser (auto-test)

1. Pourquoi un `docker pull` ne vérifie-t-il rien ?
2. Où se situe exactement la vérification de signature dans l'architecture de ce projet ?
3. Que se passe-t-il si je signe un tag plutôt qu'un digest ?
4. Pourquoi Rekor est-il utile même si Fulcio délivre déjà un certificat ?
5. Quelle est la différence entre `Audit` et `Enforce`, et pourquoi la démo doit être en
   `Enforce` ?
6. Quel contrôle mitige quelle menace (voir tableau dans `labs/lab4-attaque-defense.md`) ?
