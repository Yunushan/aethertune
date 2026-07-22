#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

bundle="$workspace/bundle"
archive="$workspace/aethertune-linux-x64.tar.gz"
package_script="$root/scripts/ci/package_linux_tarball.sh"

mkdir -p "$bundle/data/flutter_assets"
printf 'fixture executable\n' > "$bundle/aethertune"
chmod +x "$bundle/aethertune"
printf 'fixture asset manifest\n' > "$bundle/data/flutter_assets/AssetManifest.bin"

bash "$package_script" "$bundle" "$archive"

if [[ ! -s "$archive" ]]; then
  echo "Expected Linux tarball package at $archive." >&2
  exit 1
fi
