#!/usr/bin/env bash
set -euo pipefail

backup_dir_arg="${1:?Usage: aethertune-verify-backups.sh BACKUP_DIR}"

if [[ ! -d "$backup_dir_arg" ]]; then
  echo "Backup directory does not exist: $backup_dir_arg" >&2
  exit 1
fi

backup_dir="$(cd "$backup_dir_arg" && pwd -P)"
shopt -s nullglob
archives=("$backup_dir"/aethertune-server-data-*.tar.gz)
checksums=("$backup_dir"/aethertune-server-data-*.tar.gz.sha256)

if (( ${#archives[@]} == 0 )); then
  echo "No AetherTune backup archives found in $backup_dir" >&2
  exit 1
fi

for archive in "${archives[@]}"; do
  checksum="$archive.sha256"
  if [[ ! -f "$checksum" ]]; then
    echo "Missing checksum sidecar: $checksum" >&2
    exit 2
  fi

  (
    cd "$backup_dir"
    sha256sum --check "$(basename "$checksum")"
  )
  tar -tzf "$archive" >/dev/null
done

for checksum in "${checksums[@]}"; do
  archive="${checksum%.sha256}"
  if [[ ! -f "$archive" ]]; then
    echo "Checksum sidecar has no matching archive: $checksum" >&2
    exit 2
  fi
done

printf 'Verified %s AetherTune backup archive(s) in %s\n' "${#archives[@]}" "$backup_dir"
