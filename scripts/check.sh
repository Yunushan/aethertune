#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/bootstrap_client.sh"

cd "$ROOT_DIR/apps/mobile"
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
python3 "$ROOT_DIR/scripts/ci/build_native_transport.py" --install-toolchain --test
flutter test

cd "$ROOT_DIR/services/server"
dart pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed bin lib test
dart analyze
dart test
