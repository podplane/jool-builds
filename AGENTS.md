# Jool Builds — Agent Guide

## Purpose

This repository discovers Debian cloud kernel ABIs and publishes prebuilt,
signed Jool kernel modules for `amd64` and `arm64`.

## Layout

- `.github/workflows/check.yaml`: scheduled discovery and build dispatch.
- `.github/workflows/build.yaml`: module build, validation, signing, and release publishing.
- `.github/workflows/ci.yaml`: pull-request and main-branch validation.
- `scripts/*.sh`: Bash-only repository automation.
- `scripts/git-hooks`: local pre-commit and DCO hooks installed by `make setup`.
- `tests/test.sh`: fixture-backed script tests.

## Commands

- `make setup`: install pinned mise tools and local Git hooks.
- `make lint`: run ShellCheck and actionlint.
- `make precommit`: run fast, read-only checks used by the pre-commit hook.
- `make test`: run fixture-backed tests.
- `make check`: run lint and tests.

## Constraints

- Repository automation must be written in Bash. Go may be introduced when a
  compiled program is justified. Do not add other programming languages without
  explicit approval.
- This repository uses GPLv2 rather than Podplane's normal Apache-2.0
  baseline because it distributes GPLv2 Jool kernel modules and corresponding
  source.
- All Bash files must use a `.sh` extension, except Git hooks whose names are
  fixed by Git.
- Do not mutate published releases. Incomplete work must remain a draft.
- Do not use Git operations unless the user explicitly requests them.
- Generated build outputs belong under `output/` and must not be committed.
