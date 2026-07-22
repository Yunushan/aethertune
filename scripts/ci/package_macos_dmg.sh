#!/usr/bin/env bash
set -euo pipefail

app_bundle="${1:?macOS Flutter app bundle path is required}"
output_path="${2:?macOS DMG output path is required}"

if [[ ! -d "$app_bundle" || "${app_bundle##*.}" != "app" ]]; then
  echo "Expected a macOS Flutter .app bundle at $app_bundle." >&2
  exit 1
fi

if [[ "$output_path" != *.dmg ]]; then
  echo "Expected a .dmg output path at $output_path." >&2
  exit 1
fi

executable_path="$app_bundle/Contents/MacOS/aethertune"
flutter_assets_path="$app_bundle/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/AssetManifest.bin"

if [[ ! -x "$executable_path" ]]; then
  echo "Expected a macOS Flutter app executable at $executable_path." >&2
  exit 1
fi

if [[ ! -f "$flutter_assets_path" ]]; then
  echo "Expected Flutter assets at $flutter_assets_path." >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null; then
  echo "macOS hdiutil is required to package a DMG." >&2
  exit 1
fi

staging_directory="$(mktemp -d)"
trap 'rm -rf "$staging_directory"' EXIT

bundle_name="$(basename "$app_bundle")"
ditto "$app_bundle" "$staging_directory/$bundle_name"
ln -s /Applications "$staging_directory/Applications"

mkdir -p "$(dirname "$output_path")"
rm -f "$output_path"
hdiutil create \
  -volname "AetherTune" \
  -srcfolder "$staging_directory" \
  -ov \
  -format UDZO \
  "$output_path" >/dev/null

if [[ ! -s "$output_path" ]]; then
  echo "The macOS DMG was not created at $output_path." >&2
  exit 1
fi
