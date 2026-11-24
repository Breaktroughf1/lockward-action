#!/usr/bin/env bash
# Downloads a Lockward release, verifies the Sigstore signature on
# checksums.txt (identity: this repository's release workflow at the
# matching tag), verifies the archive checksum, and puts lockward on PATH.
# Nothing is run until both checks pass (LW-FR-14, THREAT_MODEL T11).
set -euo pipefail

version="${LOCKWARD_VERSION:?set the version input}"
version="${version#v}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "::error::invalid lockward version: $version" >&2
  exit 1
fi

case "${RUNNER_OS:-}" in
  Linux) os=linux; ext=tar.gz ;;
  macOS) os=darwin; ext=tar.gz ;;
  Windows) os=windows; ext=zip ;;
  *) echo "::error::unsupported runner OS: ${RUNNER_OS:-unknown}" >&2; exit 1 ;;
esac
case "${RUNNER_ARCH:-}" in
  X64) arch=amd64 ;;
  ARM64) arch=arm64 ;;
  *) echo "::error::unsupported runner architecture: ${RUNNER_ARCH:-unknown}" >&2; exit 1 ;;
esac

repo="Breaktroughf1/lockward"
archive="lockward_${version}_${os}_${arch}.${ext}"
base="https://github.com/${repo}/releases/download/v${version}"
dir="${RUNNER_TEMP:-/tmp}/lockward-${version}"
mkdir -p "$dir"
cd "$dir"

for f in "$archive" checksums.txt checksums.txt.sigstore.json; do
  curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 -o "$f" "$base/$f"
done

cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity "https://github.com/${repo}/.github/workflows/release.yml@refs/tags/v${version}" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt

expected="$(awk -v f="$archive" '$2 == f { print $1 }' checksums.txt)"
if [[ -z "$expected" ]]; then
  echo "::error::$archive is not listed in checksums.txt" >&2
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$archive" | awk '{ print $1 }')"
else
  actual="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
fi
if [[ "$actual" != "$expected" ]]; then
  echo "::error::checksum mismatch for $archive (expected $expected, got $actual)" >&2
  exit 1
fi

if [[ "$ext" == zip ]]; then
  unzip -q -o "$archive" lockward.exe
else
  tar -xzf "$archive" lockward
fi
echo "$dir" >> "$GITHUB_PATH"
echo "Installed lockward $version (signature and checksum verified)."
