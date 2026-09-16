.DEFAULT_GOAL := help

MISE ?= mise

.PHONY: help setup lint precommit test check clean

help: ## Show available targets
	@echo "Usage: make <target>"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Install pinned tools and Git hooks
	@command -v $(MISE) >/dev/null 2>&1 || { echo "mise is required but not installed" >&2; exit 1; }
	@$(MISE) install actionlint shellcheck
	@for tool in bash cosign curl gh jq make tar xz; do \
		command -v $$tool >/dev/null 2>&1 || { echo "$$tool is required but not installed" >&2; exit 1; }; \
	done
	@command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || { echo "sha256sum or shasum is required but not installed" >&2; exit 1; }
	@test -d .git/hooks || { echo ".git/hooks does not exist" >&2; exit 1; }
	@cp scripts/git-hooks/pre-commit .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@cp scripts/git-hooks/commit-msg .git/hooks/commit-msg
	@chmod +x .git/hooks/commit-msg
	@echo "Pinned tools and Git hooks installed."

lint: ## Run ShellCheck and actionlint
	@$(MISE) exec -- shellcheck scripts/*.sh tests/*.sh scripts/git-hooks/*
	@$(MISE) exec -- actionlint

precommit: lint ## Run fast read-only checks

test: ## Run fixture-backed tests
	tests/test.sh

check: lint test ## Run all validation

clean: ## Remove generated local artifacts
	rm -rf output output-*
