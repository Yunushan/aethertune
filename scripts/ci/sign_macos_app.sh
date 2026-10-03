#!/usr/bin/env bash
set -euo pipefail

app_bundle="${1:?macOS app bundle path is required}"
signing_identity="${2:?macOS signing identity is required}"
: "${AETHERTUNE_APPLE_KEYCHAIN_PATH:?signing keychain is required}"
: "${AETHERTUNE_MACOS_PROVISIONING_PROFILE_PATH:?reviewed Developer ID profile is required}"
: "${AETHERTUNE_MACOS_PROVISIONING_PROFILE_SHA256:?reviewed profile SHA-256 is required}"
: "${AETHERTUNE_MACOS_TEAM_ID:?expected team ID is required}"
: "${AETHERTUNE_MACOS_BUNDLE_ID:?expected bundle ID is required}"

python3 scripts/ci/macos_signing_contract.py sign \
  --app "$app_bundle" --identity "$signing_identity" \
  --keychain "$AETHERTUNE_APPLE_KEYCHAIN_PATH" \
  --profile "$AETHERTUNE_MACOS_PROVISIONING_PROFILE_PATH" \
  --profile-sha256 "$AETHERTUNE_MACOS_PROVISIONING_PROFILE_SHA256" \
  --team "$AETHERTUNE_MACOS_TEAM_ID" --bundle "$AETHERTUNE_MACOS_BUNDLE_ID" \
  --release-entitlements apps/mobile/macos/Runner/Release.entitlements \
  --output "$RUNNER_TEMP/aethertune-macos-signing.json"
