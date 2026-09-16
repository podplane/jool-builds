#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

api_url="${JOOL_RELEASE_API:-https://api.github.com/repos/NICMx/Jool/releases/latest}"
release="$(curl --fail --silent --show-error --location --retry 3 "$api_url")"
version="$(jq -er '.tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")) | ltrimstr("v")' <<<"$release")"

asset="jool-${version}.tar.gz"
jq -e --arg asset "$asset" '.assets | any(.name == $asset)' <<<"$release" >/dev/null
printf '%s\n' "$version"
