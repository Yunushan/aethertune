#!/usr/bin/env bash
set -euo pipefail

: "${AETHERTUNE_APPLE_KEYCHAIN_PATH:?AETHERTUNE_APPLE_KEYCHAIN_PATH is required}"
: "${AETHERTUNE_APPLE_KEYCHAIN_PASSWORD:?AETHERTUNE_APPLE_KEYCHAIN_PASSWORD is required}"
: "${AETHERTUNE_APPLE_CERTIFICATE_BASE64:?AETHERTUNE_APPLE_CERTIFICATE_BASE64 is required}"
: "${AETHERTUNE_APPLE_CERTIFICATE_PASSWORD:?AETHERTUNE_APPLE_CERTIFICATE_PASSWORD is required}"
: "${AETHERTUNE_APPLE_CERTIFICATE_FILE_NAME:?AETHERTUNE_APPLE_CERTIFICATE_FILE_NAME is required}"

if [[ ! -f "$AETHERTUNE_APPLE_KEYCHAIN_PATH" ]]; then
  security create-keychain \
    -p "$AETHERTUNE_APPLE_KEYCHAIN_PASSWORD" \
    "$AETHERTUNE_APPLE_KEYCHAIN_PATH"
fi
security unlock-keychain \
  -p "$AETHERTUNE_APPLE_KEYCHAIN_PASSWORD" \
  "$AETHERTUNE_APPLE_KEYCHAIN_PATH"
security set-keychain-settings \
  -lut 21600 \
  "$AETHERTUNE_APPLE_KEYCHAIN_PATH"

certificate_path="$RUNNER_TEMP/$AETHERTUNE_APPLE_CERTIFICATE_FILE_NAME"
printf '%s' "$AETHERTUNE_APPLE_CERTIFICATE_BASE64" | base64 -D > "$certificate_path"
security import "$certificate_path" \
  -f pkcs12 \
  -k "$AETHERTUNE_APPLE_KEYCHAIN_PATH" \
  -P "$AETHERTUNE_APPLE_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/xcrun
security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$AETHERTUNE_APPLE_KEYCHAIN_PASSWORD" \
  "$AETHERTUNE_APPLE_KEYCHAIN_PATH"
security list-keychains -d user -s "$AETHERTUNE_APPLE_KEYCHAIN_PATH"
security default-keychain -s "$AETHERTUNE_APPLE_KEYCHAIN_PATH"

if [[ -n "${AETHERTUNE_APPLE_SIGNING_IDENTITY:-}" ]]; then
  identities="$(security find-identity -v -p codesigning "$AETHERTUNE_APPLE_KEYCHAIN_PATH")"
  if ! grep -F -- "$AETHERTUNE_APPLE_SIGNING_IDENTITY" <<< "$identities" >/dev/null; then
    echo "Configured Apple signing identity was not imported: $AETHERTUNE_APPLE_SIGNING_IDENTITY" >&2
    exit 1
  fi
fi
