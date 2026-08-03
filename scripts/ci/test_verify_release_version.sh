#!/usr/bin/env bash
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
pubspec="$root/pubspec.yaml"
printf 'version: 1.2.3+7\n' > "$pubspec"

bash scripts/ci/verify_release_version.sh v1.2.3 "$pubspec" >/dev/null
if bash scripts/ci/verify_release_version.sh v1.2.4 "$pubspec" >/dev/null 2>&1; then
  echo 'Version mismatch was accepted.' >&2
  exit 1
fi
if bash scripts/ci/verify_release_version.sh release-1.2.3 "$pubspec" >/dev/null 2>&1; then
  echo 'Malformed release tag was accepted.' >&2
  exit 1
fi
