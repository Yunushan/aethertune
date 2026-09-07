"""Executable filesystem contracts for the production backup implementation."""

import gzip
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[2] / 'services/server/deploy/aethertune-backup.py'
SPEC = importlib.util.spec_from_file_location('server_backup', HELPER)
backup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup)


class ServerBackupTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='aethertune-backup-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data = self.root / 'data'
        self.data.mkdir()
        self.backups = self.root / 'backups'
        (self.data / 'library.json').write_text('{"revision":7}', encoding='utf-8')

    def sidecar(self, archive):
        checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
        archive.with_name(archive.name + '.sha256').write_text(f'{checksum}  {archive.name}\n', encoding='ascii')

    def archive(self, entries):
        target = self.root / 'legacy.tar.gz'
        with tarfile.open(target, 'w:gz') as bundle:
            for name, kind, content in entries:
                member = tarfile.TarInfo(name)
                member.type = kind
                if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE):
                    member.linkname = content.decode()
                elif kind == tarfile.REGTYPE:
                    member.size = len(content)
                bundle.addfile(member, io.BytesIO(content) if kind == tarfile.REGTYPE else None)
        self.sidecar(target)
        return target

    def test_round_trip_checks_manifest_and_excludes_transient_files(self):
        for name in backup.RUNTIME_FILES | {'unfinished.tmp'}:
            (self.data / name).write_text('transient', encoding='utf-8')
        archive = backup.backup(self.data, self.backups)
        result = backup.restore(archive, self.root / 'restored')
        self.assertEqual(result, {'fileCount': 1, 'byteCount': 14, 'manifestVerified': True})
        self.assertEqual(list((self.root / 'restored').iterdir()), [self.root / 'restored/library.json'])
        self.assertEqual((self.root / 'restored/library.json').read_bytes(), (self.data / 'library.json').read_bytes())

    def test_archive_can_be_relocated(self):
        archive = backup.backup(self.data, self.backups)
        moved = self.root / archive.name
        archive.rename(moved)
        archive.with_name(archive.name + '.sha256').rename(moved.with_name(moved.name + '.sha256'))
        self.assertTrue(backup.inspect_archive(moved)['manifestVerified'])

    def test_legacy_archive_is_explicitly_not_manifest_verified(self):
        archive = self.archive([('./library.json', tarfile.REGTYPE, b'legacy')])
        self.assertFalse(backup.restore(archive, self.root / 'restored')['manifestVerified'])

    def test_no_overwrite_on_rapid_backups_and_retention_preserves_current(self):
        first = backup.backup(self.data, self.backups)
        second = backup.backup(self.data, self.backups)
        self.assertNotEqual(first, second)
        os.utime(first, (0, 0))
        third = backup.backup(self.data, self.backups, retention_days=1)
        self.assertFalse(first.exists())
        self.assertFalse(first.with_name(first.name + '.sha256').exists())
        self.assertTrue(second.exists())
        self.assertTrue(backup.inspect_archive(third)['manifestVerified'])

    def test_missing_and_mismatched_checksum_rejected(self):
        archive = backup.backup(self.data, self.backups)
        sidecar = archive.with_name(archive.name + '.sha256')
        sidecar.unlink()
        with self.assertRaisesRegex(backup.BackupError, 'Missing checksum'):
            backup.inspect_archive(archive)
        sidecar.write_text(f'{"0" * 64}  {archive.name}\n', encoding='ascii')
        with self.assertRaisesRegex(backup.BackupError, 'checksum mismatch'):
            backup.inspect_archive(archive)

    def test_checksum_of_another_file_does_not_validate_archive(self):
        archive = backup.backup(self.data, self.backups)
        archive.with_name(archive.name + '.sha256').write_text(f'{"0" * 64}  another.tar.gz\n', encoding='ascii')
        with self.assertRaisesRegex(backup.BackupError, 'this archive'):
            backup.inspect_archive(archive)

    def test_tampered_archive_preserves_target(self):
        archive = backup.backup(self.data, self.backups)
        with archive.open('ab') as output:
            output.write(b'tampered')
        target = self.root / 'restored'
        target.mkdir()
        with self.assertRaises(backup.BackupError):
            backup.restore(archive, target)
        self.assertEqual(list(target.iterdir()), [])
        self.assertEqual(list(self.root.glob('.restored-restore-*')), [])

    def test_non_empty_target_is_never_replaced(self):
        archive = backup.backup(self.data, self.backups)
        with self.assertRaisesRegex(backup.BackupError, 'empty'):
            backup.restore(archive, self.data)
        self.assertEqual((self.data / 'library.json').read_text(), '{"revision":7}')

    def test_rejects_traversal_and_non_portable_names(self):
        for name in ('../escape', '/escape', 'a/../../escape', 'a\\escape', 'C:/escape',
                     'CON', 'aux.txt', 'LPT1.dat', 'dir./file', 'space /file', 'bad\nname'):
            with self.subTest(name=name):
                archive = self.archive([(name, tarfile.REGTYPE, b'bad')])
                with self.assertRaises(backup.BackupError):
                    backup.restore(archive, self.root / 'restored')
                self.assertFalse((self.root / 'restored').exists())

    def test_rejects_links_and_special_files(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE, tarfile.CHRTYPE):
            with self.subTest(kind=kind):
                archive = self.archive([('link', kind, b'../outside')])
                with self.assertRaisesRegex(backup.BackupError, 'entry type'):
                    backup.inspect_archive(archive)

    def test_rejects_duplicates_case_aliases_and_file_parents(self):
        for names in (('same', 'same'), ('A', 'a'), ('A/one', 'a/two'), ('parent', 'parent/child'), ('parent/child', 'parent')):
            with self.subTest(names=names):
                archive = self.archive([(name, tarfile.REGTYPE, b'x') for name in names])
                with self.assertRaises(backup.BackupError):
                    backup.inspect_archive(archive)

    def test_rejects_runtime_locks(self):
        for name in backup.RUNTIME_FILES:
            archive = self.archive([(name, tarfile.REGTYPE, b'')])
            with self.assertRaisesRegex(backup.BackupError, 'runtime lock'):
                backup.inspect_archive(archive)

    def test_bounds_file_and_manifest_sizes(self):
        archive = self.archive([('large', tarfile.REGTYPE, b'x' * 100)])
        with self.assertRaisesRegex(backup.BackupError, 'size limit'):
            backup.restore(archive, self.root / 'restored', max_bytes=99)
        self.assertFalse((self.root / 'restored').exists())
        old = backup.MAX_MANIFEST_BYTES
        try:
            backup.MAX_MANIFEST_BYTES = 10
            archive = self.archive([(backup.MANIFEST, tarfile.REGTYPE, b' ' * 11)])
            with self.assertRaisesRegex(backup.BackupError, 'manifest'):
                backup.inspect_archive(archive)
        finally:
            backup.MAX_MANIFEST_BYTES = old

    def test_rejects_oversized_pax_metadata_before_reading_payload(self):
        archive = self.root / 'oversized.tar.gz'
        info = tarfile.TarInfo('metadata')
        info.type = tarfile.XHDTYPE
        info.size = backup.MAX_METADATA_BYTES + 1
        with gzip.open(archive, 'wb') as output:
            output.write(info.tobuf(format=tarfile.USTAR_FORMAT))
        self.sidecar(archive)
        with self.assertRaisesRegex(backup.BackupError, 'metadata'):
            backup.inspect_archive(archive)

    def test_manifest_mismatch_does_not_publish_partial_restore(self):
        manifest = json.dumps({'format': 1, 'files': {}}).encode()
        archive = self.archive([('library.json', tarfile.REGTYPE, b'changed'), (backup.MANIFEST, tarfile.REGTYPE, manifest)])
        with self.assertRaisesRegex(backup.BackupError, 'manifest'):
            backup.restore(archive, self.root / 'restored')
        self.assertFalse((self.root / 'restored').exists())
        self.assertEqual(list(self.root.glob('.restored-restore-*')), [])

    def test_oversized_backup_is_not_published(self):
        with self.assertRaises(backup.BackupError):
            backup.backup(self.data, self.backups, max_bytes=1)
        self.assertEqual(list(self.backups.iterdir()), [])

    def test_present_but_invalid_manifest_cannot_downgrade_to_legacy(self):
        for value in (None, True, [], {}, {'format': True, 'files': {}}):
            with self.subTest(value=value):
                archive = self.archive([(backup.MANIFEST, tarfile.REGTYPE, json.dumps(value).encode())])
                with self.assertRaisesRegex(backup.BackupError, 'manifest'):
                    backup.inspect_archive(archive)

    @unittest.skipIf(os.name == 'nt', 'Native symlink creation requires Windows privileges; executed on Linux.')
    def test_source_symlink_is_not_followed(self):
        outside = self.root / 'outside'
        outside.write_text('private', encoding='utf-8')
        (self.data / 'link').symlink_to(outside)
        with self.assertRaises(backup.BackupError):
            backup.backup(self.data, self.backups)
        self.assertEqual(list(self.backups.iterdir()), [])
        self.assertEqual(outside.read_text(), 'private')

    @unittest.skipIf(os.name == 'nt', 'Native symlink creation requires Windows privileges; executed on Linux.')
    def test_archive_and_restore_target_symlinks_are_rejected(self):
        archive = backup.backup(self.data, self.backups)
        linked = self.root / 'linked.tar.gz'
        linked.symlink_to(archive)
        with self.assertRaises(backup.BackupError):
            backup.inspect_archive(linked)
        target = self.root / 'restore-link'
        target.symlink_to(self.data, target_is_directory=True)
        with self.assertRaises(backup.BackupError):
            backup.restore(archive, target)
        self.assertEqual((self.data / 'library.json').read_text(), '{"revision":7}')

    def test_rejects_backups_inside_data(self):
        with self.assertRaisesRegex(backup.BackupError, 'inside'):
            backup.backup(self.data, self.data / 'backups')

    @unittest.skipIf(os.name == 'nt', 'POSIX permission and file-type semantics.')
    def test_new_locks_are_private_even_with_permissive_umask(self):
        import stat
        previous = os.umask(0)
        try:
            lock = self.data / '.private.lock'
            with backup.FileLock(lock):
                self.assertEqual(stat.S_IMODE(lock.stat().st_mode), 0o600)
        finally:
            os.umask(previous)

    @unittest.skipIf(os.name == 'nt', 'POSIX link and special-file semantics.')
    def test_lock_rejects_links_and_special_files_without_modifying_targets(self):
        target = self.root / 'untouched'
        target.write_bytes(b'private')
        for kind in ('symlink', 'hardlink', 'fifo'):
            with self.subTest(kind=kind):
                lock = self.data / kind
                if kind == 'symlink':
                    lock.symlink_to(target)
                elif kind == 'hardlink':
                    os.link(target, lock)
                else:
                    os.mkfifo(lock)
                with self.assertRaises(backup.BackupError):
                    with backup.FileLock(lock):
                        self.fail('Unsafe lock was accepted.')
                self.assertEqual(target.read_bytes(), b'private')

    def test_verification_rejects_orphan_sidecar(self):
        archive = backup.backup(self.data, self.backups)
        archive.unlink()
        result = subprocess.run([sys.executable, str(HELPER), 'verify', str(self.backups)], capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no matching archive', result.stderr)

    def test_cli_round_trip(self):
        for arguments in (['backup', str(self.data), str(self.backups)], ['verify', str(self.backups)]):
            result = subprocess.run([sys.executable, str(HELPER), *arguments], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
        archive = next(self.backups.glob('*.tar.gz'))
        result = subprocess.run([sys.executable, str(HELPER), 'restore', str(archive), str(self.root / 'restored')], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['manifestVerified'])


if __name__ == '__main__':
    unittest.main()
