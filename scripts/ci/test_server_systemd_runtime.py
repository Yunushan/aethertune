"""The deployment fixture must retain the production unit's restrictions."""

from pathlib import Path
from types import SimpleNamespace
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from server_systemd_runtime import DEPLOY, publish_evidence, unit_config


class SystemdRuntimeContractTest(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'linux' and getattr(os, 'geteuid', lambda: -1)() == 0,
                         'Requires Linux root to transfer evidence ownership')
    def test_unprivileged_uploader_can_read_private_root_generated_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary)
            parent.chmod(0o755)
            evidence = parent / 'evidence'
            evidence.mkdir(mode=0o700)
            report = evidence / 'systemd-runtime.json'
            report.write_text('{"result":"passed"}')
            report.chmod(0o600)
            publish_evidence(evidence, [report.name], SimpleNamespace(st_uid=65534, st_gid=65534))
            result = subprocess.run([sys.executable, '-c',
                'import pathlib,sys; print(pathlib.Path(sys.argv[1]).read_text())', str(report)],
                user=65534, group=65534, extra_groups=[], check=True, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.stdout.strip(), '{"result":"passed"}')

    def test_private_evidence_is_returned_to_uploader_without_changing_modes(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary) / 'evidence'
            evidence.mkdir(mode=0o700)
            report = evidence / 'systemd-runtime.json'
            report.write_text('{"result":"passed"}')
            report.chmod(0o600)
            before = (evidence.stat().st_mode, report.stat().st_mode)
            with patch('server_systemd_runtime.os.chown', create=True) as chown:
                publish_evidence(evidence, [report.name], SimpleNamespace(st_uid=1001, st_gid=1002))
            self.assertEqual(chown.call_count, 2)
            self.assertEqual(chown.call_args_list[0].args, (report, 1001, 1002))
            self.assertEqual(chown.call_args_list[1].args, (evidence, 1001, 1002))
            self.assertTrue(all(call.kwargs == {'follow_symlinks': False} for call in chown.call_args_list))
            self.assertEqual((evidence.stat().st_mode, report.stat().st_mode), before)
            self.assertEqual(report.read_text(), '{"result":"passed"}')

    def test_evidence_publication_rejects_escape_and_links(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary)
            owner = SimpleNamespace(st_uid=1001, st_gid=1002)
            with patch('server_systemd_runtime.os.chown', create=True) as chown:
                with self.assertRaisesRegex(AssertionError, 'escape'):
                    publish_evidence(evidence, ['../outside'], owner)
                with patch.object(Path, 'is_symlink', return_value=True):
                    with self.assertRaisesRegex(AssertionError, 'real directory'):
                        publish_evidence(evidence, [], owner)
                chown.assert_not_called()

    def test_fixture_overrides_do_not_weaken_server_sandbox(self):
        source = DEPLOY / 'aethertune.service'
        original = unit_config(source, {})
        changed = {'StateDirectory': 'test-fixture', 'EnvironmentFile': '/run/test-fixture/env',
                   'Environment': 'AETHERTUNE_DATA_DIR=/var/lib/test-fixture',
                   'ExecStart': '/run/test-fixture/server', 'ReadWritePaths': '/var/lib/test-fixture'}
        fixture = unit_config(source, {'Service': changed})
        for section in original.sections():
            for key, value in original[section].items():
                if section != 'Service' or key not in changed:
                    self.assertEqual(fixture[section][key], value)
        self.assertEqual(fixture['Service']['DynamicUser'], 'yes')
        self.assertEqual(fixture['Service']['ProtectSystem'], 'strict')

    def test_unknown_override_fails_instead_of_hiding_unit_drift(self):
        with self.assertRaisesRegex(AssertionError, 'Unexpected unit structure'):
            unit_config(DEPLOY / 'aethertune.service', {'Service': {'Unexpected': 'value'}})


if __name__ == '__main__':
    unittest.main()
