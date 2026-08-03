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

output_directory="$(dirname "$output_path")"
mkdir -p "$output_directory"
output_path="$(cd "$output_directory" && pwd)/$(basename "$output_path")"

# Keep the staging directory beside the bundle so regular files can be
# hard-linked instead of duplicating the entire Flutter bundle on disk.
package_root="$(mktemp -d "$output_directory/.aethertune-deb.XXXXXX")"
archive_root="$(mktemp -d "$output_directory/.aethertune-deb-archives.XXXXXX")"
trap 'rm -rf "$package_root" "$archive_root"' EXIT
mkdir -p "$package_root/DEBIAN" "$package_root/opt/aethertune" \
  "$package_root/usr/share/applications"
cp -al "$bundle_dir/." "$package_root/opt/aethertune/"

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

# Assemble the ar container explicitly. This avoids a runner-specific
# dpkg-deb tar pipe failure while preserving the standard Debian package
# members and metadata.
if ! command -v ar >/dev/null 2>&1; then
  echo "The ar utility is required to build a Debian package." >&2
  exit 1
fi
printf '2.0\n' > "$archive_root/debian-binary"
tar --format=gnu --owner=0 --group=0 --numeric-owner --mtime='UTC 1970-01-01' \
  -C "$package_root/DEBIAN" -cf "$archive_root/control.tar" .
tar --format=gnu --owner=0 --group=0 --numeric-owner --mtime='UTC 1970-01-01' \
  --exclude='./DEBIAN' -C "$package_root" -cf "$archive_root/data.tar" .
(
  cd "$archive_root"
  ar rD "$output_path" debian-binary control.tar data.tar
)
dpkg-deb --info "$output_path" >/dev/null
contents_file="$archive_root/contents.txt"
dpkg-deb --contents "$output_path" > "$contents_file"
grep -q '/opt/aethertune/aethertune$' "$contents_file"
grep -q '/opt/aethertune/data/flutter_assets/AssetManifest.bin$' "$contents_file"
grep -q '/usr/share/applications/aethertune.desktop$' "$contents_file"
