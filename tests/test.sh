#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/packages" "$work/bin"
for arch in amd64 arm64; do
  cat >"$work/packages/trixie-${arch}.Packages" <<EOF
Package: linux-headers-6.12.48+deb13-cloud-${arch}
Version: 1

Package: linux-headers-6.12.57+deb13-cloud-${arch}
Version: 1

Package: linux-headers-cloud-${arch}
Version: 1

Package: unrelated
Version: 1
EOF
done

DEBIAN_PACKAGES_DIR="$work/packages" "$repo_root/scripts/discover-kernels.sh" trixie:13 >"$work/kernels.json"
jq -e '
  length == 4 and
  (.[0].kernel_abi == "6.12.48+deb13") and
  (.[0].kernel_release == "6.12.48+deb13-cloud-amd64") and
  (.[3].architecture == "arm64")
' "$work/kernels.json" >/dev/null

cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${GH_FIXTURE:-}" ]]; then
  cat "$GH_FIXTURE"
  exit 0
fi
echo 'gh: Not Found (HTTP 404)' >&2
exit 1
EOF
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH" "$repo_root/scripts/check-releases.sh" \
  --repository example/jool-builds \
  --jool-version 4.1.15 \
  --kernels "$work/kernels.json" >"$work/matrix.json"
jq -e 'length == 4 and all(.jool_version == "4.1.15")' "$work/matrix.json" >/dev/null

jq '[.[] | select(.kernel_abi == "6.12.48+deb13")]' "$work/kernels.json" >"$work/one-kernel.json"
jq -n '{draft: false, assets: [
  "jool-4.1.15-6.12.48+deb13-amd64.tar.gz",
  "jool-4.1.15-6.12.48+deb13-amd64.spdx.json",
  "jool-4.1.15-6.12.48+deb13-amd64.sigstore.json",
  "jool-4.1.15-6.12.48+deb13-arm64.tar.gz",
  "jool-4.1.15-6.12.48+deb13-arm64.spdx.json",
  "jool-4.1.15-6.12.48+deb13-arm64.sigstore.json",
  "jool-4.1.15-6.12.48+deb13-source.tar.gz",
  "jool-4.1.15-6.12.48+deb13-source.sigstore.json",
  "SHA256SUMS",
  "SHA256SUMS.sigstore.json"
] | map({name: .})}' >"$work/complete-release.json"
GH_FIXTURE="$work/complete-release.json" PATH="$work/bin:$PATH" "$repo_root/scripts/check-releases.sh" \
  --repository example/jool-builds \
  --jool-version 4.1.15 \
  --kernels "$work/one-kernel.json" >"$work/complete-matrix.json"
jq -e 'length == 0' "$work/complete-matrix.json" >/dev/null

jq 'del(.assets[-1])' "$work/complete-release.json" >"$work/incomplete-release.json"
if GH_FIXTURE="$work/incomplete-release.json" PATH="$work/bin:$PATH" "$repo_root/scripts/check-releases.sh" \
  --repository example/jool-builds \
  --jool-version 4.1.15 \
  --kernels "$work/one-kernel.json" >/dev/null 2>"$work/incomplete-error"; then
  echo "an incomplete published release unexpectedly passed" >&2
  exit 1
fi
grep -q 'incomplete and immutable' "$work/incomplete-error"

mkdir -p "$work/modules"
printf module >"$work/modules/jool_common.ko"
printf nat64 >"$work/modules/jool.ko"
printf siit >"$work/modules/jool_siit.ko"
printf 'GPLv2 license\n' >"$work/modules/COPYING"
printf 'Jool copyright notice\n' >"$work/modules/NOTICE"
printf 'Corresponding source notice\n' >"$work/modules/SOURCE"
cat >"$work/modules/metadata.json" <<'EOF'
{"jool_version":"4.1.15","kernel_abi":"6.12.48+deb13","kernel_release":"6.12.48+deb13-cloud-amd64","architecture":"amd64","headers_package":"linux-headers-6.12.48+deb13-cloud-amd64","headers_package_version":"6.12.48-1","source":{"url":"https://example.invalid/jool.tar.gz","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"compiler":"gcc test","modules":["jool_common.ko","jool.ko","jool_siit.ko"],"notices":["COPYING","NOTICE","SOURCE"]}
EOF
SOURCE_DATE_EPOCH=0 "$repo_root/scripts/package.sh" --input "$work/modules" --output "$work/artifact.tar.gz"
tar -tzf "$work/artifact.tar.gz" | sort >"$work/archive-files"
diff -u <(printf '%s\n' COPYING NOTICE SOURCE jool.ko jool_common.ko jool_siit.ko metadata.json | sort) "$work/archive-files"

"$repo_root/scripts/sbom.sh" \
  --modules "$work/modules" \
  --metadata "$work/modules/metadata.json" \
  --archive "$work/artifact.tar.gz" \
  --output "$work/artifact.spdx.json"
jq -e '
  .spdxVersion == "SPDX-2.3" and
  (.files | length == 3) and
  (.packages[0].licenseDeclared == "GPL-2.0-only") and
  (.packages[0].copyrightText == "Copyright (C) 2011 NIC Mexico <jool@nic.mx>") and
  (.packages | length == 4) and
  (.relationships | length == 7)
' "$work/artifact.spdx.json" >/dev/null

publish_assets="$work/publish-assets"
mkdir -p "$publish_assets"
publish_stem="jool-4.1.15-6.12.48+deb13"
for architecture in amd64 arm64; do
  printf archive >"$publish_assets/${publish_stem}-${architecture}.tar.gz"
  printf sbom >"$publish_assets/${publish_stem}-${architecture}.spdx.json"
  printf bundle >"$publish_assets/${publish_stem}-${architecture}.sigstore.json"
done
printf source >"$publish_assets/${publish_stem}-source.tar.gz"
printf bundle >"$publish_assets/${publish_stem}-source.sigstore.json"
jq --arg version 4.1.15 'map(. + {jool_version: $version})' "$work/one-kernel.json" >"$work/publish-matrix.json"

cat >"$work/bin/cosign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bundle=''
while (($#)); do
  case "$1" in
    --bundle) bundle="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$bundle" ]]
printf '{}\n' >"$bundle"
EOF
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  'release view') exit 1 ;;
  'release create')
    shift 2
    (($#)) || exit 1
    shift
    while (($#)); do
      case "$1" in
        --repo|--title|--notes) shift 2; continue ;;
        --draft) shift; continue ;;
      esac
      argument="$1"
      [[ -f "$argument" ]] || { echo "missing upload argument: $argument" >&2; exit 1; }
      if [[ "${argument##*/}" == SHA256SUMS ]]; then
        cp "$argument" "$GH_CHECKSUM_CAPTURE"
      fi
      shift
    done
    echo create >>"$GH_COMMAND_LOG"
    ;;
  'release edit') echo edit >>"$GH_COMMAND_LOG" ;;
  *) echo "unexpected gh invocation: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/cosign" "$work/bin/gh"
(
  cd "$repo_root"
  GH_CHECKSUM_CAPTURE="$work/published-SHA256SUMS" \
    GH_COMMAND_LOG="$work/gh-commands" \
    PATH="$work/bin:$PATH" \
    scripts/publish.sh \
      --repository example/jool-builds \
      --matrix "$(cat "$work/publish-matrix.json")" \
      --assets "$publish_assets"
)
diff -u <(printf '%s\n' create edit) "$work/gh-commands"
[[ "$(wc -l <"$work/published-SHA256SUMS" | tr -d ' ')" == 5 ]]
grep -q "${publish_stem}-amd64.tar.gz" "$work/published-SHA256SUMS"
grep -q "${publish_stem}-arm64.tar.gz" "$work/published-SHA256SUMS"
grep -q "${publish_stem}-source.tar.gz" "$work/published-SHA256SUMS"

mkdir -p "$work/path.with.dots/6.12.48+deb13"
printf sums >"$work/path.with.dots/6.12.48+deb13/SHA256SUMS"
PATH="$work/bin:$PATH" "$repo_root/scripts/sign.sh" "$work/path.with.dots/6.12.48+deb13/SHA256SUMS"
[[ -f "$work/path.with.dots/6.12.48+deb13/SHA256SUMS.sigstore.json" ]]

echo "All tests passed."
