#!/usr/bin/env bash
set -euo pipefail

app_bundle="${1:?macOS app bundle path is required}"
signing_identity="${2:?macOS signing identity is required}"

if [[ ! -d "$app_bundle" || "${app_bundle##*.}" != "app" ]]; then
  echo "Expected a macOS .app bundle at $app_bundle." >&2
  exit 1
fi

codesign \
  --deep \
  --force \
  --options runtime \
  --timestamp \
  --sign "$signing_identity" \
  "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"
