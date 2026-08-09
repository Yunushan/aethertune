#!/usr/bin/env bash
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
current="$root/bin/aethertune-server"
previous="$root/releases/aethertune-server.previous"
mkdir -p "$(dirname "$current")" "$(dirname "$previous")"
printf 'current\n' > "$current"
printf 'previous\n' > "$previous"
chmod 0755 "$current" "$previous"

bash services/server/deploy/aethertune-rollback.sh "$current" "$previous"
cmp "$current" "$previous"
test -x "$current"

if bash services/server/deploy/aethertune-rollback.sh "$current" "$root/missing"; then
  echo 'Rollback unexpectedly accepted a missing previous binary.' >&2
  exit 1
fi

if bash services/server/deploy/aethertune-rollback.sh "$current" "$current"; then
  echo 'Rollback unexpectedly accepted identical binary paths.' >&2
  exit 1
fi
