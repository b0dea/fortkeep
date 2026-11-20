# fortkeep — developer targets. People who only check their Mac never need make.
# Every target carries a `## <Section>: <description>` comment; `##!` stars a frequent one in `make help`.

# --- Shell & safety -----------------------------------------------------------
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
# macOS's /usr/bin/make is GNU Make 3.81, which ignores .SHELLFLAGS but passes flags written in SHELL.
ifeq ($(MAKE_VERSION),3.81)
SHELL := /bin/bash -eu -o pipefail
endif
.DEFAULT_GOAL := help

# --- Colours (real ESC bytes, so echo, printf and awk all render them) --------
GREEN  := $(shell printf '\033[0;32m')
YELLOW := $(shell printf '\033[1;33m')
RED    := $(shell printf '\033[0;31m')
NC     := $(shell printf '\033[0m')

# --- Tools --------------------------------------------------------------------
# The versions pinned in .mise.toml when mise is installed; otherwise whatever is on PATH.
MISE := $(shell command -v mise >/dev/null 2>&1 && echo mise exec --)
STOCK_PATH := /usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
TESTS ?= tests
# How many test files run at once (ci/run-tests.sh). Several agent sessions share a Mac: keep it at 4 or below.
JOBS ?= 4
export JOBS
SH := $(sort $(wildcard $(shell git ls-files -co --exclude-standard '*.sh' bin/fortkeep)))

# --- Help macro (sectioned, ##! = ⭐) -----------------------------------------
define print_help_section
	@printf "$(YELLOW)%s$(NC)\n" "$(1)"
	@grep -h -E '^[a-zA-Z0-9_-]+:.*##[!]? .*$$' $(MAKEFILE_LIST) | \
	grep -E "$(2)" | \
	awk -F '##' \
	'{ \
	    cmd=$$1; \
	    gsub(/:.*/,"",cmd); \
	    desc=$$NF; \
	    gsub(/^[!]? [A-Za-z]+: /,"",desc); \
	    marker = ($$0 ~ /##!/) ? "⭐" : "  "; \
	    printf "  $(GREEN)%-14s$(NC)  %s  %s\n", cmd, marker, desc \
	}'
	@echo ""
endef

.PHONY: help install lock hooks dev clean build controls lint format test test-stock controls-check scan scan-private ci push-check check release

help: ## Meta: Show this help
	@printf "$(GREEN)%s$(NC)\n\n" "fortkeep developer targets"
	$(call print_help_section,Dev — set up and run:,Dev:)
	$(call print_help_section,Build — generated files:,Build:)
	$(call print_help_section,Quality — lint / test / scan:,Quality:)
	@printf "$(RED)⭐ = frequently used$(NC)\n"

# --- Dev ----------------------------------------------------------------------
install: ##! Dev: Install the pinned dev tools (needs mise: brew install mise) and the git hooks
	@command -v mise >/dev/null 2>&1 || { echo "$(RED)mise is not installed: brew install mise$(NC)"; exit 1; }
	mise install
	@$(MAKE) --no-print-directory hooks

# yamllint (pypi) stays out: mise can't lock a Python tool's dependencies while it pins the Python (uvx_args), so
# mise.lock records only its version, and `mise install --locked` refuses it.
# mise checks each locked tool's checksum (bats' is that of its source tarball).
lock: ## Dev: Refresh mise.lock after changing .mise.toml
	mise lock --platform linux-x64,macos-arm64 bats shellcheck uv gitleaks lefthook yq

hooks: ## Dev: Install the git hooks with lefthook (replaces the old .githooks folder)
	@# With a global core.hooksPath, lefthook would write into that shared folder: warn and skip, so make install
	@# still finishes. One shell, so the skip also skips the install below.
	@# Git ignores .git/hooks, where lefthook installs, while this repo's core.hooksPath is set.
	@if git config --global --get core.hooksPath >/dev/null 2>&1; then \
	  echo "$(YELLOW)WARNING: your global git config sets core.hooksPath, so lefthook would install into that shared folder. Skipping this repo's git hooks (make never changes your global config): run make ci before you push.$(NC)"; \
	else \
	  if git config --local --get core.hooksPath >/dev/null 2>&1; then \
	    echo "$(YELLOW)Unsetting this repo's core.hooksPath ($$(git config --local --get core.hooksPath)) so lefthook's hooks run$(NC)"; \
	    git config --local --unset core.hooksPath; \
	  fi; \
	  echo "$(MISE) lefthook install -f"; \
	  $(MISE) lefthook install -f; \
	fi

dev: ##! Dev: Check this Mac (read-only; results go to reports/)
	checks/run.sh

clean: ## Dev: Remove scratch files (.DS_Store); never touches reports/
	find . -name .DS_Store -type f -not -path './reports/*' -not -path './.git/*' -print -delete

# --- Build --------------------------------------------------------------------
build: ##! Build: Compile controls/*.yaml into controls/controls.json
	$(MISE) ci/build-controls.sh

controls: build ## Build: Same as build

# --- Quality (ci = everything; run it before merging) --------------------------
lint: ##! Quality: yamllint, shellcheck
	$(MISE) yamllint .
	$(MISE) shellcheck -x $(SH)

format: ## Quality: No auto-formatter; shellcheck (make lint) enforces the style
	@echo "No auto-formatter here: shellcheck (make lint) enforces the shell style."

controls-check: ## Quality: controls.json is valid and up to date with the YAML
	$(MISE) ci/check-controls.sh

test: ##! Quality: bats tests, JOBS files at a time (TESTS=tests/x.bats for one file)
	$(MISE) ci/run-tests.sh $(TESTS)

test-stock: ## Quality: The same tests with stock macOS tools first on PATH
	$(MISE) /bin/bash -c 'PATH="$(STOCK_PATH):$$PATH" exec ci/run-tests.sh $(TESTS)'

scan: ## Quality: gitleaks over the whole history, then the marker scan
	$(MISE) gitleaks git --redact --no-banner .
	ci/marker-scan.sh

# Maintainers only: it needs a list that lives outside the repo, so contributors' gates leave it out.
scan-private: ## Quality: Scan for terms you never want committed, such as employer or client names (list: ~/.config/fortkeep/denylist)
	ci/denylist-scan.sh

ci: ##! Quality: Lint, controls, the tests (also with stock tools) and the scans; run it before merging
	@$(MAKE) --no-print-directory lint
	@$(MAKE) --no-print-directory controls-check
	@$(MAKE) --no-print-directory test
	@$(MAKE) --no-print-directory test-stock
	@$(MAKE) --no-print-directory scan

push-check: ## Quality: ci without the tests (pre-push runs this, so a push stays quick)
	@$(MAKE) --no-print-directory lint
	@$(MAKE) --no-print-directory controls-check
	@$(MAKE) --no-print-directory scan

check: ci ## Quality: Same as ci (the old name)

release: ci scan-private ## Quality: Sign a release tag on main after ci and scan-private pass (VERSION=v1.2.3)
	ci/release.sh $(VERSION)
