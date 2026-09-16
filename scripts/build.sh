#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

usage() {
  echo "usage: $0 --jool-version VERSION --kernel-abi ABI --kernel-release RELEASE --architecture ARCH --headers-package PACKAGE --output DIR" >&2
  exit 2
}

jool_version=''
kernel_abi=''
kernel_release=''
architecture=''
headers_package=''
output=''
while (($#)); do
  case "$1" in
    --jool-version) jool_version="$2"; shift 2 ;;
    --kernel-abi) kernel_abi="$2"; shift 2 ;;
    --kernel-release) kernel_release="$2"; shift 2 ;;
    --architecture) architecture="$2"; shift 2 ;;
    --headers-package) headers_package="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$jool_version" && -n "$kernel_abi" && -n "$kernel_release" && -n "$architecture" && -n "$headers_package" && -n "$output" ]] || usage
[[ "$architecture" == amd64 || "$architecture" == arm64 ]] || { echo "unsupported architecture: $architecture" >&2; exit 1; }
[[ "$(dpkg --print-architecture)" == "$architecture" ]] || { echo "the build host architecture does not match $architecture" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --yes --no-install-recommends \
  bc bison build-essential ca-certificates curl flex gettext-base git jq kmod libelf-dev libgcc-s1 libssl-dev libstdc++6 tar xz-utils \
  "$headers_package"

for command in cc curl cut date dpkg-query envsubst jq make mktemp modinfo nproc readelf sed sha256sum sort tar xz; do
  command -v "$command" >/dev/null || {
    echo "required command not found after dependency installation: $command" >&2
    exit 1
  }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
source_url="https://github.com/NICMx/Jool/releases/download/v${jool_version}/jool-${jool_version}.tar.gz"
source_archive="$work/jool.tar.gz"
curl --fail --location --retry 3 --output "$source_archive" "$source_url"
source_sha256="$(sha256sum "$source_archive" | cut -d' ' -f1)"
tar -xzf "$source_archive" -C "$work"
source_dir="$work/jool-${jool_version}"
headers_dir="/usr/src/linux-headers-${kernel_release}"
[[ -d "$source_dir" ]] || { echo "unexpected Jool archive layout" >&2; exit 1; }
[[ -d "$headers_dir" ]] || { echo "headers directory not found: $headers_dir" >&2; exit 1; }

make -C "$source_dir/src/mod/common" KERNEL_DIR="$headers_dir" -j"$(nproc)"
make -C "$source_dir/src/mod/siit" KERNEL_DIR="$headers_dir" -j"$(nproc)"
make -C "$source_dir/src/mod/nat64" KERNEL_DIR="$headers_dir" -j"$(nproc)"

modules="$work/modules"
mkdir -p "$modules" "$output"
cp \
  "$source_dir/src/mod/common/jool_common.ko" \
  "$source_dir/src/mod/nat64/jool.ko" \
  "$source_dir/src/mod/siit/jool_siit.ko" \
  "$modules/"
cp LICENSE "$modules/COPYING"
cp NOTICE "$modules/NOTICE"

scripts/validate.sh \
  --modules "$modules" \
  --jool-version "$jool_version" \
  --kernel-release "$kernel_release" \
  --architecture "$architecture"

compiler="$("${CC:-cc}" --version | head -1)"
headers_package_version="$(dpkg-query --show --showformat='${Version}' "$headers_package")"
source_asset="jool-${jool_version}-${kernel_abi}-source.tar.gz"
cat >"$modules/SOURCE" <<EOF
Corresponding source
====================

The complete, unmodified Jool ${jool_version} source used to build these
modules is distributed alongside this archive as:

    ${source_asset}

SHA-256: ${source_sha256}
Upstream: ${source_url}

The scripts controlling compilation, validation, packaging, and publication
are distributed in the source archive for the GitHub Release containing this
artifact, tagged jool-${jool_version}-kernel-${kernel_abi}.
EOF
jq -n \
  --arg jool_version "$jool_version" \
  --arg kernel_abi "$kernel_abi" \
  --arg kernel_release "$kernel_release" \
  --arg architecture "$architecture" \
  --arg headers_package "$headers_package" \
  --arg headers_package_version "$headers_package_version" \
  --arg source_url "$source_url" \
  --arg source_sha256 "$source_sha256" \
  --arg compiler "$compiler" \
  '{
    jool_version: $jool_version,
    kernel_abi: $kernel_abi,
    kernel_release: $kernel_release,
    architecture: $architecture,
    headers_package: $headers_package,
    headers_package_version: $headers_package_version,
    source: {url: $source_url, sha256: $source_sha256},
    compiler: $compiler,
    modules: ["jool_common.ko", "jool.ko", "jool_siit.ko"],
    notices: ["COPYING", "NOTICE", "SOURCE"]
  }' >"$modules/metadata.json"

stem="jool-${jool_version}-${kernel_abi}-${architecture}"
scripts/package.sh --input "$modules" --output "$output/${stem}.tar.gz"
scripts/sbom.sh \
  --modules "$modules" \
  --metadata "$modules/metadata.json" \
  --archive "$output/${stem}.tar.gz" \
  --output "$output/${stem}.spdx.json"

if [[ "$architecture" == amd64 ]]; then
  cp "$source_archive" "$output/$source_asset"
fi
