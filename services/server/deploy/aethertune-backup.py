#!/usr/bin/env python3
"""Coordinated server snapshots and bounded, validated restores (Python 3.10+)."""

import argparse
import contextlib
import ctypes
import datetime as dt
import errno
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tarfile
import tempfile
import time
import uuid

RUNTIME_FILES = {'.server.lock', '.server.instance.lock', '.backup.intent.lock', '.backup.snapshot.lock'}
MANIFEST = '.aethertune-backup.json'
MAX_BYTES = 16 * 1024**3
MAX_FILES = 100_000
MAX_MANIFEST_BYTES = 32 * 1024**2
MAX_METADATA_BYTES = 1024**2


class BackupError(Exception):
    pass


class BoundedTarInfo(tarfile.TarInfo):
    def __setattr__(self, name, value):
        super().__setattr__(name, value)
        # Validate public attributes as they are parsed, before tarfile loads
        # extension payloads. This also covers Python's internal parser paths.
        if name in ('type', 'size'):
            kind, size = getattr(self, 'type', None), getattr(self, 'size', 0)
            if kind == tarfile.GNUTYPE_SPARSE:
                raise BackupError('Sparse archives are not supported.')
            if kind in (tarfile.XHDTYPE, tarfile.XGLTYPE, tarfile.GNUTYPE_LONGNAME,
                        tarfile.GNUTYPE_LONGLINK) and size > MAX_METADATA_BYTES:
                raise BackupError('Archive metadata exceeds its size limit.')


class FileLock:
    """The same first-byte record locks used by Dart, not Unix flock locks."""

    def __init__(self, path, *, shared=False, timeout=30):
        self.path, self.shared, self.timeout = Path(path), shared, timeout
        self.file = None

    def __enter__(self):
        if self.path.exists() or self.path.is_symlink():
            _regular(self.path)
        self.file = self._open()
        deadline = time.monotonic() + self.timeout
        try:
            while True:
                try:
                    self._lock()
                    return self
                except OSError as error:
                    if error.errno not in (errno.EACCES, errno.EAGAIN) and getattr(error, 'winerror', None) != 33:
                        raise
                    if time.monotonic() >= deadline:
                        raise BackupError(f'Timed out acquiring {self.path.name}; no snapshot was published.') from error
                    time.sleep(0.025)
        except BaseException:
            self.file.close()
            raise

    def _open(self):
        flags = os.O_RDWR | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0)
        try:
            descriptor = os.open(self.path, flags | os.O_CREAT | os.O_EXCL, 0o600)
            created = True
        except FileExistsError:
            descriptor = os.open(self.path, flags)
            created = False
        try:
            metadata = os.fstat(descriptor)
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1 or getattr(metadata, 'st_file_attributes', 0) & 0x400:
                raise BackupError(f'Lock must be a single regular file: {self.path}')
            if created and os.name == 'posix' and os.geteuid() == 0:
                # Root backups may precede the first upgraded server start.
                # New locks must remain writable by the data-directory owner.
                owner = self.path.parent.stat()
                os.fchown(descriptor, owner.st_uid, owner.st_gid)
            return os.fdopen(descriptor, 'r+b')
        except BaseException:
            os.close(descriptor)
            raise

    def _lock(self):
        if os.name != 'nt':
            import fcntl
            fcntl.lockf(self.file.fileno(), (fcntl.LOCK_SH if self.shared else fcntl.LOCK_EX) | fcntl.LOCK_NB, 1, 0)
            return
        import msvcrt
        from ctypes import wintypes

        class Overlapped(ctypes.Structure):
            _fields_ = [('Internal', ctypes.c_size_t), ('InternalHigh', ctypes.c_size_t),
                        ('Offset', wintypes.DWORD), ('OffsetHigh', wintypes.DWORD), ('hEvent', wintypes.HANDLE)]

        api = ctypes.WinDLL('kernel32', use_last_error=True)
        api.LockFileEx.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD,
                                   wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(Overlapped)]
        api.LockFileEx.restype = wintypes.BOOL
        overlapped = Overlapped()
        if not api.LockFileEx(msvcrt.get_osfhandle(self.file.fileno()), 1 | (0 if self.shared else 2), 0, 1, 0, ctypes.byref(overlapped)):
            raise ctypes.WinError(ctypes.get_last_error())

    def __exit__(self, *unused):
        # Closing releases the OS lock even when the owner is terminated.
        self.file.close()


@contextlib.contextmanager
def snapshot_lock(data_dir, timeout=30):
    """Stop new data requests, drain existing ones, then fence all stores."""
    data_dir = Path(data_dir)
    with FileLock(data_dir / '.server.lock', shared=True, timeout=timeout):
        with FileLock(data_dir / '.backup.intent.lock', timeout=timeout):
            with FileLock(data_dir / '.backup.snapshot.lock', timeout=timeout):
                yield


def _regular(path):
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode) or getattr(metadata, 'st_file_attributes', 0) & 0x400:
        raise BackupError(f'Expected a regular file, not a link or special file: {path}')
    return metadata


def _digest(handle):
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b''):
        digest.update(chunk)
    return digest.hexdigest()


def _sync_directory(path):
    if os.name != 'nt':
        descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


def _data_files(root):
    for directory, names, files in os.walk(root, followlinks=False):
        names.sort()
        files.sort()
        for name in names:
            item = Path(directory) / name
            metadata = item.lstat()
            if not stat.S_ISDIR(metadata.st_mode) or item.is_symlink() or getattr(metadata, 'st_file_attributes', 0) & 0x400:
                raise BackupError(f'Unsafe data directory: {item}')
        for name in files:
            item = Path(directory) / name
            relative = item.relative_to(root).as_posix()
            if relative in RUNTIME_FILES or name.endswith('.tmp'):
                continue
            if relative == MANIFEST:
                raise BackupError('Data directory contains the reserved backup manifest name.')
            _regular(item)
            yield item, relative


def backup(data_dir, backup_dir, *, timeout=30, retention_days=30, max_bytes=MAX_BYTES):
    data_dir = Path(data_dir).resolve(strict=True)
    if not data_dir.is_dir():
        raise BackupError('Data directory does not exist.')
    backup_dir = Path(backup_dir).resolve()
    if backup_dir == data_dir or data_dir in backup_dir.parents:
        raise BackupError('Backup directory must not be inside the data directory.')
    if retention_days <= 0 or timeout < 0 or max_bytes <= 0:
        raise BackupError('Invalid backup retention, timeout, or size limit.')
    backup_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    name = f"aethertune-server-data-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%S.%fZ}-{uuid.uuid4().hex[:8]}.tar.gz"
    archive = backup_dir / name
    temporary = archive.with_name(archive.name + '.tmp')
    sidecar = archive.with_name(archive.name + '.sha256')
    checksum_temp = sidecar.with_name(sidecar.name + '.tmp')
    try:
        with snapshot_lock(data_dir, timeout):
            manifest = {'format': 1, 'snapshotUtc': dt.datetime.now(dt.timezone.utc).isoformat(), 'files': {}}
            total = 0
            with temporary.open('xb') as output:
                with tarfile.open(fileobj=output, mode='w:gz') as bundle:
                    for item, relative in _data_files(data_dir):
                        size = item.stat().st_size
                        total += size
                        if total > max_bytes or len(manifest['files']) >= MAX_FILES:
                            raise BackupError('Server snapshot exceeds the configured backup bounds.')
                        with item.open('rb') as source:
                            digest = _digest(source)
                            source.seek(0)
                            info = tarfile.TarInfo(relative)
                            info.size, info.mode = size, 0o600
                            bundle.addfile(info, source)
                        manifest['files'][relative] = {'size': size, 'sha256': digest}
                    payload = json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()
                    if len(payload) > MAX_MANIFEST_BYTES:
                        raise BackupError('Backup manifest exceeds its size limit.')
                    info = tarfile.TarInfo(MANIFEST)
                    info.size, info.mode = len(payload), 0o600
                    bundle.addfile(info, io.BytesIO(payload))
                output.flush()
                os.fsync(output.fileno())
        with temporary.open('rb') as source:
            digest = _digest(source)
        with checksum_temp.open('x', encoding='ascii') as output:
            output.write(f'{digest}  {archive.name}\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, archive)
        os.replace(checksum_temp, sidecar)
        _sync_directory(backup_dir)
        cutoff = time.time() - retention_days * 86400
        for old in backup_dir.glob('aethertune-server-data-*.tar.gz'):
            if old != archive and not old.is_symlink() and old.is_file() and old.stat().st_mtime < cutoff:
                old.unlink()
                old.with_name(old.name + '.sha256').unlink(missing_ok=True)
        return archive
    finally:
        temporary.unlink(missing_ok=True)
        checksum_temp.unlink(missing_ok=True)


def _verify_checksum(archive):
    _regular(archive)
    sidecar = archive.with_name(archive.name + '.sha256')
    if not sidecar.exists():
        raise BackupError(f'Missing checksum sidecar: {sidecar}')
    if _regular(sidecar).st_size > 4096:
        raise BackupError('Checksum sidecar is too large.')
    match = re.fullmatch(r'([a-fA-F0-9]{64})[ \t]+\*?([^\r\n]+)\r?\n?', sidecar.read_text(encoding='utf-8'))
    if not match or match[2].replace('\\', '/').split('/')[-1] != archive.name:
        raise BackupError('Checksum sidecar must identify this archive only.')
    with archive.open('rb') as source:
        if _digest(source) != match[1].lower():
            raise BackupError('Backup archive checksum mismatch.')


def _member_name(member):
    name = member.name
    if any(ord(char) < 32 for char in name) or '\\' in name or ':' in name:
        raise BackupError(f'Unsafe archive entry: {name!r}')
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts:
        raise BackupError(f'Unsafe archive entry: {name!r}')
    if len(name) > 4096 or len(path.parts) > 64:
        raise BackupError('Archive path exceeds its size limit.')
    for part in path.parts:
        if part.endswith((' ', '.')) or re.fullmatch(r'(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?', part, re.IGNORECASE):
            raise BackupError(f'Non-portable archive entry: {name!r}')
    if not (member.isfile() or member.isdir()) or member.sparse is not None:
        raise BackupError(f'Unsafe archive entry type: {name!r}')
    return path.as_posix()


def inspect_archive(archive, *, destination=None, max_bytes=MAX_BYTES):
    archive = Path(archive).absolute()
    _verify_checksum(archive)
    manifest = None
    has_manifest = False
    actual = {}
    names = set()
    paths = {}
    files = set()
    directories = set()
    total = 0
    with tarfile.open(archive, 'r:gz', tarinfo=BoundedTarInfo) as bundle:
        for member in bundle:
            name = _member_name(member)
            if name == '.' and member.isdir():
                continue
            key = name.casefold()
            if key in names or len(names) >= MAX_FILES + 1:
                raise BackupError('Duplicate, case-aliased, or excessive archive entries.')
            names.add(key)
            parts = PurePosixPath(name).parts
            for index in range(1, len(parts) + 1):
                prefix = '/'.join(parts[:index])
                folded = prefix.casefold()
                if (folded in paths and paths[folded] != prefix) or (index < len(parts) and folded in files):
                    raise BackupError('Archive paths alias or traverse an archived file.')
                paths[folded] = prefix
                if index < len(parts) or member.isdir():
                    directories.add(folded)
            if member.isfile():
                if key in directories:
                    raise BackupError('Archive file replaces an existing directory.')
                files.add(key)
            if member.isdir():
                continue
            if name in RUNTIME_FILES:
                raise BackupError('Archive includes a transient runtime lock.')
            if name == MANIFEST:
                if member.size > MAX_MANIFEST_BYTES:
                    raise BackupError('Backup manifest exceeds its size limit.')
                has_manifest = True
                manifest = json.load(bundle.extractfile(member))
                continue
            total += member.size
            if member.size < 0 or total > max_bytes:
                raise BackupError('Uncompressed archive exceeds its size limit.')
            digest = hashlib.sha256()
            with contextlib.ExitStack() as stack:
                source = stack.enter_context(bundle.extractfile(member))
                output = None
                if destination is not None:
                    target = destination.joinpath(*PurePosixPath(name).parts)
                    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                    if shutil.disk_usage(target.parent).free < member.size:
                        raise BackupError('Insufficient free space for restore.')
                    output = stack.enter_context(target.open('xb'))
                received = 0
                for chunk in iter(lambda: source.read(1024 * 1024), b''):
                    received += len(chunk)
                    digest.update(chunk)
                    if output is not None:
                        output.write(chunk)
                if received != member.size:
                    raise BackupError('Incomplete archive member.')
                if output is not None:
                    output.flush()
                    os.fsync(output.fileno())
            actual[name] = {'size': member.size, 'sha256': digest.hexdigest()}
    if has_manifest and (not isinstance(manifest, dict) or type(manifest.get('format')) is not int or manifest.get('format') != 1 or manifest.get('files') != actual):
        raise BackupError('Backup manifest does not match the archived files.')
    return {'fileCount': len(actual), 'byteCount': total, 'manifestVerified': has_manifest}


def restore(archive, data_dir, *, max_bytes=MAX_BYTES):
    target = Path(data_dir).absolute()
    if target.is_symlink() or (target.exists() and (getattr(target.lstat(), 'st_file_attributes', 0) & 0x400 or not target.is_dir() or any(target.iterdir()))):
        raise BackupError('Restore target must be empty; stop the server and move existing data first.')
    target.parent.mkdir(parents=True, exist_ok=True)
    parent = target.parent.resolve(strict=True)
    target = parent / target.name
    staging = Path(tempfile.mkdtemp(prefix=f'.{target.name}-restore-', dir=parent)).resolve()
    try:
        report = inspect_archive(archive, destination=staging, max_bytes=max_bytes)
        for directory, _, _ in os.walk(staging, topdown=False):
            _sync_directory(directory)
        if target.exists():
            target.rmdir()  # Only an empty directory can be replaced.
        os.replace(staging, target)
        _sync_directory(parent)
        return report
    finally:
        if staging.exists():
            if staging.parent != parent or not staging.name.startswith(f'.{target.name}-restore-'):
                raise BackupError('Refusing cleanup outside the restore staging directory.')
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['backup', 'restore', 'verify'])
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path, nargs='?')
    parser.add_argument('--lock-timeout', type=float, default=30)
    parser.add_argument('--max-bytes', type=int, default=MAX_BYTES)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.max_bytes <= 0:
            raise BackupError('Maximum bytes must be positive.')
        if args.mode == 'backup':
            if args.destination is None:
                parser.error('backup needs DATA_DIR BACKUP_DIR')
            retention = int(os.environ.get('AETHERTUNE_BACKUP_RETENTION_DAYS', '30'))
            print(backup(args.source, args.destination, timeout=args.lock_timeout, retention_days=retention, max_bytes=args.max_bytes))
        elif args.mode == 'restore':
            if args.destination is None:
                parser.error('restore needs ARCHIVE DATA_DIR')
            print(json.dumps(restore(args.source, args.destination, max_bytes=args.max_bytes)))
        else:
            if args.source.is_dir():
                archives = sorted(args.source.glob('aethertune-server-data-*.tar.gz'))
                for sidecar in args.source.glob('aethertune-server-data-*.tar.gz.sha256'):
                    if not sidecar.with_name(sidecar.name.removesuffix('.sha256')).is_file():
                        raise BackupError('Checksum sidecar has no matching archive.')
            else:
                archives = [args.source]
            if not archives:
                raise BackupError('No backup archives found.')
            for archive in archives:
                print(json.dumps({'archive': archive.name, **inspect_archive(archive, max_bytes=args.max_bytes)}))
    except (BackupError, OSError, ValueError, tarfile.TarError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
