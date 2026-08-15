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

if ! dpkg-deb --info "$package" | grep -q 'Package: aethertune'; then
  echo "Expected a valid AetherTune Debian package." >&2
  exit 1
fi

printf 'stale archive member\n' > "$workspace/stale.txt"
(
  cd "$workspace"
  ar rD "$package" stale.txt
)

if ! ar t "$package" | grep -qx 'stale.txt'; then
  echo "Expected the fixture to add a stale archive member." >&2
  exit 1
fi

bash "$package_script" "$bundle" "$package" '0.0.1'

if ar t "$package" | grep -qx 'stale.txt'; then
  echo "The Debian package retained a stale archive member." >&2
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
