#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

bundle="$workspace/aethertune.app"
archive="$workspace/aethertune-macos.zip"
package_script="$root/scripts/ci/package_macos_zip.sh"

mkdir -p "$bundle/Contents/MacOS" \
  "$bundle/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets"
printf 'fixture executable\n' > "$bundle/Contents/MacOS/aethertune"
chmod +x "$bundle/Contents/MacOS/aethertune"
printf 'fixture asset manifest\n' \
  > "$bundle/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/AssetManifest.bin"

bash "$package_script" "$bundle" "$archive"

if [[ ! -f "$archive" ]]; then
  echo "Expected macOS ZIP package at $archive." >&2
  exit 1
fi
