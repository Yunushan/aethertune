#!/usr/bin/env python3
"""Safety and failure-contract tests for native client storage acceptance."""

import errno
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import Mock, patch

import client_storage_runtime as runtime


class StorageFixtureTest(unittest.TestCase):
    def test_staging_preserves_native_assets_and_source_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'private-checkout' / 'bundle'
            executable = source / 'bin' / 'probe'
            library = source / 'lib' / 'libsqlite3.so'
            executable.parent.mkdir(parents=True)
            library.parent.mkdir()
            executable.write_bytes(b'compiled fixture')
            library.write_bytes(b'native asset')
            before = {path: (path.read_bytes(), path.stat().st_mode) for path in (executable, library)}
            staged, hashes = runtime.stage_probe_bundle(executable, root / 'staged')
            self.assertEqual(staged, root / 'staged/bin/probe')
            self.assertEqual(hashes, {'bin/probe': runtime.digest(executable),
                                      'lib/libsqlite3.so': runtime.digest(library)})
            for path, (data, mode) in before.items():
                self.assertEqual(path.read_bytes(), data)
                self.assertEqual(path.stat().st_mode, mode)
                target = root / 'staged' / path.relative_to(source)
                self.assertEqual(target.read_bytes(), data)
                if os.name == 'posix':
                    self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o755 if path == executable else 0o644)
            if os.name == 'posix':
                for directory in (staged.parent, staged.parent.parent, root / 'staged/lib'):
                    self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o755)
            with self.assertRaises(FileExistsError):
                runtime.stage_probe_bundle(executable, root / 'staged')

    def test_staging_rejects_links_and_non_bundle_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / 'bundle/bin/probe'
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b'fixture')
            with patch.object(Path, 'is_symlink', side_effect=lambda: True):
                with self.assertRaisesRegex(AssertionError, 'symbolic link'):
                    runtime.stage_probe_bundle(executable, root / 'staged')
            with self.assertRaisesRegex(AssertionError, 'CLI bundle/bin'):
                runtime.stage_probe_bundle(root / 'probe', root / 'staged')

    @unittest.skipUnless(os.name == 'posix', 'POSIX file types')
    def test_staging_rejects_special_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / 'bundle/bin/probe'
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b'fixture')
            os.mkfifo(executable.parent / 'pipe')
            with self.assertRaisesRegex(AssertionError, 'non-regular file'):
                runtime.stage_probe_bundle(executable, root / 'staged')

    def test_staging_detects_copy_corruption(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / 'bundle/bin/probe'
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b'fixture')
            with patch.object(runtime.shutil, 'copyfile', side_effect=lambda source, target, **kwargs: target.write_bytes(b'bad')):
                with self.assertRaisesRegex(AssertionError, 'changed probe bundle bytes'):
                    runtime.stage_probe_bundle(executable, root / 'staged')

    @unittest.skipUnless(sys.platform == 'linux' and getattr(os, 'geteuid', lambda: -1)() == 0,
                         'Requires Linux root to launch the unprivileged fixture')
    def test_unprivileged_process_uses_staged_bundle_from_private_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            root.chmod(0o755)
            private = root / 'checkout'
            private.mkdir(mode=0o700)
            executable = private / 'bundle/bin/probe'
            executable.parent.mkdir(parents=True)
            shutil.copyfile(Path(sys.executable).resolve(), executable)
            executable.chmod(0o700)
            library = private / 'bundle/lib/marker'
            library.parent.mkdir()
            library.write_text('native fixture asset')
            options = {'user': 65534, 'group': 65534, 'extra_groups': [], 'timeout': 5,
                       'check': True, 'capture_output': True, 'text': True}
            with self.assertRaises(PermissionError):
                subprocess.run([str(executable), '-c', 'pass'], **options)
            staged, _ = runtime.stage_probe_bundle(executable, root / 'staged')
            result = subprocess.run([str(staged), '-c',
                'import os,pathlib,sys; print(os.getuid(), (pathlib.Path(sys.executable).parent.parent / "lib/marker").read_text())'],
                **options)
            self.assertEqual(result.stdout.strip(), '65534 native fixture asset')
            self.assertEqual(stat.S_IMODE(private.stat().st_mode), 0o700)

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
