#!/usr/bin/env bash
set -euo pipefail

data_dir_arg="${1:?Usage: aethertune-backup.sh DATA_DIR BACKUP_DIR}"
backup_dir_arg="${2:?Usage: aethertune-backup.sh DATA_DIR BACKUP_DIR}"
retention_days="${AETHERTUNE_BACKUP_RETENTION_DAYS:-30}"

if [[ ! "$retention_days" =~ ^[1-9][0-9]*$ ]]; then
  echo "AETHERTUNE_BACKUP_RETENTION_DAYS must be a positive integer." >&2
  exit 2
fi
if [[ ! -d "$data_dir_arg" ]]; then
  echo "Data directory does not exist: $data_dir_arg" >&2
  exit 1
fi

umask 077
data_dir="$(cd "$data_dir_arg" && pwd -P)"
mkdir -p "$backup_dir_arg"
backup_dir="$(cd "$backup_dir_arg" && pwd -P)"
case "$backup_dir/" in
  "$data_dir/"*)
    echo "Backup directory must not be inside the data directory." >&2
    exit 2
    ;;
esac

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive="$backup_dir/aethertune-server-data-$timestamp.tar.gz"
temporary_archive="$archive.tmp"
temporary_checksum="$archive.sha256.tmp"
trap 'rm -f "$temporary_archive" "$temporary_checksum"' EXIT

# Writes use temporary files and renames, so incomplete temporary snapshots are excluded.
# The runtime lock file is transient and must not be restored.
tar -C "$data_dir" --exclude='*.tmp' --exclude='.server.lock' -czf "$temporary_archive" .
mv "$temporary_archive" "$archive"
(
  cd "$backup_dir"
  sha256sum "$(basename "$archive")" > "$(basename "$temporary_checksum")"
  sha256sum --check "$(basename "$temporary_checksum")"
)
mv "$temporary_checksum" "$archive.sha256"

find "$backup_dir" -maxdepth 1 -type f \
  \( -name 'aethertune-server-data-*.tar.gz' -o -name 'aethertune-server-data-*.tar.gz.sha256' \) \
  -mtime +"$retention_days" -delete

printf 'Created and verified %s\n' "$archive"
