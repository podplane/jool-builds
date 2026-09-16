#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

(($# > 0)) || { echo "usage: $0 FILE..." >&2; exit 2; }
for file in "$@"; do
  case "$file" in
    *.tar.gz) bundle="${file%.tar.gz}.sigstore.json" ;;
    *) bundle="${file}.sigstore.json" ;;
  esac
  cosign sign-blob --yes --bundle "$bundle" "$file"
done
