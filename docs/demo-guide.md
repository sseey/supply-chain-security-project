# Guide de démo (5-7 minutes)

Séquence de commandes pour la démo de soutenance. Chaque commande est réelle — aucune
sortie n'est simulée. Répétez-la au moins une fois avant la soutenance et **enregistrez une
capture vidéo** en plan B (cf. `labs/lab4-attaque-defense.md`).

## Prérequis avant la démo

```bash
cp .env.example .env        # puis éditez .env avec vos vraies valeurs
make check-prereqs          # tous les outils répondent ?
make cluster-create         # cluster kind up
make kyverno-install        # Kyverno installé + namespace 'app' créé
# Adaptez policies/kyverno/03 et 04 à VOTRE <votre-user> / identité keyless, puis :
kubectl apply -f policies/kyverno/
kubectl get clusterpolicy   # les 4 doivent être Ready
```

## 1. Montrer le digest (30 s)

```bash
make build sbom scan        # build local + SBOM + scan (échoue si CRITICAL corrigeable)
make push                    # push GHCR — notez le digest affiché
export DIGEST=sha256:...     # collez le digest affiché par 'make push'
```

> *"Voici le digest — l'empreinte immuable de l'image. C'est cette référence, jamais un
> tag, que nous allons signer et déployer."*

## 2. Signer et attester (1 min)

```bash
make sign      # signature keyless (OIDC)
make attest    # attestations SBOM + provenance
make verify    # vérifie la signature avec l'identité attendue
cosign tree "$(source scripts/lib.sh && echo "$GHCR_IMAGE")@$DIGEST"
```

> *"cosign tree montre 3 artefacts attachés au digest : la signature, l'attestation SBOM,
> l'attestation de provenance. Rien de tout ça n'est un fichier séparé qu'on pourrait
> perdre ou falsifier sans que le digest ne change."*

## 3. Déployer l'image légitime → ACCEPTED (30 s)

```bash
make deploy
kubectl -n app get pods
```

> *"Le pod tourne. Kyverno a vérifié : registre autorisé, pas de `:latest`, signature
> valide de notre identité, provenance présente."*

## 4. Déployer une image interdite → DENIED (2 min)

```bash
make demo
```

Ce script exécute réellement les scénarios B (tag `:latest`) et C (registre non autorisé),
et — si vous avez préparé les variantes d'attaque (voir `labs/lab4-attaque-defense.md`) —
D (non signée), E (sans provenance) et F (digest modifié). Chaque refus affiche le **vrai**
message de Kyverno.

> *"Regardez le message : ce n'est pas un texte que j'ai écrit, c'est la réponse du
> webhook d'admission Kubernetes."*

## 5. Prouver qu'aucun Pod interdit n'existe (15 s)

```bash
kubectl -n app get pods
```

> *"Seul le pod légitime tourne. Toutes les tentatives de contournement ont été refusées
> à l'admission, avant même la moindre tentative de démarrage."*

## Questions probables du jury → voir `livrables/soutenance-notes.md`
