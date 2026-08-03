#!/usr/bin/env bash
set -euo pipefail

archive="${1:?Usage: aethertune-restore.sh ARCHIVE DATA_DIR}"
data_dir="${2:?Usage: aethertune-restore.sh ARCHIVE DATA_DIR}"

if [[ ! -f "$archive" ]]; then
  echo "Backup archive does not exist: $archive" >&2
  exit 1
fi
if [[ -f "$archive.sha256" ]]; then
  sha256sum --check "$archive.sha256"
else
  echo "Missing checksum sidecar: $archive.sha256" >&2
  exit 1
fi

# Reject absolute, parent-traversal, and non-regular archive entries before extraction.
while IFS= read -r entry; do
  entry_type="${entry:0:1}"
  case "$entry_type" in
    -|d) ;;
    *)
      echo "Unsafe archive entry type: $entry" >&2
      exit 2
      ;;
  esac
done < <(tar -tvzf "$archive")

while IFS= read -r entry; do
  case "$entry" in
    /*|..|../*|*/../*|*/..|*\\*)
      echo "Unsafe archive entry: $entry" >&2
      exit 2
      ;;
  esac
done < <(tar -tzf "$archive")

if [[ -d "$data_dir" ]] && [[ -n "$(find "$data_dir" -mindepth 1 -print -quit)" ]]; then
  echo "Restore target must be empty; stop the server and move existing data first: $data_dir" >&2
  exit 2
fi
mkdir -p "$data_dir"
tar -xzf "$archive" -C "$data_dir" --no-same-owner --no-same-permissions
printf 'Restored and checksum-verified %s into %s\n' "$archive" "$data_dir"
