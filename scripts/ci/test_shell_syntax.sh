#!/usr/bin/env bash
set -euo pipefail

while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(
  find . \
    -path './.git' -prune -o \
    -type f -name '*.sh' -print0 \
    | sort -z
)
