#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

input=''
output=''
while (($#)); do
  case "$1" in
    --input) input="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$input" && -n "$output" ]] || exit 2

files=(COPYING NOTICE SOURCE jool.ko jool_common.ko jool_siit.ko metadata.json)
for file in "${files[@]}"; do
  [[ -f "$input/$file" ]] || {
    echo "missing package input: $file" >&2
    exit 1
  }
done

COPYFILE_DISABLE=1 tar -czf "$output" -C "$input" "${files[@]}"
