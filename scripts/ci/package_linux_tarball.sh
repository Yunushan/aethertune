#!/usr/bin/env bash
set -euo pipefail

bundle_dir="${1:?Flutter Linux bundle path is required}"
output_path="${2:?Linux tarball output path is required}"

if [[ ! -d "$bundle_dir" ]]; then
  echo "Expected a Flutter Linux bundle directory at $bundle_dir." >&2
  exit 1
fi

if [[ "$output_path" != *.tar.gz ]]; then
  echo "Expected a .tar.gz output path at $output_path." >&2
  exit 1
fi

executable_path="$bundle_dir/aethertune"
flutter_assets_path="$bundle_dir/data/flutter_assets/AssetManifest.bin"

if [[ ! -x "$executable_path" ]]; then
  echo "Expected a Flutter Linux executable at $executable_path." >&2
  exit 1
fi

if [[ ! -f "$flutter_assets_path" ]]; then
  echo "Expected Flutter assets at $flutter_assets_path." >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
rm -f "$output_path"
tar -czf "$output_path" -C "$bundle_dir" .

if [[ ! -s "$output_path" ]]; then
  echo "The Linux tarball was not created at $output_path." >&2
  exit 1
fi

entries="$(tar -tzf "$output_path")"
if ! grep -Fxq './aethertune' <<<"$entries"; then
  echo "The Linux tarball is missing the AetherTune executable." >&2
  exit 1
fi

if ! grep -Fxq './data/flutter_assets/AssetManifest.bin' <<<"$entries"; then
  echo "The Linux tarball is missing the Flutter asset manifest." >&2
  exit 1
fi
