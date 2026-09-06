#!/usr/bin/env python3
"""Safety and failure-contract tests for native client storage acceptance."""

import errno
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import Mock, patch

import client_storage_runtime as runtime


class StorageFixtureTest(unittest.TestCase):
    def test_kill_requires_a_live_process_and_waits_for_its_exit(self):
        probe = object.__new__(runtime.Probe)
        probe.process = Mock()
        probe.process.poll.return_value = None
        probe.process.wait.return_value = -9
        probe.kill()
        probe.process.kill.assert_called_once_with()
        probe.process.wait.assert_called_once_with(timeout=5)
        probe.process.poll.return_value = 0
        with self.assertRaisesRegex(AssertionError, 'already exited'):
            probe.kill()
        self.assertEqual(probe.process.kill.call_count, 1)

    def test_mounting_is_refused_in_host_init_namespace(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / 'never-mounted'
            with patch.object(runtime.sys, 'platform', 'linux'), patch.object(runtime.os, 'geteuid', return_value=0, create=True):
                with patch.object(runtime.os, 'readlink', return_value='mnt:[same]'), patch.object(runtime.subprocess, 'run') as run:
                    with self.assertRaisesRegex(AssertionError, 'host init mount namespace'):
                        runtime.disk_acceptance(Mock(), directory, [], {})
                    run.assert_not_called()
            self.assertFalse(directory.exists())

    def test_unprivileged_or_non_linux_disk_fixture_cannot_mount(self):
        for platform, uid in (('win32', 0), ('linux', 1000)):
            with self.subTest(platform=platform), patch.object(runtime.sys, 'platform', platform):
                with patch.object(runtime.os, 'geteuid', return_value=uid, create=True), patch.object(runtime.subprocess, 'run') as run:
                    with self.assertRaisesRegex(AssertionError, 'requires Linux root'):
                        runtime.disk_acceptance(Mock(), Path('unused'), [], {})
                    run.assert_not_called()

    def test_failed_disk_case_still_closes_workers_and_unmounts_only_its_fixture(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / 'bounded'
            fixture = Mock()
            with patch.object(runtime.sys, 'platform', 'linux'), patch.object(runtime.os, 'geteuid', return_value=0, create=True):
                with patch.object(runtime.os, 'readlink', side_effect=['mnt:[child]', 'mnt:[host]']):
                    with patch.object(runtime.os, 'chown', create=True), patch.object(runtime.os, 'statvfs',
                            return_value=SimpleNamespace(f_blocks=2048, f_frsize=4096), create=True):
                        with patch.object(runtime, 'seed'), patch.object(runtime, 'saved_bytes'), patch.object(runtime,
                                'fill_filesystem', side_effect=OSError('fixture failure')), patch.object(runtime.subprocess, 'run') as run:
                            with self.assertRaisesRegex(OSError, 'fixture failure'):
                                runtime.disk_acceptance(fixture, directory, [], {})
            fixture.open.return_value.close.assert_called_once_with()
            self.assertEqual(run.call_args_list[0].args[0], [
                'mount', '-t', 'tmpfs', '-o', 'size=8m,mode=0700,nosuid,nodev,noexec',
                'aethertune-storage-fixture', str(directory),
            ])
            self.assertEqual(run.call_args_list[-1].args[0], ['umount', str(directory)])
            fixture.open.assert_called_once_with(directory / 'full_before_lock', user=65534)

    def test_fill_requires_actual_enospc_and_zero_free_blocks(self):
        path = Mock()
        stream = path.open.return_value.__enter__ = Mock(return_value=Mock())
        path.open.return_value.__exit__ = Mock(return_value=False)
        stream.return_value.write.side_effect = [65536, OSError(errno.ENOSPC, 'full')]
        with patch.object(runtime.os, 'statvfs', return_value=SimpleNamespace(f_bavail=0), create=True):
            self.assertEqual(runtime.fill_filesystem(path), 65536)
        stream.return_value.write.side_effect = OSError(errno.EACCES, 'denied')
        with self.assertRaisesRegex(AssertionError, 'Expected real ENOSPC'):
            runtime.fill_filesystem(path)

    def test_runtime_failure_retains_evidence_and_cleans_up(self):
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / 'probe'
            executable.write_bytes(b'fixture')
            evidence = Path(temporary) / 'evidence'
            with patch.object(runtime, 'Fixture') as fixture, patch.object(runtime, 'process_acceptance',
                    side_effect=AssertionError('storage failed')):
                fixture.return_value.cleanup.return_value = []
                self.assertEqual(runtime.run(executable, evidence), 1)
                fixture.return_value.cleanup.assert_called_once_with()
            report = json.loads((evidence / 'runtime.json').read_text())
            self.assertEqual(report['result'], 'failed')
            self.assertEqual(report['error'], 'storage failed')
            self.assertEqual(report['cleanup_errors'], [])

    def test_cleanup_failure_cannot_pass_and_existing_evidence_is_not_reused(self):
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / 'probe'
            executable.write_bytes(b'fixture')
            evidence = Path(temporary) / 'evidence'
            with patch.object(runtime, 'Fixture') as fixture, patch.object(runtime, 'process_acceptance'):
                fixture.return_value.cleanup.return_value = ['process still running']
                self.assertEqual(runtime.run(executable, evidence), 1)
            self.assertEqual(json.loads((evidence / 'runtime.json').read_text())['result'], 'failed')
            with self.assertRaises(FileExistsError):
                runtime.run(executable, evidence)


class StorageWorkflowTest(unittest.TestCase):
    def test_ci_and_release_enforce_native_acceptance_in_existing_desktop_jobs(self):
        for name in ('aethertune-ci.yml', 'aethertune-release.yml'):
            with self.subTest(workflow=name):
                workflow = (runtime.ROOT / '.github/workflows' / name).read_text()
                desktop = workflow.split('\n  desktop:\n', 1)[1].split('\n  server:\n', 1)[0]
                gate = desktop.split('      - name: Build native client storage probe\n', 1)[1].split(
                    '      - name: Verify Windows SMTC toolchain', 1)[0]
                for required in ('dart pub get --enforce-lockfile', 'tool/verify_dependencies.dart',
                                 'tool/test_dependency_policy.dart', 'dart build cli',
                                 'client_storage_runtime.py', '--disk-full',
                                 'unshare --mount --propagation private', 'if-no-files-found: error'):
                    self.assertIn(required, gate)
                self.assertNotIn('continue-on-error', gate)
                self.assertIn("if: matrix.target != 'linux'", gate)
                self.assertIn("if: matrix.target == 'linux'", gate)
                self.assertIn('if: ${{ always() }}', gate)


if __name__ == '__main__':
    unittest.main()
