#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/mobile"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed or not on PATH. Install Flutter first: https://docs.flutter.dev/get-started/install"
  exit 1
fi

mkdir -p "$APP_DIR"

if [ ! -d "$APP_DIR/android" ] || [ ! -d "$APP_DIR/ios" ]; then
  echo "Generating Flutter Android/iOS platform wrappers..."
  flutter create "$APP_DIR" \
    --project-name aethertune \
    --org dev.aethertune \
    --platforms android,ios
fi

DEFAULT_WIDGET_TEST="$APP_DIR/test/widget_test.dart"
if [ -f "$DEFAULT_WIDGET_TEST" ] &&
  grep -q "Counter increments smoke test" "$DEFAULT_WIDGET_TEST" &&
  grep -q "MyApp" "$DEFAULT_WIDGET_TEST"; then
  rm "$DEFAULT_WIDGET_TEST"
fi

cd "$APP_DIR"
flutter pub get

echo "AetherTune is ready. Run: cd apps/mobile && flutter run"
