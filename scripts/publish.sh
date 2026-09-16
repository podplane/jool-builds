#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

repository=''
matrix=''
assets=''
while (($#)); do
  case "$1" in
    --repository) repository="$2"; shift 2 ;;
    --matrix) matrix="$2"; shift 2 ;;
    --assets) assets="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$repository" && -n "$matrix" && -n "$assets" ]] || exit 2

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

sha256_files() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

while IFS= read -r abi; do
  entries="$(jq -c --arg abi "$abi" '[.[] | select(.kernel_abi == $abi)]' <<<"$matrix")"
  version="$(jq -er 'map(.jool_version) | unique | if length == 1 then .[0] else error("mixed Jool versions") end' <<<"$entries")"
  debian_release="$(jq -er 'map(.debian_release) | unique | if length == 1 then .[0] else error("mixed Debian releases") end' <<<"$entries")"
  architectures="$(jq -cr 'map(.architecture) | unique | sort | join(" ")' <<<"$entries")"
  [[ "$architectures" == "amd64 arm64" ]] || {
    echo "kernel $abi does not include exactly amd64 and arm64" >&2
    exit 1
  }

  tag="jool-${version}-kernel-${abi}"
  title="Jool ${version} — Debian ${debian_release} / Linux ${abi}"
  stem="jool-${version}-${abi}"
  release_dir="$work/$abi"
  mkdir -p "$release_dir"

  files=()
  checksummed=()
  for architecture in amd64 arm64; do
    for suffix in tar.gz spdx.json; do
      file="$assets/${stem}-${architecture}.${suffix}"
      [[ -f "$file" ]] || { echo "missing release asset: $file" >&2; exit 1; }
      files+=("$file")
      checksummed+=("$(basename "$file")")
    done
    bundle="$assets/${stem}-${architecture}.sigstore.json"
    [[ -f "$bundle" ]] || { echo "missing release asset: $bundle" >&2; exit 1; }
    files+=("$bundle")
  done

  source_archive="$assets/${stem}-source.tar.gz"
  source_bundle="$assets/${stem}-source.sigstore.json"
  [[ -f "$source_archive" ]] || { echo "missing release asset: $source_archive" >&2; exit 1; }
  [[ -f "$source_bundle" ]] || { echo "missing release asset: $source_bundle" >&2; exit 1; }
  files+=("$source_archive" "$source_bundle")
  checksummed+=("$(basename "$source_archive")")

  (
    cd "$assets"
    sha256_files "${checksummed[@]}" >"$release_dir/SHA256SUMS"
  )
  scripts/sign.sh "$release_dir/SHA256SUMS"
  checksum_bundle="$release_dir/SHA256SUMS.sigstore.json"
  [[ -f "$checksum_bundle" ]] || { echo "missing generated signature bundle: $checksum_bundle" >&2; exit 1; }
  files+=("$release_dir/SHA256SUMS" "$checksum_bundle")

  if current="$(gh release view "$tag" --repo "$repository" --json isDraft 2>/dev/null)"; then
    if [[ "$(jq -r .isDraft <<<"$current")" != true ]]; then
      echo "refusing to modify published release $tag" >&2
      exit 1
    fi
    gh release delete "$tag" --repo "$repository" --yes
  fi

  notes="Prebuilt Jool ${version} kernel modules for Debian ${debian_release} cloud kernels with ABI ${abi}."
  gh release create "$tag" "${files[@]}" \
    --repo "$repository" \
    --draft \
    --title "$title" \
    --notes "$notes"
  gh release edit "$tag" --repo "$repository" --draft=false
done < <(jq -r 'map(.kernel_abi) | unique[]' <<<"$matrix")
