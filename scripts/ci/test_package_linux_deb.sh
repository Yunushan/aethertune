#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

bundle="$workspace/bundle"
package="$workspace/aethertune-linux-x64.deb"
package_script="$root/scripts/ci/package_linux_deb.sh"

mkdir -p "$bundle/data/flutter_assets"
printf 'fixture executable\n' > "$bundle/aethertune"
chmod +x "$bundle/aethertune"
printf 'fixture asset manifest\n' > "$bundle/data/flutter_assets/AssetManifest.bin"

bash "$package_script" "$bundle" "$package" '0.0.1'

if [[ ! -s "$package" ]]; then
  echo "Expected Linux Debian package at $package." >&2
  exit 1
fi

relative_package="release/aethertune-linux-x64.deb"
(
  cd "$workspace"
  bash "$package_script" "$bundle" "$relative_package" '0.0.1'
)

if [[ ! -s "$workspace/$relative_package" ]]; then
  echo "Expected Linux Debian package at $workspace/$relative_package." >&2
  exit 1
fi
