#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/bootstrap_client.sh"

cd "$ROOT_DIR/apps/mobile"
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

cd "$ROOT_DIR/services/server"
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed bin lib test
dart analyze
dart test
