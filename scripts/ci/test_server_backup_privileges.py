"""Real POSIX ownership checks; execute with sudo on an isolated CI runner."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[2] / 'services/server/deploy/aethertune-backup.py'
SPEC = importlib.util.spec_from_file_location('server_backup_privileges', HELPER)
backup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(backup)


@unittest.skipUnless(os.name == 'posix' and os.geteuid() == 0,
                     'Requires POSIX root to test a distinct unprivileged service identity.')
class ServerBackupPrivilegesTest(unittest.TestCase):
    def setUp(self):
        import pwd
        identity = pwd.getpwnam('nobody')
        self.uid, self.gid = identity.pw_uid, identity.pw_gid
        self.assertNotEqual(self.uid, 0)
        self.temporary = tempfile.TemporaryDirectory(prefix='aethertune-backup-privileges-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.root.chmod(0o711)
        self.helper = self.root / 'backup.py'
        shutil.copyfile(HELPER, self.helper)
        self.helper.chmod(0o644)
        self.data = self.root / 'data'
        self.data.mkdir(mode=0o700)
        os.chown(self.data, self.uid, self.gid)
        self.library = self.data / 'library.json'
        self.library.write_text('{"revision":7}', encoding='utf-8')
        self.library.chmod(0o600)
        os.chown(self.library, self.uid, self.gid)
        self.user_backups = self.root / 'service-backups'
        self.user_backups.mkdir(mode=0o700)
        os.chown(self.user_backups, self.uid, self.gid)

    def command(self, *arguments, unprivileged=False):
        identity = {'user': self.uid, 'group': self.gid, 'extra_groups': []} if unprivileged else {}
        return subprocess.run([sys.executable, str(self.helper), *map(str, arguments)],
                              capture_output=True, text=True, timeout=10, **identity)

    def test_root_backup_before_upgrade_keeps_service_locks_accessible(self):
        legacy = self.data / '.server.lock'
        legacy.touch(mode=0o600)
        os.chown(legacy, self.uid, self.gid)
        inode = legacy.stat().st_ino
        result = self.command('backup', self.data, self.root / 'root-backups')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(legacy.stat().st_ino, inode, 'Never replace an existing lock inode.')
        for name in ('.server.lock', '.backup.intent.lock', '.backup.snapshot.lock'):
            metadata = (self.data / name).stat()
            self.assertEqual((metadata.st_uid, metadata.st_gid), (self.uid, self.gid), name)
            self.assertEqual(stat.S_IMODE(metadata.st_mode), 0o600, name)
        result = self.command('backup', self.data, self.user_backups, unprivileged=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        verified = self.command('verify', self.user_backups, unprivileged=True)
        self.assertEqual(verified.returncode, 0, verified.stderr)
        self.assertTrue(json.loads(verified.stdout)['manifestVerified'])
        self.assertEqual(self.library.read_text(), '{"revision":7}')

    def test_existing_lock_ownership_and_permissions_are_not_rewritten(self):
        lock = self.data / '.backup.intent.lock'
        lock.write_bytes(b'existing')
        lock.chmod(0o640)
        original = lock.stat()
        with backup.FileLock(lock):
            current = lock.stat()
            self.assertEqual((current.st_ino, current.st_uid, current.st_gid, current.st_mode),
                             (original.st_ino, original.st_uid, original.st_gid, original.st_mode))
        self.assertEqual(lock.read_bytes(), b'existing')


if __name__ == '__main__':
    unittest.main()
