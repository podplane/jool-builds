#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

repository=''
jool_version=''
kernels=''
while (($#)); do
  case "$1" in
    --repository) repository="$2"; shift 2 ;;
    --jool-version) jool_version="$2"; shift 2 ;;
    --kernels) kernels="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repository" && -n "$jool_version" && -n "$kernels" ]] || exit 2
jq -e 'type == "array"' "$kernels" >/dev/null

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
missing="$work/missing.ndjson"
: >"$missing"

while IFS= read -r abi; do
  tag="jool-${jool_version}-kernel-${abi}"
  current="$work/current.json"
  error="$work/gh-error"
  exists=true
  if ! gh api "repos/${repository}/releases/tags/${tag}" >"$current" 2>"$error"; then
    if grep -Eq 'HTTP 404|Not Found' "$error"; then
      exists=false
    else
      cat "$error" >&2
      exit 1
    fi
  fi

  if [[ "$exists" == false ]] || jq -e '.draft == true' "$current" >/dev/null 2>&1; then
    jq -c --arg abi "$abi" --arg version "$jool_version" \
      '.[] | select(.kernel_abi == $abi) | . + {jool_version: $version}' \
      "$kernels" >>"$missing"
    continue
  fi

  actual="$work/actual"
  expected="$work/expected"
  jq -r '.assets[]?.name' "$current" | sort -u >"$actual"
  {
    echo SHA256SUMS
    echo SHA256SUMS.sigstore.json
    echo "jool-${jool_version}-${abi}-source.tar.gz"
    echo "jool-${jool_version}-${abi}-source.sigstore.json"
    while IFS= read -r architecture; do
      stem="jool-${jool_version}-${abi}-${architecture}"
      echo "${stem}.tar.gz"
      echo "${stem}.spdx.json"
      echo "${stem}.sigstore.json"
    done < <(jq -r --arg abi "$abi" '[.[] | select(.kernel_abi == $abi) | .architecture] | unique[]' "$kernels")
  } | sort -u >"$expected"

  absent="$(comm -23 "$expected" "$actual")"
  if [[ -n "$absent" ]]; then
    absent="$(printf '%s\n' "$absent" | paste -sd ', ' -)"
    echo "published release $tag is incomplete and immutable; missing: $absent" >&2
    exit 1
  fi
done < <(jq -r 'map(.kernel_abi) | unique[]' "$kernels")

jq -s -c . "$missing"
