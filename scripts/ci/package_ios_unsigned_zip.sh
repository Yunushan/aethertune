#!/usr/bin/env bash
set -euo pipefail

app_bundle="${1:?unsigned iOS Flutter app bundle path is required}"
output_path="${2:?unsigned iOS ZIP output path is required}"

if [[ ! -d "$app_bundle" || "${app_bundle##*.}" != "app" ]]; then
  echo "Expected an unsigned iOS Flutter .app bundle at $app_bundle." >&2
  exit 1
fi

if [[ "$output_path" != *.zip ]]; then
  echo "Expected a .zip output path at $output_path." >&2
  exit 1
fi

info_plist="$app_bundle/Info.plist"
flutter_assets_path="$app_bundle/Frameworks/App.framework/flutter_assets/AssetManifest.bin"
if [[ ! -f "$info_plist" ]]; then
  echo "Expected iOS app metadata at $info_plist." >&2
  exit 1
fi

if [[ ! -f "$flutter_assets_path" ]]; then
  echo "Expected Flutter assets at $flutter_assets_path." >&2
  exit 1
fi

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
executable_path="$app_bundle/$executable_name"
if [[ -z "$executable_name" || ! -x "$executable_path" ]]; then
  echo "Expected an iOS app executable at $executable_path." >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
rm -f "$output_path"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$output_path"

bundle_name="$(basename "$app_bundle")"
entries="$(unzip -Z1 "$output_path")"
if ! grep -Fxq "$bundle_name/$executable_name" <<<"$entries"; then
  echo "The unsigned iOS ZIP is missing the app executable." >&2
  exit 1
fi

if ! grep -Fxq "$bundle_name/Frameworks/App.framework/flutter_assets/AssetManifest.bin" <<<"$entries"; then
  echo "The unsigned iOS ZIP is missing the Flutter asset manifest." >&2
  exit 1
fi
