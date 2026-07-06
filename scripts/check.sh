#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../apps/mobile"
flutter pub get
flutter analyze
flutter test
