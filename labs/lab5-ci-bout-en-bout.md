# Lab 5 (bonus) — Tout enchaîner en CI GitHub Actions (~1 h 30)

**But :** automatiser toute la chaîne dans un workflow. C'est ce qui vous fait réellement
progresser vers **SLSA L2** : le build a lieu sur une **plateforme hébergée**, l'identité de
signature est celle du **workflow** (OIDC), et rien n'est fait à la main.

> Un workflow de référence complet est fourni : [`../.github/workflows/supply-chain.yml`](../.github/workflows/supply-chain.yml).
> Lisez-le, adaptez-le, activez-le sur votre fork.

## 5.1 Ce que fait le pipeline

Le workflow a deux jobs : `test` (pytest, doit passer avant tout le reste) puis
`build-sign-attest`. À chaque `push` sur `main` :

1. **teste** l'application (`pytest`) — le build ne démarre pas si les tests échouent ;
2. **build** l'image (par digest, sorti par `docker/build-push-action`) ;
3. génère le **SBOM** (Syft) ;
4. **scanne** (Grype) et **casse** si `CRITICAL` corrigeable ;
5. **pousse** l'image sur GHCR ;
6. **signe** l'image en **keyless** (OIDC du runner, via `cosign sign`) ;
7. **attache** l'attestation **SBOM** (`cosign attest --type spdxjson`) ;
8. **attache** une provenance **pédagogique** (`cosign attest --type slsaprovenance`,
   predicate écrit à la main — conservée pour retrouver la structure exacte) **et** une
   provenance **officielle** via `actions/attest-build-provenance` (mécanisme natif
   GitHub, infalsifiable car généré par l'infrastructure GitHub elle-même) ;
9. **vérifie** la signature et les deux attestations (`cosign verify` /
   `verify-attestation`) — le workflow casse si la vérification échoue ;
10. **publie** `sbom.spdx.json` et `provenance.json` comme artefacts téléchargeables du run.

Aucune clé privée n'est stockée : l'identité est
`https://github.com/<user>/<repo>/.github/workflows/supply-chain.yml@refs/heads/main`.

## 5.2 Permissions requises (déjà dans le workflow)

```yaml
permissions:
  contents: read
  packages: write        # pousser sur GHCR
  id-token: write        # OIDC → signature keyless (Fulcio/Rekor)
  attestations: write    # attestation de provenance native GitHub
```

> Ces permissions sont déclarées au niveau du job `build-sign-attest`, pas au niveau global
> du workflow : le job `test` n'a besoin que de `contents: read` (principe du moindre
> privilège — un job qui ne fait que lancer pytest n'a aucune raison de pouvoir écrire sur GHCR).

## 5.3 Adapter la vérification Kyverno au mode keyless

En keyless, la politique `03-verify-signature.yaml` doit exiger **l'identité du workflow**,
pas une clé publique. Remplacez le bloc `keys:` par un bloc `keyless:` :

```yaml
attestors:
  - entries:
      - keyless:
          issuer: "https://token.actions.githubusercontent.com"
          subject: "https://github.com/<votre-user>/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main"
          rekor:
            url: "https://rekor.sigstore.dev"
```

> **C'est le vrai zero-trust :** le cluster n'accepte que ce qui a été signé **par ce workflow
> précis, sur cette branche précise**. Un attaquant qui pousse une image ne peut pas se faire
> passer pour ce workflow (il n'a pas l'OIDC du runner GitHub).

## 5.4 Vérifier de bout en bout

```bash
# Récupérer le digest produit par la CI (onglet Actions → summary, ou via crane/cosign) puis :
cosign verify \
  --certificate-identity "https://github.com/<user>/supply-chain-security-project/.github/workflows/supply-chain.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  ghcr.io/<user>/scs-demo-app@sha256:...
```

Déployez ce digest CI-signé sur le cluster ⇒ accepté. Poussez quoi que ce soit d'autre ⇒ refusé.

## ✅ Critères de sortie du lab

- [ ] Le workflow build + SBOM + scan + push + sign + attest passe au vert.
- [ ] `cosign verify` réussit avec l'**identité du workflow** (keyless).
- [ ] La politique Kyverno **keyless** accepte l'image CI et **refuse** le reste.
- [ ] Vous savez expliquer **pourquoi c'est SLSA ~L2** et ce qui manque pour **L3**.

---

## Discussion pour le rapport : SLSA L2 vs L3

| | Vous avez (L2-ish) | Il faudrait pour L3 |
|---|---|---|
| Build | Hébergé (GitHub Actions) | Build **isolé/éphémère** non contournable, paramètres non falsifiables |
| Provenance | Signée par l'OIDC du runner | Générée par un **générateur isolé** (ex. `slsa-github-generator` en mode L3) |
| Falsifiabilité | Un mainteneur avec droits peut altérer le workflow | Séparation stricte, revue obligatoire, provenance **infalsifiable** |

Soyez **honnêtes** dans le rapport : indiquez le niveau réellement atteint et ce qui reste contournable.
