"""Guard the scope/safety of the separately executed native Sandbox fixture."""

from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
GUEST = ROOT / "scripts/ci/windows_sync_sandbox_guest.ps1"
PREPARE = ROOT / "scripts/ci/prepare_windows_sync_sandbox.ps1"
HARNESS = ROOT / "apps/mobile/integration_test/windows_sync_transport_acceptance.dart"
CONTRACTS = ROOT / "apps/mobile/integration_test/support/native_sync_transport_contracts.dart"


class WindowsSyncAcceptancePolicyTest(unittest.TestCase):
    def test_sandbox_has_only_restricted_fixture_mappings(self):
        source = PREPARE.read_text()
        start = source.index("<Configuration>")
        end = source.index("</Configuration>") + len("</Configuration>")
        config = ET.fromstring(source[start:end])
        for setting in ("Networking", "ClipboardRedirection", "AudioInput", "VideoInput"):
            self.assertEqual(config.findtext(setting), "Disable")
        folders = config.findall("MappedFolders/MappedFolder")
        self.assertEqual(len(folders), 2)
        self.assertEqual(folders[0].findtext("SandboxFolder"), r"C:\Input")
        self.assertEqual(folders[0].findtext("ReadOnly"), "true")
        self.assertEqual(folders[1].findtext("SandboxFolder"), r"C:\Evidence")
        self.assertEqual(folders[1].findtext("ReadOnly"), "false")
        self.assertIn("$output.StartsWith($buildRoot", source)
        self.assertIn("Use a new or empty directory", source)

    def test_guest_guard_precedes_import_launch_and_shutdown(self):
        source = GUEST.read_text()
        guard = source.index("throw 'This driver may run only")
        self.assertIn("WDAGUtilityAccount", source[:guard])
        self.assertIn("sync-fixture-v1", source[:guard])
        for action in ("$rootStore.Add", "[Diagnostics.Process]::Start", "shutdown.exe"):
            self.assertLess(guard, source.index(action))
        self.assertIn("::new('Root', 'LocalMachine')", source)
        self.assertNotIn("::new('Root', 'CurrentUser')", source)
        self.assertLess(source.index("'compile-peer'"), source.index("Add-Type"))

    def test_shutdown_requires_live_request_normal_exit_and_peer_close(self):
        source = GUEST.read_text()
        close = source.index("$app.CloseMainWindow()")
        self.assertLess(source.index("$peer.Received.Wait(15000)"), close)
        self.assertLess(source.index("$app.HasExited -or $peer.Disconnected.IsSet"), close)
        self.assertIn("$app.WaitForExit(5000)", source[close:])
        self.assertIn("$peer.Disconnected.Wait(2000)", source[close:])
        self.assertIn("if ($app.ExitCode -ne 0)", source[close:])
        self.assertIn("$phaseResult.forcedKill = $false", source[close:])
        self.assertIn("$phaseResult.forcedKill = $true", source[close:])

    def test_harness_uses_application_and_never_relaxes_its_trust(self):
        source = HARNESS.read_text()
        contracts = CONTRACTS.read_text()
        self.assertIn("await app.main();", source)
        self.assertIn("library_sync_transport.dart", source)
        self.assertIn("runNativeSyncTransportContracts(", source)
        self.assertIn("failure is HandshakeException", contracts)
        self.assertIn("await _diagnoseCertificateFixture(", contracts)
        self.assertIn("rethrow;", contracts)
        self.assertNotIn("verifyCertificates: false", source + contracts)
        self.assertNotIn("badCertificateCallback", source + contracts)
        # The shutdown phase uses actual production deadlines, not shortened
        # harness timeouts that could disconnect before native window close.
        shutdown = source.split("Production deadlines remain unchanged.", 1)[1]
        shutdown = shutdown.split("Unfinished request returned", 1)[0]
        self.assertNotIn("transferTimeout:", shutdown)
        self.assertNotIn("requestTimeout:", shutdown)
        self.assertNotIn("idleTimeout:", shutdown)

    def test_executor_explicitly_preserves_platform_certificate_trust(self):
        source = (ROOT / "apps/mobile/lib/src/data/library_sync_transport.dart").read_text()
        self.assertIn("tlsSettings: const native.TlsSettings(", source)
        self.assertIn("rootCertSource: native.RootCertSource.platform", source)
        self.assertNotIn("verifyCertificates: false", source)
        self.assertNotIn("trustedRootCertificates:", source)

    def test_linux_uses_same_contracts_and_preserves_tool_homes(self):
        source = (ROOT / "apps/mobile/integration_test/linux_sync_transport_acceptance_test.dart").read_text()
        runner = (ROOT / "scripts/ci/run_linux_native_acceptance.sh").read_text()
        self.assertIn("runNativeSyncTransportContracts(", source)
        self.assertIn("await app.main();", source)
        self.assertIn("for phase in seed migrate reopen sync", runner)
        self.assertIn("linux_sync_transport_acceptance_test.dart", runner)
        self.assertIn('export SSL_CERT_FILE="$certificates/trusted-bundle.pem"', runner)
        for name in ("PUB_CACHE", "CARGO_HOME", "RUSTUP_HOME"):
            self.assertLess(runner.index(f"export {name}="), runner.index('export HOME="$fixture"'))


if __name__ == "__main__":
    unittest.main()
