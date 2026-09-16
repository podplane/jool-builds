#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

modules=''
metadata_file=''
archive=''
output=''
while (($#)); do
  case "$1" in
    --modules) modules="$2"; shift 2 ;;
    --metadata) metadata_file="$2"; shift 2 ;;
    --archive) archive="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$modules" && -n "$metadata_file" && -n "$archive" && -n "$output" ]] || exit 2

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

metadata="$(cat "$metadata_file")"
jool_version="$(jq -er .jool_version <<<"$metadata")"
kernel_abi="$(jq -er .kernel_abi <<<"$metadata")"
architecture="$(jq -er .architecture <<<"$metadata")"
namespace="jool-${jool_version}-${kernel_abi}-${architecture}"
package_id="SPDXRef-$(printf '%s' "$namespace" | sed 's/[^A-Za-z0-9.-]/-/g')"
archive_hash="$(sha256 "$archive")"
common_hash="$(sha256 "$modules/jool_common.ko")"
nat64_hash="$(sha256 "$modules/jool.ko")"
siit_hash="$(sha256 "$modules/jool_siit.ko")"
epoch="${SOURCE_DATE_EPOCH:-0}"
if created="$(date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)"; then
  :
else
  created="$(date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ')"
fi

jq -n \
  --argjson metadata "$metadata" \
  --arg namespace "$namespace" \
  --arg package_id "$package_id" \
  --arg archive_hash "$archive_hash" \
  --arg common_hash "$common_hash" \
  --arg nat64_hash "$nat64_hash" \
  --arg siit_hash "$siit_hash" \
  --arg created "$created" \
  --arg copyright "Copyright (C) 2011 NIC Mexico <jool@nic.mx>" \
  '{
    spdxVersion: "SPDX-2.3",
    dataLicense: "CC0-1.0",
    SPDXID: "SPDXRef-DOCUMENT",
    name: $namespace,
    documentNamespace: ("https://github.com/podplane/jool-builds/sbom/" + $namespace + "/" + $archive_hash),
    creationInfo: {
      created: $created,
      creators: ["Tool: jool-builds/scripts/sbom.sh"],
      comment: ("Built with " + $metadata.compiler + " against " + $metadata.headers_package)
    },
    packages: [
      {
        SPDXID: $package_id,
        name: "Jool kernel modules",
        versionInfo: $metadata.jool_version,
        downloadLocation: "NOASSERTION",
        filesAnalyzed: true,
        licenseConcluded: "GPL-2.0-only",
        licenseDeclared: "GPL-2.0-only",
        copyrightText: $copyright,
        checksums: [{algorithm: "SHA256", checksumValue: $archive_hash}],
        externalRefs: [{
          referenceCategory: "PACKAGE-MANAGER",
          referenceType: "purl",
          referenceLocator: ("pkg:github/NICMx/Jool@v" + $metadata.jool_version)
        }],
        comment: ("Target: " + $metadata.kernel_release + " (" + $metadata.architecture + "); headers: " + $metadata.headers_package)
      },
      {
        SPDXID: "SPDXRef-Jool-source",
        name: "Jool source",
        versionInfo: $metadata.jool_version,
        downloadLocation: $metadata.source.url,
        filesAnalyzed: false,
        licenseConcluded: "GPL-2.0-only",
        licenseDeclared: "GPL-2.0-only",
        copyrightText: $copyright,
        checksums: [{algorithm: "SHA256", checksumValue: $metadata.source.sha256}],
        externalRefs: [{
          referenceCategory: "PACKAGE-MANAGER",
          referenceType: "purl",
          referenceLocator: ("pkg:github/NICMx/Jool@v" + $metadata.jool_version)
        }]
      },
      {
        SPDXID: "SPDXRef-Kernel-headers",
        name: $metadata.headers_package,
        versionInfo: $metadata.headers_package_version,
        downloadLocation: "NOASSERTION",
        filesAnalyzed: false,
        licenseConcluded: "NOASSERTION",
        licenseDeclared: "NOASSERTION",
        copyrightText: "NOASSERTION",
        externalRefs: [{
          referenceCategory: "PACKAGE-MANAGER",
          referenceType: "purl",
          referenceLocator: ("pkg:deb/debian/" + $metadata.headers_package + "@" + $metadata.headers_package_version + "?arch=" + $metadata.architecture)
        }]
      },
      {
        SPDXID: "SPDXRef-Compiler",
        name: "C compiler",
        downloadLocation: "NOASSERTION",
        filesAnalyzed: false,
        licenseConcluded: "NOASSERTION",
        licenseDeclared: "NOASSERTION",
        copyrightText: "NOASSERTION",
        comment: $metadata.compiler
      }
    ],
    files: [
      {name: "jool_common.ko", id: "SPDXRef-File-jool_common.ko", hash: $common_hash},
      {name: "jool.ko", id: "SPDXRef-File-jool.ko", hash: $nat64_hash},
      {name: "jool_siit.ko", id: "SPDXRef-File-jool_siit.ko", hash: $siit_hash}
    ] | map({
      SPDXID: .id,
      fileName: .name,
      checksums: [{algorithm: "SHA256", checksumValue: .hash}],
      licenseConcluded: "GPL-2.0-only",
      licenseInfoInFiles: ["GPL-2.0-only"],
      copyrightText: $copyright
    }),
    relationships: [
      {spdxElementId: "SPDXRef-DOCUMENT", relationshipType: "DESCRIBES", relatedSpdxElement: $package_id},
      {spdxElementId: $package_id, relationshipType: "GENERATED_FROM", relatedSpdxElement: "SPDXRef-Jool-source"},
      {spdxElementId: $package_id, relationshipType: "GENERATED_FROM", relatedSpdxElement: "SPDXRef-Kernel-headers"},
      {spdxElementId: "SPDXRef-Compiler", relationshipType: "BUILD_TOOL_OF", relatedSpdxElement: $package_id},
      {spdxElementId: $package_id, relationshipType: "CONTAINS", relatedSpdxElement: "SPDXRef-File-jool_common.ko"},
      {spdxElementId: $package_id, relationshipType: "CONTAINS", relatedSpdxElement: "SPDXRef-File-jool.ko"},
      {spdxElementId: $package_id, relationshipType: "CONTAINS", relatedSpdxElement: "SPDXRef-File-jool_siit.ko"}
    ]
  }' >"$output"
