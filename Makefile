# Self-Hosted AI Stack - convenience targets.
#
# Run `make help` for the list. Uses `docker compose` (falls back to
# docker-compose if needed via the scripts).

SHELL := /usr/bin/env bash
COMPOSE := docker compose

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: ## Start the stack and preload models
	./scripts/up.sh

.PHONY: down
down: ## Stop and remove the stack containers
	$(COMPOSE) down

.PHONY: restart
restart: down up ## Restart the stack

.PHONY: logs
logs: ## Follow logs from all services
	$(COMPOSE) logs -f --tail=100

.PHONY: ps
ps: ## Show service status
	$(COMPOSE) ps

.PHONY: pull-models
pull-models: ## Pull the models listed in OLLAMA_MODELS
	./scripts/preload-models.sh

.PHONY: backup
backup: ## Back up Open WebUI data to ./backups
	./scripts/backup.sh

.PHONY: backup-all
backup-all: ## Back up Open WebUI data and Ollama models
	./scripts/backup.sh --models

.PHONY: restore
restore: ## Restore a backup: make restore FILE=backups/openwebui-....tar.gz
	@test -n "$(FILE)" || { echo "Usage: make restore FILE=backups/<archive>.tar.gz"; exit 1; }
	./scripts/restore.sh "$(FILE)"

.PHONY: validate
validate: ## Validate the Compose config (renders + checks)
	$(COMPOSE) config -q && echo "docker compose config: OK"

.PHONY: lint
lint: ## Run yamllint + shellcheck
	@command -v yamllint >/dev/null 2>&1 && yamllint . || echo "yamllint not installed - skipping"
	@command -v shellcheck >/dev/null 2>&1 && shellcheck scripts/*.sh tests/*.sh || echo "shellcheck not installed - skipping"

.PHONY: test
test: ## Run the compose smoke tests (no containers started)
	./tests/smoke-compose.sh

.PHONY: clean
clean: ## Remove the stack AND its named volumes (DESTROYS DATA)
	$(COMPOSE) down -v
