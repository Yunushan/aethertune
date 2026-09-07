"""Safety regressions for the disposable Android TLS fixture, not device evidence."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import prepare_android_sync_fixture as fixture


class AndroidSyncFixtureTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.output = self.root / 'build' / 'fixture'
        self.root_patch = patch.object(fixture, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.calls = []
        self.rooted = False

    def fake_run(self, args, *, data=None, **kwargs):
        self.calls.append((args, data))
        if 'getprop' in args:
            return {'ro.kernel.qemu': b'1', 'ro.boot.qemu.avd_name': b'AetherTune_Acceptance_API35',
                    'ro.build.type': b'userdebug'}[args[-1]]
        if args[-2:] == ['id', '-u']:
            return b'0' if self.rooted else b'2000'
        if args[-1] == 'root':
            self.rooted = True
        if args[-1] == 'unroot':
            self.rooted = False
        if args[0] == 'openssl':
            for option in ('-out', '-keyout'):
                if option in args:
                    Path(args[args.index(option) + 1]).write_bytes(b'synthetic-test-only\n')
            if '-subject_hash_old' in args:
                return b'1234abcd\n'
        if args[-3:-1] == ['exec-out', 'cat']:
            return b'synthetic-test-only\n'
        return b''

    def test_physical_serial_and_personal_avd_never_contact_adb(self) -> None:
        with patch.object(fixture, 'run') as run:
            for serial, avd in [('physical-device', 'AetherTune_Acceptance_API35'),
                                ('emulator-5580', 'Personal_Pixel')]:
                with self.subTest(serial=serial, avd=avd), self.assertRaises(ValueError):
                    fixture.validate_target('adb', serial, avd)
            run.assert_not_called()

    def test_wrong_guest_property_stops_before_root_or_writes(self) -> None:
        with patch.object(fixture, 'run', return_value=b'0') as run:
            with self.assertRaisesRegex(ValueError, 'identity mismatch'):
                fixture.validate_target('adb', 'emulator-5580', 'AetherTune_Acceptance_API35')
            self.assertEqual(run.call_count, 1)
            self.assertIn('getprop', run.call_args.args[0])

    def test_output_cannot_be_build_root_or_outside_workspace_build(self) -> None:
        for path in (self.root / 'outside', self.root / 'build', self.root / 'build/../../outside'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                fixture.validate_output(path)

    def test_preparation_uses_guest_user_store_and_non_pty_stdin(self) -> None:
        with patch.object(fixture, 'run', side_effect=self.fake_run):
            fixture.prepare('adb', 'openssl', 'emulator-5580', 'AetherTune_Acceptance_API35', self.output)
        transfers = [(args, data) for args, data in self.calls if data is not None]
        self.assertEqual(len(transfers), 6)
        for args, _ in transfers:
            self.assertEqual(args[3:7], ['shell', '-T', 'run-as', fixture.PACKAGE])
        pushes = [args for args, _ in self.calls if 'push' in args]
        self.assertEqual(len(pushes), 1)
        self.assertEqual(pushes[0][-1], fixture.GUEST_CA + '/1234abcd.0')
        self.assertNotIn('untrusted-ca.pem', pushes[0])
        self.assertTrue((self.output / 'receipt.json').is_file())

    def write_receipt(self, *, digest=None, path=None) -> None:
        self.output.mkdir(parents=True)
        receipt = {'serial': 'emulator-5580', 'avd': 'AetherTune_Acceptance_API35',
                   'guest_certificate': path or fixture.GUEST_CA + '/1234abcd.0',
                   'certificate_sha256': digest or hashlib.sha256(b'synthetic-test-only\n').hexdigest()}
        (self.output / 'receipt.json').write_text(json.dumps(receipt), encoding='utf-8')

    def test_cleanup_rejects_changed_certificate(self) -> None:
        self.write_receipt(digest='0' * 64)
        with patch.object(fixture, 'run', side_effect=self.fake_run):
            with self.assertRaisesRegex(ValueError, 'differs'):
                fixture.cleanup('adb', 'emulator-5580', 'AetherTune_Acceptance_API35', self.output)
        self.assertFalse(any('rm' in args for args, _ in self.calls))

    def test_cleanup_rejects_a_receipt_path_escape(self) -> None:
        self.write_receipt(path='/data/misc/user/0/cacerts-added/../../personal')
        with patch.object(fixture, 'run', side_effect=self.fake_run):
            with self.assertRaisesRegex(ValueError, 'receipt'):
                fixture.cleanup('adb', 'emulator-5580', 'AetherTune_Acceptance_API35', self.output)
        self.assertFalse(any('root' in args or 'rm' in args for args, _ in self.calls))

    def test_cleanup_compares_binary_bytes_and_removes_only_owned_paths(self) -> None:
        self.write_receipt()
        with patch.object(fixture, 'run', side_effect=self.fake_run):
            fixture.cleanup('adb', 'emulator-5580', 'AetherTune_Acceptance_API35', self.output)
        self.assertIn(['adb', '-s', 'emulator-5580', 'exec-out', 'cat',
                       fixture.GUEST_CA + '/1234abcd.0'], [args for args, _ in self.calls])
        removals = [args for args, _ in self.calls if 'rm' in args]
        self.assertEqual(len(removals), 7)
        self.assertFalse(any('-r' in args or '-rf' in args for args in removals))
        self.assertTrue(any(args[-1] == 'unroot' for args, _ in self.calls))
        self.assertEqual(self.calls[-1][0][-2:], ['id', '-u'])
        self.assertEqual(json.loads((self.output / 'cleanup.json').read_text())['status'], 'passed')

    def test_cleanup_cannot_report_success_if_guest_root_remains_active(self) -> None:
        self.write_receipt()

        def still_root(args, **kwargs):
            result = self.fake_run(args, **kwargs)
            return b'0' if args[-2:] == ['id', '-u'] else result

        with patch.object(fixture, 'run', side_effect=still_root):
            with self.assertRaisesRegex(RuntimeError, 'still active'):
                fixture.cleanup('adb', 'emulator-5580', 'AetherTune_Acceptance_API35', self.output)
        self.assertFalse((self.output / 'cleanup.json').exists())


if __name__ == '__main__':
    unittest.main()
