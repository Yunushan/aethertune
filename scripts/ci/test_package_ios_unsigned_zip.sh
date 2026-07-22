#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT

bundle="$workspace/AetherTune.app"
archive="$workspace/aethertune-ios-unsigned.zip"
package_script="$root/scripts/ci/package_ios_unsigned_zip.sh"

mkdir -p "$bundle/Frameworks/App.framework/flutter_assets"
cat > "$bundle/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>AetherTune</string></dict></plist>
EOF
printf 'fixture executable\n' > "$bundle/AetherTune"
chmod +x "$bundle/AetherTune"
printf 'fixture asset manifest\n' \
  > "$bundle/Frameworks/App.framework/flutter_assets/AssetManifest.bin"

bash "$package_script" "$bundle" "$archive"

if [[ ! -s "$archive" ]]; then
  echo "Expected unsigned iOS ZIP package at $archive." >&2
  exit 1
fi
