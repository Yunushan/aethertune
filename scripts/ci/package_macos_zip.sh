#!/usr/bin/env bash
set -euo pipefail

app_bundle="${1:?macOS Flutter app bundle path is required}"
output_path="${2:?macOS ZIP output path is required}"

if [[ ! -d "$app_bundle" || "${app_bundle##*.}" != "app" ]]; then
  echo "Expected a macOS Flutter .app bundle at $app_bundle." >&2
  exit 1
fi

executable_path="$app_bundle/Contents/MacOS/aethertune"
flutter_assets_path="$app_bundle/Contents/Frameworks/App.framework/flutter_assets/AssetManifest.bin"

if [[ ! -x "$executable_path" ]]; then
  echo "Expected a macOS Flutter app executable at $executable_path." >&2
  exit 1
fi

if [[ ! -f "$flutter_assets_path" ]]; then
  echo "Expected Flutter assets at $flutter_assets_path." >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
rm -f "$output_path"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$output_path"

bundle_name="$(basename "$app_bundle")"
entries="$(unzip -Z1 "$output_path")"
if ! grep -Fxq "$bundle_name/Contents/MacOS/aethertune" <<<"$entries"; then
  echo "The macOS ZIP is missing the AetherTune executable." >&2
  exit 1
fi

if ! grep -Fxq "$bundle_name/Contents/Frameworks/App.framework/flutter_assets/AssetManifest.bin" <<<"$entries"; then
  echo "The macOS ZIP is missing the Flutter asset manifest." >&2
  exit 1
fi
