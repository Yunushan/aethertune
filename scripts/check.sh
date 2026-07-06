#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/bootstrap_client.sh"

cd "$ROOT_DIR/apps/mobile"
flutter pub get
flutter analyze
flutter test

cd "$ROOT_DIR/services/server"
dart pub get
dart analyze
dart test
