#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <workspace> <scheme> <output-ipa>" >&2
  exit 2
fi

workspace="$1"
scheme="$2"
output_ipa="$3"
: "${AETHERTUNE_IOS_SIGNING_IDENTITY:?AETHERTUNE_IOS_SIGNING_IDENTITY is required}"
: "${AETHERTUNE_IOS_PROVISIONING_PROFILE_PATH:?AETHERTUNE_IOS_PROVISIONING_PROFILE_PATH is required}"
: "${AETHERTUNE_IOS_EXPORT_OPTIONS_PATH:?AETHERTUNE_IOS_EXPORT_OPTIONS_PATH is required}"

if [[ ! -f "$AETHERTUNE_IOS_PROVISIONING_PROFILE_PATH" ]]; then
  echo "iOS provisioning profile does not exist: $AETHERTUNE_IOS_PROVISIONING_PROFILE_PATH" >&2
  exit 1
fi
if [[ ! -f "$AETHERTUNE_IOS_EXPORT_OPTIONS_PATH" ]]; then
  echo "iOS export options plist does not exist: $AETHERTUNE_IOS_EXPORT_OPTIONS_PATH" >&2
  exit 1
fi

runner_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
profile_plist="$runner_temp/aethertune-ios-profile.plist"
archive_path="$runner_temp/aethertune-ios.xcarchive"
export_path="$runner_temp/aethertune-ios-export"

security cms -D \
  -i "$AETHERTUNE_IOS_PROVISIONING_PROFILE_PATH" \
  -o "$profile_plist"
team_id=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$profile_plist")
profile_uuid=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$profile_plist")
if [[ -z "$team_id" || -z "$profile_uuid" ]]; then
  echo 'iOS provisioning profile is missing TeamIdentifier or UUID.' >&2
  exit 1
fi

rm -rf "$archive_path" "$export_path"
xcodebuild \
  -workspace "$workspace" \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$AETHERTUNE_IOS_SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$team_id" \
  PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
  CODE_SIGNING_REQUIRED=YES \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportOptionsPlist "$AETHERTUNE_IOS_EXPORT_OPTIONS_PATH" \
  -exportPath "$export_path"

ipa_path="$(find "$export_path" -maxdepth 1 -name '*.ipa' -type f -print -quit)"
if [[ -z "$ipa_path" ]]; then
  echo 'xcodebuild did not produce an IPA.' >&2
  exit 1
fi
mkdir -p "$(dirname "$output_ipa")"
cp "$ipa_path" "$output_ipa"

# Re-open the exported archive and verify the signature/profile that will be
# distributed, rather than relying only on the archive build step.
ipa_check_dir="$runner_temp/aethertune-ios-ipa-check"
embedded_profile_plist="$runner_temp/aethertune-ios-embedded-profile.plist"
rm -rf "$ipa_check_dir" "$embedded_profile_plist"
mkdir -p "$ipa_check_dir"
ditto -x -k "$output_ipa" "$ipa_check_dir"
app_bundle="$(find "$ipa_check_dir/Payload" -maxdepth 1 -name '*.app' -type d -print -quit)"
if [[ -z "$app_bundle" ]]; then
  echo 'Exported IPA does not contain an app bundle.' >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$app_bundle"
if [[ ! -f "$app_bundle/embedded.mobileprovision" ]]; then
  echo 'Exported IPA is missing its embedded provisioning profile.' >&2
  exit 1
fi
security cms -D \
  -i "$app_bundle/embedded.mobileprovision" \
  -o "$embedded_profile_plist"
embedded_team_id=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$embedded_profile_plist")
if [[ "$embedded_team_id" != "$team_id" ]]; then
  echo 'Exported IPA provisioning profile belongs to a different team.' >&2
  exit 1
fi
