#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.44.6"
FLUTTER_COMMIT="ee80f08bbf97172ec030b8751ceab557177a34a6"
FLUTTER_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/aethertune-flutter-${FLUTTER_COMMIT}"

if [[ ! -d "$FLUTTER_ROOT/.git" ]]; then
  rm -rf -- "$FLUTTER_ROOT"
  mkdir -p "$FLUTTER_ROOT"
  git -C "$FLUTTER_ROOT" init --quiet
  git -C "$FLUTTER_ROOT" remote add origin https://github.com/flutter/flutter.git
  git -C "$FLUTTER_ROOT" fetch --depth=1 origin "$FLUTTER_COMMIT"
  git -C "$FLUTTER_ROOT" checkout --quiet --detach FETCH_HEAD
fi

actual_commit="$(git -C "$FLUTTER_ROOT" rev-parse HEAD)"
if [[ "$actual_commit" != "$FLUTTER_COMMIT" ]]; then
  echo "Flutter SDK commit mismatch: expected $FLUTTER_COMMIT, got $actual_commit" >&2
  exit 1
fi

printf 'FLUTTER_ROOT=%s\n' "$FLUTTER_ROOT" >> "$GITHUB_ENV"
printf '%s/bin\n' "$FLUTTER_ROOT" >> "$GITHUB_PATH"
export PATH="$FLUTTER_ROOT/bin:$PATH"

echo "Using Flutter $FLUTTER_VERSION at commit $actual_commit"
flutter --version
