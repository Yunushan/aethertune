#!/usr/bin/env bash
set -euo pipefail

tag_name="${1:?Usage: verify_release_version.sh TAG_NAME PUBSPEC_PATH}"
pubspec_path="${2:?Usage: verify_release_version.sh TAG_NAME PUBSPEC_PATH}"

if [[ ! "$tag_name" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release tag must use vMAJOR.MINOR.PATCH: $tag_name" >&2
  exit 1
fi
if [[ ! -f "$pubspec_path" ]]; then
  echo "Pubspec does not exist: $pubspec_path" >&2
  exit 1
fi

tag_version="${tag_name#v}"
app_version="$(awk '/^version:/ {print $2; exit}' "$pubspec_path" | cut -d+ -f1)"
if [[ -z "$app_version" ]]; then
  echo "Pubspec has no version field: $pubspec_path" >&2
  exit 1
fi
if [[ "$tag_version" != "$app_version" ]]; then
  echo "Release tag $tag_name does not match app version $app_version" >&2
  exit 1
fi

printf 'Release version verified: %s\n' "$tag_name"
