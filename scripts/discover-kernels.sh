#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

(($# > 0)) || {
  echo "usage: $0 SUITE:RELEASE [SUITE:RELEASE ...]" >&2
  exit 2
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
matrix="$work/matrix.ndjson"
: >"$matrix"

extract_packages() {
  local architecture="$1"
  local destination="$2"
  local suffix="-cloud-${architecture}"
  awk -v suffix="$suffix" '
    $1 == "Package:" {
      package = $2
      prefix = "linux-headers-"
      if (index(package, prefix) == 1 && length(package) > length(prefix) + length(suffix) && substr(package, length(package) - length(suffix) + 1) == suffix) {
        abi = substr(package, length(prefix) + 1, length(package) - length(prefix) - length(suffix))
        print abi "\t" package
      }
    }
  ' >>"$destination"
}

for value in "$@"; do
  case "$value" in
    *:*) suite="${value%%:*}"; release="${value#*:}" ;;
    *) echo "invalid Debian release '$value'; expected SUITE:RELEASE" >&2; exit 2 ;;
  esac
  [[ -n "$suite" && -n "$release" ]] || {
    echo "invalid Debian release '$value'; expected SUITE:RELEASE" >&2
    exit 2
  }

  for architecture in amd64 arm64; do
    packages="$work/${suite}-${architecture}.packages"
    : >"$packages"
    if [[ -n "${DEBIAN_PACKAGES_DIR:-}" ]]; then
      fixture="$DEBIAN_PACKAGES_DIR/${suite}-${architecture}.Packages"
      [[ -f "$fixture" ]] && extract_packages "$architecture" "$packages" <"$fixture"
    else
      mirror="${DEBIAN_MIRROR:-https://deb.debian.org/debian}"
      security="${DEBIAN_SECURITY_MIRROR:-https://security.debian.org/debian-security}"
      urls=(
        "${mirror%/}/dists/${suite}/main/binary-${architecture}/Packages.xz"
        "${mirror%/}/dists/${suite}-updates/main/binary-${architecture}/Packages.xz"
        "${security%/}/dists/${suite}-security/main/binary-${architecture}/Packages.xz"
      )
      for url in "${urls[@]}"; do
        index="$work/index.xz"
        curl --fail --silent --show-error --location --retry 3 --output "$index" "$url"
        xz --decompress --stdout "$index" | extract_packages "$architecture" "$packages"
      done
    fi
    sort -u "$packages" -o "$packages"
    cut -f1 "$packages" >"$work/${suite}-${architecture}.abis"
  done

  comm -12 "$work/${suite}-amd64.abis" "$work/${suite}-arm64.abis" >"$work/${suite}.common"
  [[ -s "$work/${suite}.common" ]] || {
    echo "no cloud kernel ABI is available for every architecture in $suite" >&2
    exit 1
  }

  while IFS= read -r abi; do
    for architecture in amd64 arm64; do
      package="$(awk -F '\t' -v abi="$abi" '$1 == abi { print $2; exit }' "$work/${suite}-${architecture}.packages")"
      jq -cn \
        --arg suite "$suite" \
        --arg release "$release" \
        --arg abi "$abi" \
        --arg architecture "$architecture" \
        --arg package "$package" \
        '{
          debian_suite: $suite,
          debian_release: $release,
          kernel_abi: $abi,
          architecture: $architecture,
          kernel_release: ($abi + "-cloud-" + $architecture),
          headers_package: $package
        }' >>"$matrix"
    done
  done <"$work/${suite}.common"
done

jq -s . "$matrix"
