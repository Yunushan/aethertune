#!/usr/bin/env python3
"""Regression checks for the version-tag release publication contract."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-release.yml"


class ReleaseWorkflowTest(unittest.TestCase):
    def test_release_workflow_uses_bounded_jobs_and_non_persistent_checkout(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("concurrency:", workflow)
        self.assertIn("cancel-in-progress: false", workflow)
        self.assertEqual(workflow.count("timeout-minutes:"), 7)
        self.assertEqual(workflow.count("persist-credentials: false"), 7)

    def test_assembly_checks_out_release_policy_before_running_verifiers(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        assembly = workflow.split("  assemble-release:\n", 1)[1].split(
            "  publish:\n", 1
        )[0]
        publish = workflow.split("  publish:\n", 1)[1]

        self.assertIn("- name: Checkout release policy", assembly)
        self.assertIn("actions: read", assembly)
        self.assertIn("actions: read", publish)
        self.assertIn(
            "uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
            assembly,
        )
        self.assertLess(
            assembly.index(
                "uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
            ),
            assembly.index("scripts/ci/generate_release_manifest.py"),
        )

    def test_builds_a_verified_bundle_and_publishes_version_tags(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        android = workflow.split("  android:\n", 1)[1].split(
            "  desktop:\n", 1
        )[0]

        self.assertIn(
            "uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c",
            workflow,
        )
        self.assertIn("Require production tag to be based on main", workflow)
        self.assertIn("fetch-depth: 0", workflow)
        self.assertIn(
            'git merge-base --is-ancestor "$GITHUB_SHA" origin/main',
            workflow,
        )
        self.assertIn("merge-multiple: true", workflow)
        self.assertIn("- name: Verify downloaded artifact layout", workflow)
        self.assertIn(
            'if [[ ! -f "release/$artifact" ]]; then',
            workflow,
        )
        self.assertIn("scripts/ci/generate_release_manifest.py", workflow)
        self.assertIn("RELEASE_MANIFEST.json", workflow)
        self.assertIn("sha256sum -- * > SHA256SUMS.txt", workflow)
        self.assertIn("sha256sum --check SHA256SUMS.txt", workflow)
        self.assertIn("scripts/ci/verify_release_version.sh", workflow)
        self.assertIn("scripts/ci/verify_release_manifest.py", workflow)
        self.assertIn(
            "actions/attest@508db95dd578ae2727ebd6217d5ba78e4fbda05d",
            workflow,
        )
        self.assertIn("subject-checksums: release/SHA256SUMS.txt", workflow)
        self.assertIn("id-token: write", workflow)
        self.assertIn("attestations: write", workflow)
        self.assertIn("artifact-metadata: write", workflow)
        self.assertIn("actions: read", workflow)
        self.assertLess(
            workflow.index("Attest verified release subjects"),
            workflow.index("Verify release manifest"),
        )
        self.assertIn("scripts/ci/verify_android_release_artifacts.py", workflow)
        self.assertIn("scripts/ci/verify_ios_release_artifact.py", workflow)
        self.assertIn("scripts/ci/verify_macos_release_artifacts.py", workflow)
        self.assertIn("scripts/ci/verify_windows_release_artifacts.py", workflow)
        self.assertIn("aethertune-macos-notarization.json", workflow)
        self.assertIn("aethertune-ios.ipa", workflow)
        self.assertIn("scripts/ci/build_signed_ios_ipa.sh", workflow)
        self.assertIn("Configure Apple production signing", workflow)
        self.assertIn("Build and package signed iOS app", workflow)
        ios_builder = (ROOT / "scripts" / "ci" / "build_signed_ios_ipa.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("codesign --verify --deep --strict --verbose=2", ios_builder)
        self.assertIn("embedded.mobileprovision", ios_builder)
        self.assertIn("security cms -D", ios_builder)
        self.assertIn("Sign and notarize macOS production app", workflow)
        self.assertIn("Notarize macOS production DMG", workflow)
        self.assertIn("AETHERTUNE_IOS_PROVISIONING_PROFILE_BASE64", workflow)
        self.assertIn("AETHERTUNE_IOS_SIGNING_IDENTITY", workflow)
        self.assertIn("AETHERTUNE_APPLE_SIGNING_IDENTITY", workflow)
        self.assertIn("AETHERTUNE_IOS_EXPORT_OPTIONS_PLIST_BASE64", workflow)
        self.assertIn("AETHERTUNE_APPLE_NOTARY_API_KEY_BASE64", workflow)
        self.assertIn("xcrun notarytool submit", workflow)
        self.assertIn("xcrun stapler staple", workflow)
        self.assertLess(
            workflow.index("Sign and notarize macOS production app"),
            workflow.index("Package macOS desktop app"),
        )
        self.assertLess(
            workflow.index("Package macOS desktop app"),
            workflow.index("Notarize macOS production DMG"),
        )
        self.assertIn("Require signed Android production artifacts", workflow)
        self.assertIn("--require-signing", workflow)
        self.assertIn("- name: Stage Android artifacts", android)
        self.assertIn(
            "cp apps/mobile/build/app/outputs/flutter-apk/app-release.apk release/app-release.apk",
            android,
        )
        self.assertIn(
            "cp apps/mobile/build/app/outputs/bundle/release/app-release.aab release/app-release.aab",
            android,
        )
        self.assertIn("path: release/*", android)
        self.assertIn('apksigner_path=', workflow)
        self.assertIn('verify --verbose --print-certs "$apk_path"', workflow)
        self.assertIn("Android Debug", workflow)
        self.assertIn('jarsigner -verify -verbose -certs "$aab_path"', workflow)
        self.assertIn("scripts/ci/package_linux_tarball.sh", workflow)
        self.assertIn("aethertune-linux-x64.tar.gz", workflow)
        self.assertIn("scripts/ci/package_linux_deb.sh", workflow)
        self.assertIn("aethertune-linux-x64.deb", workflow)
        self.assertLess(
            workflow.index("scripts/ci/package_linux_deb.sh"),
            workflow.index("scripts/ci/package_linux_tarball.sh"),
        )
        self.assertIn("scripts/ci/package_windows_zip.ps1", workflow)
        self.assertIn("aethertune-windows-x64.zip", workflow)
        self.assertIn("scripts/ci/package_windows_msix.ps1", workflow)
        self.assertIn("aethertune-windows-x64.msix", workflow)
        self.assertIn("WINDOWS_SIGNING_CERTIFICATE_BASE64", workflow)
        self.assertIn("Sign Windows executable for production", workflow)
        self.assertIn("scripts/ci/sign_windows_executable.ps1", workflow)
        signer_script = (ROOT / "scripts" / "ci" / "sign_windows_executable.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("Get-AuthenticodeSignature", signer_script)
        self.assertIn("Status -ne 'Valid'", signer_script)
        self.assertIn("verify /pa /all", signer_script)
        msix_script = (ROOT / "scripts" / "ci" / "package_windows_msix.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("verify /pa /all", msix_script)
        self.assertIn("X509Certificate2", msix_script)
        self.assertIn("$publisher = $certificate.Subject", msix_script)
        self.assertIn("SecurityElement]::Escape", msix_script)
        self.assertIn('Publisher="$publisherXml"', msix_script)
        self.assertIn("WINDOWS_SIGNING_CERTIFICATE_PATH", workflow)
        self.assertLess(
            workflow.index("Sign Windows executable for production"),
            workflow.index("Package Windows desktop app"),
        )
        self.assertIn("SigningCertificatePath", workflow)
        self.assertIn("scripts/ci/package_macos_zip.sh", workflow)
        self.assertIn("aethertune-macos.zip", workflow)
        self.assertIn("scripts/ci/package_macos_dmg.sh", workflow)
        self.assertIn("aethertune-macos.dmg", workflow)
        self.assertIn("scripts/ci/package_ios_unsigned_zip.sh", workflow)
        self.assertIn("aethertune-ios-unsigned.zip", workflow)
        self.assertIn("scripts/ci/test_server_executable.dart", workflow)
        self.assertIn("scripts/ci/test_server_backup_restore.sh", workflow)
        self.assertIn("name: aethertune-release-bundle", workflow)
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", workflow)
        self.assertIn("vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED == 'true'", workflow)
        self.assertIn("name: production", workflow)
        self.assertIn("'production' || 'candidate'", workflow)
        self.assertIn("  governance:\n", workflow)
        self.assertIn("Verify protected governance for production", workflow)
        self.assertIn("AETHERTUNE_GOVERNANCE_TOKEN", workflow)
        self.assertIn("verify_github_governance.py", workflow)
        self.assertIn("needs: [provenance, osv-scan, governance, android, desktop, server]", workflow)
        self.assertIn("  osv-scan:", workflow)
        osv_lines = workflow.split("  osv-scan:\n", 1)[1].split(
            "  android:\n", 1
        )[0].splitlines()
        self.assertTrue(
            any(line.startswith("    uses: google/osv-scanner-action/") for line in osv_lines)
        )
        self.assertTrue(
            any(
                line.startswith(
                    "    uses: google/osv-scanner-action/.github/workflows/"
                )
                and line.endswith(
                    "@9a498708959aeaef5ef730655706c5a1df1edbc2 # v2.3.8"
                )
                for line in osv_lines
            )
        )
        self.assertIn("--lockfile=./apps/mobile/pubspec.lock", workflow)
        self.assertIn("--lockfile=./services/server/pubspec.lock", workflow)
        self.assertIn("--licenses=", workflow)
        self.assertIn(
            "needs: [provenance, osv-scan, governance, android, desktop, server]",
            workflow,
        )
        self.assertIn("scripts/ci/verify_production_release.py", workflow)
        self.assertIn(
            "- name: Test production release preflight\n"
            "        run: python3 scripts/ci/test_verify_production_release.py",
            workflow,
        )
        self.assertIn("name: Checkout release policy", workflow)
        self.assertIn("contents: write", workflow)
        self.assertIn(
            "refusing to overwrite immutable production assets",
            workflow,
        )
        self.assertIn("- name: Create immutable GitHub release", workflow)
        self.assertNotIn("- name: Create or update GitHub release", workflow)
        self.assertIn('exit 1', workflow)
        self.assertNotIn("gh release upload", workflow)
        self.assertIn('gh release create "$RELEASE_TAG" release/*', workflow)


if __name__ == "__main__":
    unittest.main()
