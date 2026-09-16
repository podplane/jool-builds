# Prebuilt Jool kernel modules for Debian

This repository builds and publishes Jool kernel modules for the kernels used by official Debian cloud images. It replaces instance-side DKMS compilation: an instance needs only `jool-tools`, the exact matching module archive, and tools to verify and install it.

Initial support is for Debian 13 (Trixie) cloud kernels on `amd64` and `arm64`. Debian's `linux-image-cloud-*` packages cover Amazon EC2 and Google Compute Engine, as well as other cloud platforms.

## Compatibility and releases

A release includes packages for one Jool version and Debian kernel ABI. Example release tag:

```text
jool-4.1.15-kernel-6.12.48+deb13
```

Each release artifact is specific to:

```text
Jool version + exact kernel ABI + architecture
```

For example, architecture-specific archives in a release are named:

```text
jool-4.1.15-6.12.48+deb13-amd64.tar.gz
jool-4.1.15-6.12.48+deb13-arm64.tar.gz
```

Each archive's `metadata.json` records the exact kernel release, such as `6.12.48+deb13-cloud-amd64`, and every module's `vermagic` is validated against it. Installers must compare this value exactly with `uname -r`.

Every module archive contains the GPLv2 text as `COPYING`, Jool's copyright and warranty notice as `NOTICE`, and corresponding-source information as `SOURCE`. Each release also publishes the exact upstream Jool source archive used for the build. The source and module archives are covered by `SHA256SUMS` and signed with keyless Sigstore; each architecture additionally has an SPDX 2.3 JSON SBOM. Once published, releases are never modified or deleted.

## Automation

[`check.yaml`](.github/workflows/check.yaml) runs regularly and can be dispatched manually. It:

1. exits if a build is already queued or running;
2. discovers the latest stable upstream Jool release;
3. reads Debian's Trixie, Trixie updates, and Trixie security package indexes;
4. finds cloud header ABIs available for both supported architectures;
5. compares the complete expected asset set with published GitHub Releases; and
6. dispatches [`build.yaml`](.github/workflows/build.yaml) only when a release is absent.

`build.yaml` uses native GitHub-hosted runners for each architecture and a Debian Trixie container. It installs the exact header package, compiles all three Jool modules (`jool_common.ko`, `jool.ko`, and `jool_siit.ko`), validates their architecture, Jool version, and kernel `vermagic`, packages them with the required licensing materials, creates an SBOM, signs the module and corresponding-source archives and checksums with keyless Sigstore, and publishes a draft only after every asset is ready. Publishing the draft is the final operation, preventing partially published releases from being mistaken for complete immutable releases.

To add another Debian release, pass another `suite:release` pair to `scripts/discover-kernels.sh` in `check.yaml`.

## Installing an artifact

Install Debian's userspace tooling without DKMS:

```sh
sudo apt-get install jool-tools
kernel="$(uname -r)"
arch="$(dpkg --print-architecture)"
```

Derive the release-level ABI only after requiring the supported exact suffix:

```sh
case "$kernel:$arch" in
  *-cloud-amd64:amd64) abi="${kernel%-cloud-amd64}" ;;
  *-cloud-arm64:arm64) abi="${kernel%-cloud-arm64}" ;;
  *) echo "unsupported kernel: $kernel ($arch)" >&2; exit 1 ;;
esac
```

Download the archive, its Sigstore bundle, `SHA256SUMS`, and its bundle from the matching release. Verify the GitHub Actions identity (replace `OWNER` and `REPOSITORY` with this repository's canonical location):

```sh
identity="https://github.com/OWNER/REPOSITORY/.github/workflows/build.yaml@refs/heads/main"
issuer="https://token.actions.githubusercontent.com"

cosign verify-blob \
  --bundle "jool-${JOOL_VERSION}-${abi}-${arch}.sigstore.json" \
  --certificate-identity "$identity" \
  --certificate-oidc-issuer "$issuer" \
  "jool-${JOOL_VERSION}-${abi}-${arch}.tar.gz"
cosign verify-blob \
  --bundle SHA256SUMS.sigstore.json \
  --certificate-identity "$identity" \
  --certificate-oidc-issuer "$issuer" \
  SHA256SUMS
sha256sum --check --ignore-missing SHA256SUMS
```

Before installation, require `.kernel_release == uname -r` and `.architecture == dpkg --print-architecture` in `metadata.json`. Then install the modules under the exact kernel's module tree:

```sh
sudo install -d "/lib/modules/$kernel/extra/jool"
sudo install -m 0644 jool_common.ko jool.ko jool_siit.ko "/lib/modules/$kernel/extra/jool/"
sudo depmod -a "$kernel"
sudo modprobe jool
```

The Sigstore signatures authenticate release artifacts; they are not kernel Secure Boot signatures. Hosts enforcing signed out-of-tree modules must enroll and apply their own module-signing key before `modprobe`.

## Development

Install [mise](https://mise.jdx.dev/), then install the pinned ShellCheck and actionlint versions plus the repository Git hooks:

```sh
make setup
```

The pre-commit hook runs the fast, read-only `make precommit` checks. The commit-message hook requires a Developer Certificate of Origin sign-off; use `git commit -s`.

Run the complete fixture-backed test and lint suite with:

```sh
make check
```
