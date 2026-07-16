# Dépannage

Problèmes réellement rencontrés pendant la mise au point de ce dépôt (pas une liste
théorique) — avec la cause exacte et le correctif appliqué.

## CI : `Error: Failed minimum severity level` alors qu'aucune CVE critique n'existe

**Symptôme réel observé :**
```
Executing: grype -o sarif --fail-on critical --only-fixed ghcr.io/<user>/scs-demo-app@sha256:...
db could not be loaded: the vulnerability database was built 18 weeks ago (max allowed age is 5 days)
Error: Failed minimum severity level. Found vulnerabilities with level 'critical' or higher
```

**Cause :** l'action `anchore/scan-action@v4` (une ancienne version majeure, alors que
`v7` est la version maintenue au moment de la rédaction) embarque un binaire `grype`
figé (`v0.80.0`) dont la base de vulnérabilités compatible a fini par dépasser l'âge
maximal accepté par défaut (5 jours). `grype` refuse alors de charger la DB et sort en
erreur — l'action interprète **n'importe quelle sortie non nulle** de `grype` comme
« vulnérabilités critiques trouvées », ce qui est trompeur : **aucun paquet n'a été
réellement scanné**, ce n'est pas une vraie détection.

**Correctif :** ne plus dépendre du wrapper `anchore/scan-action`. Le workflow installe
maintenant `grype` directement, à une version épinglée et testée (`v0.115.0`), et scanne
le SBOM déjà généré (`grype sbom:sbom.spdx.json`) — exactement la même commande que
`scripts/scan.sh` en local, donc le même comportement partout.

**Leçon générale :** une action GitHub épinglée sur une **vieille version majeure**
(`@v4` alors que `@v7` existe) peut embarquer des outils obsolètes qui cassent
silencieusement avec le temps (bases de données qui expirent), même sans qu'aucune ligne
de votre code n'ait changé. Préférez, quand c'est simple, installer l'outil vous-même à
une version que vous choisissez et pouvez mettre à jour consciemment.

## Kyverno : `CustomResourceDefinition ... Too long: must have at most 262144 bytes`

**Cause :** `kubectl apply` stocke le manifeste entier dans l'annotation
`kubectl.kubernetes.io/last-applied-configuration`. Les CRD de Kyverno sont volumineuses
et dépassent cette limite.

**Correctif :** installez Kyverno avec `kubectl apply --server-side --force-conflicts`
(déjà fait par `scripts/install-kyverno.sh`) plutôt qu'un `apply` classique. Ne stocke pas
l'annotation, donc pas de limite de taille.

## Kyverno : `unknown field "spec.versions[0].selectableFields"`

**Cause :** les toutes dernières versions de Kyverno embarquent des CRD utilisant le champ
`selectableFields`, une fonctionnalité de Kubernetes ≥ 1.31. Un cluster `kind` par défaut
(ou toute version de Kubernetes plus ancienne) refuse cette CRD.

**Correctif :** `scripts/install-kyverno.sh` épingle une version de Kyverno validée
compatible avec Kubernetes 1.29/1.30 (`KYVERNO_VERSION=v1.14.5` par défaut). Si vous
utilisez un cluster avec un Kubernetes plus récent (≥ 1.31), vous pouvez viser une version
plus récente de Kyverno — vérifiez simplement la compatibilité avant de changer la valeur
par défaut. Ne mélangez jamais "dernière version de kind" et "dernière version de Kyverno"
sans avoir testé la combinaison.

## `kubectl get clusterpolicy` affiche `Ready: True` alors que ma clé publique est un placeholder

**Cause :** Kyverno valide la **structure** de la policy à l'admission (le YAML est
syntaxiquement correct), pas le **contenu cryptographique** de la clé. Une policy avec
`COLLEZ_ICI_LE_CONTENU_DE_cosign.pub` non remplacé sera donc `Ready: True`, mais **toute**
image sera refusée à l'admission (la vérification de signature échouera systématiquement,
avec un message `PEM decoding failed`).

**Ce que ça veut dire pour vous :** `Ready: True` ne prouve pas que votre policy est
correctement configurée — seul un test réel (`make demo`, ou un `kubectl run` avec une
image réellement signée) le prouve.

## Le tag `:latest` ou une image imaginaire est quand même refusé sans jamais avoir existé

C'est normal et voulu : Kyverno est un **admission webhook**. Il évalue la requête de
création du Pod (le texte de la référence d'image) **avant** que Kubernetes tente de tirer
l'image. Une image qui n'existe pas peut donc parfaitement être utilisée pour tester les
policies `01-allowed-registries` et `02-disallow-latest` sans compte GHCR ni image réelle.

En revanche, les policies `03-verify-signature` et `04-require-provenance` ont besoin de
contacter le **vrai registry** pour lire la signature/l'attestation attachée au digest :
elles ne peuvent être testées de bout en bout qu'avec une image réellement poussée et
signée sur GHCR (ou tout registre OCI joignable depuis le cluster).

## Bash : `${VAR:?message avec une apostrophe}` casse avec `unexpected EOF`

**Cause :** un bug de parsing bash bien connu — même entre guillemets doubles, une
apostrophe à l'intérieur du `message` d'un `${VAR:?message}` peut faire croire au parseur
qu'une chaîne entre quotes simples s'ouvre. Repéré dans `scripts/deploy.sh` lors de la
rédaction du message d'erreur en français ("...avant d'appeler...").

**Correctif :** remplacez `${VAR:?message}` par un `if [[ -z "${VAR:-}" ]]; then ... exit 1;
fi` explicite dès que le message contient une apostrophe.

## Bash : `set -o pipefail` + `... | head -n1` casse le script (SIGPIPE, code 141)

**Cause :** quand une commande produit plusieurs lignes et qu'on ne garde que la première
avec `head -n1`, `head` ferme le pipe après la 1ʳᵉ ligne ; la commande amont reçoit SIGPIPE
et sort en code 141. Avec `pipefail` + `set -e`, ce code non nul fait avorter le script.
Repéré dans `scripts/check-prerequisites.sh` sur `kubectl version --client` (2 lignes de
sortie).

**Correctif :** `out="$(cmd 2>&1 | head -n1)" || true` — on ne s'intéresse qu'au texte
capturé, pas au code de sortie du pipe.

## `.env.example` ne doit jamais être sourcé directement

**Cause :** les placeholders `<GITHUB_USERNAME>` contiennent des caractères `<` et `>` qui,
en shell, sont des opérateurs de redirection. Un `source .env.example` non édité casse
immédiatement avec une erreur de syntaxe.

**Correctif :** `scripts/lib.sh` ne source jamais `.env.example` — seulement `.env` (que
vous créez vous-même en copiant et éditant l'exemple). Sans `.env`, des valeurs par défaut
sûres (`GITHUB_USERNAME=local`, etc.) sont utilisées pour les opérations 100% locales.

## Conflit de port 8080 entre `make run`/`make build` et le cluster kind

`cluster/kind-config.yaml` mappe le NodePort de l'app sur `localhost:8080`. Si vous lancez
en même temps un conteneur local avec `make run` (qui utilise aussi le port 8080), l'un des
deux échouera à réserver le port. `scripts/build.sh` utilise volontairement un port éphémère
différent (`18080` par défaut, `HEALTHCHECK_PORT`) pour son test de santé interne, mais
`make run` et le Service Kubernetes du cluster utilisent bien tous deux 8080 — ne les
lancez pas simultanément, ou changez l'un des deux ports.

## `make lint` ne montre aucune sortie pour shellcheck/yamllint/actionlint

C'est normal : ces outils sont **silencieux quand tout est correct**. Une absence de
sortie après la ligne `flake8` = un lint qui passe, pas un lint qui n'a pas tourné (sauf
message explicite « non installé, étape ignorée »).
