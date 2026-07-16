SHELL := /usr/bin/env bash

# Étape du projet : certaines cibles arrivent progressivement (voir README / checklist).
# Une cible listée dans `make help` mais pas encore câblée à un script affiche PENDING
# et échoue explicitement — elle ne prétend jamais avoir réussi.
define PENDING
	@echo "⏳ 'make $@' arrive dans une prochaine étape du projet (pas encore implémenté)." >&2
	@exit 1
endef

.PHONY: help check-prereqs install test lint build run sbom scan push sign attest verify \
        cluster-create kyverno-install deploy demo clean

help: ## Affiche cette aide
	@echo "Cibles disponibles :"
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

check-prereqs: ## Vérifie que les outils requis sont installés
	./scripts/check-prerequisites.sh

install: ## Installe les dépendances Python de l'application (venv/pip de votre choix)
	pip install -r app/requirements.txt

test: ## Lance les tests unitaires de l'application (pytest)
	cd app && python3 -m pytest -v

lint: ## Lint Python (flake8) ; ajoute shellcheck/yamllint/actionlint si installés
	python3 -m flake8 --max-line-length=100 app/app.py app/test_app.py
	@command -v shellcheck >/dev/null 2>&1 && shellcheck scripts/*.sh || echo "ℹ️  shellcheck non installé, étape ignorée"
	@command -v yamllint >/dev/null 2>&1 && yamllint policies/ k8s/ cluster/ .github/ || echo "ℹ️  yamllint non installé, étape ignorée"
	@command -v actionlint >/dev/null 2>&1 && actionlint .github/workflows/*.yml || echo "ℹ️  actionlint non installé, étape ignorée"

build: ## Build l'image Docker locale et vérifie /health
	./scripts/build.sh

run: ## Lance l'image locale sur http://localhost:8080
	./scripts/run.sh

sbom: build ## Génère le SBOM (Syft, SPDX JSON) dans artifacts/
	./scripts/generate-sbom.sh

scan: ## Scanne le SBOM avec Grype (échoue sur CRITICAL corrigeable)
	./scripts/scan.sh

push: ## Authentification GHCR + push de l'image (affiche le digest)
	./scripts/push.sh

sign: ## Signature cosign keyless (export DIGEST=sha256:... ; mode clé : ./scripts/sign.sh key)
	./scripts/sign.sh keyless

attest: ## Attestations SBOM + provenance, mode keyless (export DIGEST=sha256:...)
	./scripts/attest.sh keyless

verify: ## Vérification cosign keyless (export DIGEST=sha256:... ; mode clé : ./scripts/verify.sh key)
	./scripts/verify.sh keyless

cluster-create: ## Crée le cluster kind local (idempotent)
	./scripts/create-cluster.sh

kyverno-install: ## Installe Kyverno (version épinglée) + namespace applicatif
	./scripts/install-kyverno.sh

deploy: ## Déploie l'app PAR DIGEST (nécessite : export DIGEST=sha256:...)
	./scripts/deploy.sh

demo: ## Scénarios d'attaque/défense réels (kubectl + Kyverno)
	./scripts/run-demo.sh

clean: ## Supprime les artefacts locaux générés (artifacts/*, sauf .gitkeep)
	find artifacts -type f ! -name '.gitkeep' -delete
	@echo "✅ artifacts/ nettoyé (le cluster kind n'est PAS touché — utilisez le futur 'kind delete cluster' manuellement)"
