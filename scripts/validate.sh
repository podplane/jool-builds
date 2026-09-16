#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

modules=''
jool_version=''
kernel_release=''
architecture=''
while (($#)); do
  case "$1" in
    --modules) modules="$2"; shift 2 ;;
    --jool-version) jool_version="$2"; shift 2 ;;
    --kernel-release) kernel_release="$2"; shift 2 ;;
    --architecture) architecture="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$modules" && -n "$jool_version" && -n "$kernel_release" && -n "$architecture" ]] || exit 2

case "$architecture" in
  amd64) expected_machine='Advanced Micro Devices X86-64' ;;
  arm64) expected_machine='AArch64' ;;
  *) echo "unsupported architecture: $architecture" >&2; exit 1 ;;
esac

for name in jool_common.ko jool.ko jool_siit.ko; do
  module="$modules/$name"
  [[ -s "$module" ]] || { echo "missing module: $name" >&2; exit 1; }

  vermagic="$(modinfo -F vermagic "$module")"
  [[ "$vermagic" == "$kernel_release "* ]] || {
    echo "$name has vermagic '$vermagic', expected kernel release '$kernel_release'" >&2
    exit 1
  }

  version="$(modinfo -F version "$module")"
  [[ "$version" == "$jool_version" || "$version" == "$jool_version."* ]] || {
    echo "$name has Jool version '$version', expected '$jool_version'" >&2
    exit 1
  }

  machine="$(readelf -h "$module" | awk -F: '/Machine:/{sub(/^[[:space:]]+/, "", $2); print $2}')"
  [[ "$machine" == "$expected_machine" ]] || {
    echo "$name targets '$machine', expected '$expected_machine'" >&2
    exit 1
  }
done
