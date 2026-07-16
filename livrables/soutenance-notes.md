# Notes de soutenance

Support de présentation courte (12 min présentation + 5 min Q/R). À personnaliser avec vos
éléments de groupe ; la trame et les réponses ci-dessous sont réutilisables telles quelles.

## 1. Le problème (1 min)

« Un pipeline CI/CD classique construit, teste, scanne, déploie. Mais rien ne prouve que
l'image qui tourne en prod est celle qui a été construite à partir du code revu. SolarWinds,
Codecov, XZ Utils : dans les trois cas, l'attaque a eu lieu **avant** la publication finale,
et personne ne l'a détectée en vérifiant l'artefact livré. »

## 2. Architecture (2 min)

Montrer le schéma de `docs/architecture.md` ou le diagramme Mermaid du README. Insister sur
le point clé : **rien n'est fait confiance par défaut** — chaque étape produit une preuve
vérifiable par la suivante.

## 3. SBOM (1 min)

« Syft génère l'inventaire exact de l'image : 113 paquets pour notre image de démo. Grype
scanne ce SBOM et **casse la chaîne** si une CVE `CRITICAL` corrigeable est détectée —
`.grype.yaml` documente cette politique. » Montrer `make sbom` + `make scan`.

## 4. Signature (2 min)

« cosign signe l'image **par digest**, jamais par tag. En CI, la signature est **keyless** :
pas de clé privée à gérer, l'identité est celle du workflow GitHub, prouvée par un
certificat éphémère Fulcio et journalisée dans Rekor, un registre public immuable. » Montrer
`make sign` + `make verify`.

## 5. Attestations (1 min)

« Deux attestations sont attachées au même digest : le SBOM et la provenance. `cosign tree`
montre les trois artefacts (signature + 2 attestations) rattachés à l'image — pas des
fichiers isolés qu'on pourrait perdre ou remplacer sans que le digest ne change. »

## 6. Provenance (1 min)

« La provenance répond à qui/quoi/quand : quel commit, quel workflow, quel builder. En CI,
on utilise `actions/attest-build-provenance`, le mécanisme officiel GitHub — plus fiable
qu'une provenance écrite à la main, car générée par l'infrastructure GitHub elle-même. »

## 7. Kyverno (2 min)

« Kyverno s'installe comme admission webhook : il intercepte la création d'un Pod **avant**
qu'il existe. Quatre politiques, toutes en `Enforce` (pas `Audit`) : registre autorisé, pas
de `:latest`, signature valide de notre identité, provenance présente. »

## 8. Démonstration live (5-7 min)

Suivre `docs/demo-guide.md` pas à pas : digest → signature/attestations → déploiement
légitime (ACCEPTED) → tentatives interdites (`make demo`, DENIED en direct, vrais messages
Kyverno) → vérification qu'aucun Pod interdit n'existe.

## 9. Limites (1 min)

« Nous atteignons SLSA **L2** : build hébergé, provenance signée par une identité
vérifiable. Nous n'atteignons pas L3 : un mainteneur avec accès au workflow pourrait encore
le modifier pour produire une fausse provenance qui reste valide. Le scan ne couvre pas les
0-day. » Voir `livrables/threat-model.md` §5.

## 10. Conclusion (30 s)

« On est passés d'un pipeline qui *scanne et espère* à un cluster qui *vérifie et bloque*.
Chaque garantie qu'on annonce est prouvable par une commande — pas une affirmation. »

---

## Questions probables du jury et réponses courtes

**« Un `docker pull` vérifie-t-il la signature ? »**
Non. `docker pull` ne vérifie rien par défaut. La vérification a lieu **à l'admission
Kubernetes**, via le webhook Kyverno, avant que le Pod ne soit créé.

**« Prouvez que votre image est signée, sans faire confiance au tag. »**
`cosign verify` sur le **digest**, pas le tag — montrer la sortie avec l'identité vérifiée
(clé ou certificat OIDC + issuer).

**« Quelle attaque réelle chacun de vos contrôles mitige-t-il ? »**
Voir le tableau de `livrables/threat-model.md` §3 — un contrôle par ligne, avec la menace
correspondante (SolarWinds → signature liée au digest ; Codecov → permissions CI
minimales + keyless ; XZ Utils → SBOM + scan).

**« Quel niveau SLSA atteignez-vous vraiment ? Qu'est-ce qui reste falsifiable ? »**
L2. Un mainteneur avec droits d'écriture sur le workflow reste en capacité de produire une
fausse provenance qui passera nos contrôles (le build n'est pas isolé d'une manipulation
humaine — c'est ce que L3 empêcherait).

**« Différence entre `Audit` et `Enforce` ? Laquelle avez-vous, pourquoi ? »**
`Audit` journalise sans bloquer (utile en migration progressive) ; `Enforce` bloque
réellement à l'admission. Nos 4 politiques sont en `Enforce` — sans ça, la démo ne
prouverait rien.

**« Keyless vs par clé : qu'avez-vous choisi, quels compromis ? »**
Keyless en CI (aucune clé à protéger, identité liée au workflow, traçable dans Rekor) ; par
clé utilisé uniquement pour comprendre la mécanique en local (Lab 2) — la clé privée y est
un secret à protéger (jamais commitée, `.gitignore` dédié).

**« Que se passe-t-il si je pousse une image identique à la vôtre mais depuis mon propre
fork ? »**
Elle serait refusée : la policy vérifie le **registre exact** (`ghcr.io/<votre-user>/...`)
et, en keyless, le `subject` OIDC exact (repo + workflow + branche) — un autre fork ne peut
pas produire cette identité.

**« Pourquoi le scan Grype ne suffit-il pas à sécuriser la chaîne ? »**
Le scan détecte des vulnérabilités **connues au moment du build**. Il ne prouve pas que
l'image *déployée* est celle qui a été scannée — c'est le rôle de la signature + admission.

**« Qu'est-ce qui reste hors de portée de ce projet ? »**
La compromission du build lui-même avant signature, la sécurité du poste développeur, les
vulnérabilités 0-day, et le RBAC fin sur qui peut modifier les policies Kyverno — voir
`livrables/threat-model.md` §4.
