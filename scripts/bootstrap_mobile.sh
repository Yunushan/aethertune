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
    --project-name aethertune_mobile \
    --org dev.aethertune \
    --platforms android,ios
fi

cd "$APP_DIR"
flutter pub get

echo "AetherTune Mobile is ready. Run: cd apps/mobile && flutter run"
