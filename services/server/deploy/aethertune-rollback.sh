#!/usr/bin/env bash
set -euo pipefail

current_binary="${1:?Usage: aethertune-rollback.sh CURRENT_BINARY PREVIOUS_BINARY}"
previous_binary="${2:?Usage: aethertune-rollback.sh CURRENT_BINARY PREVIOUS_BINARY}"

if [[ "$current_binary" == "$previous_binary" ]]; then
  echo 'Current and previous binaries must be different paths.' >&2
  exit 2
fi
if [[ ! -f "$previous_binary" ]]; then
  echo "Previous server binary does not exist: $previous_binary" >&2
  exit 1
fi

target_dir="$(cd "$(dirname "$current_binary")" && pwd -P)"
target_name="$(basename "$current_binary")"
temporary_path="$target_dir/.$target_name.rollback.tmp"
trap 'rm -f "$temporary_path"' EXIT

# Install beside the live binary, then rename on the same filesystem for an atomic swap.
install -m 0755 "$previous_binary" "$temporary_path"
mv -f "$temporary_path" "$target_dir/$target_name"

if [[ ! -x "$target_dir/$target_name" ]]; then
  echo "Rollback did not produce an executable: $target_dir/$target_name" >&2
  exit 1
fi

printf 'Rolled back %s from %s\n' "$target_dir/$target_name" "$previous_binary"
