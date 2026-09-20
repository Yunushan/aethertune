"""Native recovery observers must not interfere with request admission."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import server_recovery_runtime as runtime


@unittest.skipUnless(sys.platform == 'linux', 'Linux record-lock observation')
class SnapshotObservationTest(unittest.TestCase):
    def test_observes_cross_process_shared_lock_without_acquiring_a_lock(self):
        with tempfile.TemporaryDirectory() as temporary:
            data = Path(temporary)
            lock = data / '.backup.snapshot.lock'
            lock.touch()
            child = subprocess.Popen([sys.executable, '-c', '''
import fcntl, sys
with open(sys.argv[1], 'r+b') as stream:
    fcntl.lockf(stream, fcntl.LOCK_SH | fcntl.LOCK_NB, 1, 0)
    print('locked', flush=True)
    sys.stdin.read()
''', str(lock)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                runtime.read_holder(child)
                with patch.object(runtime.backup, 'FileLock', side_effect=AssertionError('Observer must not take a lock')):
                    for _ in range(100):
                        self.assertTrue(runtime.snapshot_busy(data))
            finally:
                runtime.stop_holder(child)
            with patch.object(runtime.backup, 'FileLock', side_effect=AssertionError('Observer must not take a lock')):
                self.assertFalse(runtime.snapshot_busy(data))
            self.assertEqual(lock.read_bytes(), b'')

    def test_query_errors_are_not_misreported_as_a_held_lock(self):
        import fcntl

        with tempfile.TemporaryDirectory() as temporary:
            data = Path(temporary)
            lock = data / '.backup.snapshot.lock'
            lock.touch()
            with patch.object(fcntl, 'fcntl', side_effect=OSError('query failed')):
                with self.assertRaisesRegex(OSError, 'query failed'):
                    runtime.snapshot_busy(data)
            lock.unlink()
            lock.symlink_to(data / 'missing')
            with self.assertRaises(runtime.backup.BackupError):
                runtime.snapshot_busy(data)


if __name__ == '__main__':
    unittest.main()
