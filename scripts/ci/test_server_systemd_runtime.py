"""The deployment fixture must retain the production unit's restrictions."""

import unittest

from server_systemd_runtime import DEPLOY, unit_config


class SystemdRuntimeContractTest(unittest.TestCase):
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
