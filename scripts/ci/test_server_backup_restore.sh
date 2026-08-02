#!/usr/bin/env bash
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
data_dir="$root/data"
backup_dir="$root/backups"
restore_dir="$root/restored"
mkdir -p "$data_dir"
printf '%s\n' '{"revision":1,"snapshot":{"name":"fixture"}}' > "$data_dir/library.json"

bash services/server/deploy/aethertune-backup.sh "$data_dir" "$backup_dir"
archive="$(find "$backup_dir" -maxdepth 1 -type f -name '*.tar.gz' -print -quit)"
if [[ -z "$archive" ]]; then
  echo 'Backup script did not create an archive.' >&2
  exit 1
fi
bash services/server/deploy/aethertune-restore.sh "$archive" "$restore_dir"
cmp "$data_dir/library.json" "$restore_dir/library.json"

non_empty_restore="$root/non-empty-restore"
mkdir -p "$non_empty_restore"
printf 'existing\n' > "$non_empty_restore/existing.txt"
if bash services/server/deploy/aethertune-restore.sh "$archive" "$non_empty_restore"; then
  echo 'Restore unexpectedly accepted a non-empty target.' >&2
  exit 1
fi

tampered_archive="$root/tampered.tar.gz"
cp "$archive" "$tampered_archive"
original_checksum="$(sha256sum "$archive" | awk '{print $1}')"
printf '%s  %s\n' "$original_checksum" "$tampered_archive" > "$tampered_archive.sha256"
printf 'tampered\n' >> "$tampered_archive"
if bash services/server/deploy/aethertune-restore.sh "$tampered_archive" "$root/tampered-restore"; then
  echo 'Restore unexpectedly accepted a checksum-mismatched archive.' >&2
  exit 1
fi

if bash services/server/deploy/aethertune-backup.sh "$data_dir" "$data_dir/backups"; then
  echo 'Backup unexpectedly accepted a backup directory inside the data directory.' >&2
  exit 1
fi

symlink_archive="$root/symlink.tar.gz"
symlink_source="$root/symlink-source"
mkdir -p "$symlink_source"
printf 'outside\n' > "$root/outside.txt"
ln -s "$root/outside.txt" "$symlink_source/escape.txt"
tar -C "$symlink_source" -czf "$symlink_archive" .
sha256sum "$symlink_archive" > "$symlink_archive.sha256"
if bash services/server/deploy/aethertune-restore.sh "$symlink_archive" "$root/symlink-restore"; then
  echo 'Restore unexpectedly accepted a symlink archive entry.' >&2
  exit 1
fi
