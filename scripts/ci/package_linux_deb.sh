#!/usr/bin/env bash
set -euo pipefail

bundle_dir="${1:?Flutter Linux bundle path is required}"
output_path="${2:?Debian package output path is required}"
version="${3:?Debian package version is required}"

if [[ ! -d "$bundle_dir" || ! -x "$bundle_dir/aethertune" ]]; then
  echo "Expected a Flutter Linux bundle with an executable named aethertune." >&2
  exit 1
fi

flutter_assets_path="$bundle_dir/data/flutter_assets/AssetManifest.bin"
if [[ ! -f "$flutter_assets_path" ]]; then
  echo "Expected Flutter assets at $flutter_assets_path." >&2
  exit 1
fi

package_root="$(mktemp -d)"
trap 'rm -rf "$package_root"' EXIT
mkdir -p "$package_root/DEBIAN" "$package_root/opt/aethertune" \
  "$package_root/usr/share/applications"
cp -a "$bundle_dir/." "$package_root/opt/aethertune/"

cat > "$package_root/DEBIAN/control" <<EOF
Package: aethertune
Version: $version
Section: sound
Priority: optional
Architecture: amd64
Maintainer: AetherTune Contributors
Description: Free and open-source local-first music player
 AetherTune is a privacy-respecting music player with local files and legal providers.
EOF

cat > "$package_root/usr/share/applications/aethertune.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=AetherTune
Comment=Free and open-source music player
Exec=/opt/aethertune/aethertune
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupNotify=true
EOF

mkdir -p "$(dirname "$output_path")"
dpkg-deb --build --root-owner-group "$package_root" "$output_path"
dpkg-deb --info "$output_path" >/dev/null
dpkg-deb --contents "$output_path" | grep -q '/opt/aethertune/aethertune$'
dpkg-deb --contents "$output_path" | grep -q '/opt/aethertune/data/flutter_assets/AssetManifest.bin$'
dpkg-deb --contents "$output_path" | grep -q '/usr/share/applications/aethertune.desktop$'
