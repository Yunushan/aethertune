#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/mobile"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed or not on PATH. Install Flutter first: https://docs.flutter.dev/get-started/install"
  exit 1
fi

mkdir -p "$APP_DIR"

if [ ! -d "$APP_DIR/android" ] || [ ! -d "$APP_DIR/ios" ] || [ ! -d "$APP_DIR/linux" ] || [ ! -d "$APP_DIR/macos" ] || [ ! -d "$APP_DIR/windows" ]; then
  echo "Generating Flutter mobile and desktop platform wrappers..."
  PRESERVE_DIR="$(mktemp -d)"
  restore_manifests() {
    if [ -f "$PRESERVE_DIR/pubspec.yaml" ]; then
      cp "$PRESERVE_DIR/pubspec.yaml" "$APP_DIR/pubspec.yaml"
    fi
    if [ -f "$PRESERVE_DIR/pubspec.lock" ]; then
      cp "$PRESERVE_DIR/pubspec.lock" "$APP_DIR/pubspec.lock"
    else
      rm -f "$APP_DIR/pubspec.lock"
    fi
    rm -rf "$PRESERVE_DIR"
  }
  trap restore_manifests EXIT
  cp "$APP_DIR/pubspec.yaml" "$PRESERVE_DIR/pubspec.yaml"
  if [ -f "$APP_DIR/pubspec.lock" ]; then
    cp "$APP_DIR/pubspec.lock" "$PRESERVE_DIR/pubspec.lock"
  fi
  flutter create "$APP_DIR" --project-name aethertune --org dev.aethertune --platforms android,ios,linux,macos,windows --no-pub
  restore_manifests
  trap - EXIT
fi

ANDROID_BUILD_GRADLE="$APP_DIR/android/app/build.gradle.kts"
if [ ! -f "$ANDROID_BUILD_GRADLE" ] || ! grep -q 'create("aethertuneRelease")' "$ANDROID_BUILD_GRADLE"; then
  echo "Android release signing configuration is missing from $ANDROID_BUILD_GRADLE."
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "Python 3 is required to configure generated media and secure-storage wrappers."
  exit 1
fi

"$PYTHON_BIN" "$ROOT_DIR/scripts/configure_audio_service_platforms.py" "$APP_DIR"

DEFAULT_WIDGET_TEST="$APP_DIR/test/widget_test.dart"
if [ -f "$DEFAULT_WIDGET_TEST" ] && grep -q "Counter increments smoke test" "$DEFAULT_WIDGET_TEST" && grep -q "MyApp" "$DEFAULT_WIDGET_TEST"; then
  rm "$DEFAULT_WIDGET_TEST"
fi

cd "$APP_DIR"
flutter pub get --enforce-lockfile

echo "AetherTune client is ready. Run: cd apps/mobile && flutter run"
