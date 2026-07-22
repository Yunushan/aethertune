#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="$(mktemp -d)"
mountpoint="$workspace/mounted"
mounted=0

cleanup() {
  if [[ "$mounted" -eq 1 ]]; then
    hdiutil detach "$mountpoint" >/dev/null
  fi
  rm -rf "$workspace"
}
trap cleanup EXIT

bundle="$workspace/aethertune.app"
image="$workspace/aethertune-macos.dmg"
package_script="$root/scripts/ci/package_macos_dmg.sh"

mkdir -p "$bundle/Contents/MacOS" \
  "$bundle/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets" \
  "$mountpoint"
printf 'fixture executable\n' > "$bundle/Contents/MacOS/aethertune"
chmod +x "$bundle/Contents/MacOS/aethertune"
printf 'fixture asset manifest\n' \
  > "$bundle/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/AssetManifest.bin"

bash "$package_script" "$bundle" "$image"

if [[ ! -s "$image" ]]; then
  echo "Expected macOS DMG package at $image." >&2
  exit 1
fi

hdiutil attach -nobrowse -readonly -mountpoint "$mountpoint" "$image" >/dev/null
mounted=1

if [[ ! -x "$mountpoint/aethertune.app/Contents/MacOS/aethertune" ]]; then
  echo "The macOS DMG is missing the AetherTune executable." >&2
  exit 1
fi

if [[ ! -f "$mountpoint/aethertune.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/AssetManifest.bin" ]]; then
  echo "The macOS DMG is missing the Flutter asset manifest." >&2
  exit 1
fi

if [[ ! -L "$mountpoint/Applications" ]]; then
  echo "The macOS DMG is missing the Applications shortcut." >&2
  exit 1
fi

hdiutil detach "$mountpoint" >/dev/null
mounted=0
