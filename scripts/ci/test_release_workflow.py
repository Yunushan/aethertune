#!/usr/bin/env python3
"""Regression checks for the version-tag release publication contract."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

# Run payload/cleanup regressions in the existing hosted release-contract step.
from test_linux_packaged_release_acceptance import PackagedReleaseTest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-release.yml"


class ReleaseWorkflowTest(unittest.TestCase):
    def test_assembly_downloads_only_distribution_artifacts(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        assembly = workflow.split("  assemble-release:\n", 1)[1].split(
            "  publish:\n", 1
        )[0]

        expected = (
            "aethertune-dependency-provenance",
            "aethertune-android",
            "aethertune-linux-x64",
            "aethertune-windows-x64",
            "aethertune-macos",
            "aethertune-server-linux-x64",
            "aethertune-server-windows-x64",
            "aethertune-server-macos",
        )
        self.assertEqual(
            assembly.count("uses: actions/download-artifact@"), len(expected)
        )
        for artifact in expected:
            self.assertIn(f"name: {artifact}\n          path: release", assembly)
        self.assertNotIn("pattern: aethertune-*", assembly)
        self.assertNotIn("merge-multiple: true", assembly)

    def test_release_workflow_uses_bounded_jobs_and_non_persistent_checkout(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("concurrency:", workflow)
        self.assertIn("cancel-in-progress: false", workflow)
        # Additional step deadlines do not replace the nine job deadlines.
        self.assertEqual(workflow.count("\n    timeout-minutes:"), 9)
        self.assertEqual(workflow.count("persist-credentials: false"), 8)

    def test_production_mode_rejects_manual_dispatch_before_release_jobs(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        def job(name: str) -> str:
            return re.split(
                r"(?m)^  [a-z][a-z-]*:$",
                workflow.split(f"  {name}:\n", 1)[1],
                maxsplit=1,
            )[0]

        gate = job("release-mode")
        self.assertIn("vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED == 'true' &&", gate)
        self.assertIn(
            "!(github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v'))",
            gate,
        )
        self.assertIn("exit 1", gate)

        for name in (
            "release-trust",
            "provenance",
            "osv-scan",
            "server",
        ):
            with self.subTest(job=name):
                self.assertIn("needs: [release-mode]", job(name))

        for name in ("android", "desktop", "server"):
            with self.subTest(job=name):
                build = job(name)
                self.assertIn(
                    "vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED != 'true' ||\n"
                    "      (github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v'))",
                    build,
                )
                self.assertNotIn(
                    "github.ref == format('refs/heads/{0}', github.event.repository.default_branch)",
                    build,
                )

    def test_tag_trust_and_governance_finish_before_production_secrets_are_available(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        sections = re.split(r"(?m)^  ([a-z][a-z-]*):$", workflow.split("jobs:\n", 1)[1])
        jobs = dict(zip(sections[1::2], sections[2::2]))

        def dependencies(name: str) -> set[str]:
            match = re.search(r"(?m)^    needs: \[([^\]]+)\]$", jobs[name])
            self.assertIsNotNone(match, name)
            return {item.strip() for item in match[1].split(",")}

        def ancestors(name: str) -> set[str]:
            result = set()
            for dependency in dependencies(name):
                result.add(dependency)
                if dependency != "release-mode":
                    result.update(ancestors(dependency))
            return result

        trust = jobs["release-trust"]
        self.assertEqual(dependencies("release-trust"), {"release-mode"})
        self.assertNotIn("secrets.", trust)
        self.assertNotIn("environment:", trust)
        self.assertIn("name: Checkout trusted release policy", trust)
        self.assertIn(
            "ref: @@{{ github.event.repository.default_branch }}".replace("@@", "$"),
            trust,
        )
        self.assertIn("persist-credentials: false", trust)
        self.assertIn("run: python3 scripts/ci/verify_github_tag.py --require-main", trust)
        self.assertLess(
            trust.index("Checkout trusted release policy"),
            trust.index("scripts/ci/verify_github_tag.py --require-main"),
        )
        self.assertEqual(
            dependencies("governance"), {"release-mode", "release-trust"}
        )
        for name in ("android", "desktop"):
            with self.subTest(signing_job=name):
                self.assertEqual(
                    dependencies(name),
                    {"release-mode", "release-trust", "governance"},
                )
        # Assert the complete dependency path for every job that reads a
        # repository or environment secret, including the publish-time probe.
        for name, job in jobs.items():
            if "secrets." in job:
                with self.subTest(credentialed_job=name):
                    self.assertIn("release-trust", ancestors(name))
        for name in ("release-trust", "governance", "android", "desktop"):
            with self.subTest(fail_closed_job=name):
                job_settings = jobs[name].split("    steps:\n", 1)[0]
                self.assertNotIn("always()", job_settings)
                self.assertNotIn("continue-on-error: true", jobs[name])
                self.assertNotIn("failure()", job_settings)
                self.assertNotIn("cancelled()", job_settings)

    def test_nonpublishing_candidates_do_not_require_production_tag_or_governance(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        trust = workflow.split("  release-trust:\n", 1)[1].split(
            "  provenance:\n", 1
        )[0]
        self.assertNotRegex(trust, r"(?m)^    if:")
        production_step = trust.split(
            "      - name: Verify production tag provenance and main ancestry\n", 1
        )[1].split("      - name:", 1)[0]
        self.assertIn(
            "if: vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED == 'true'",
            production_step,
        )
        candidate_step = trust.split(
            "      - name: Confirm candidate tag bypass is non-publishing\n", 1
        )[1]
        self.assertIn(
            "if: vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED != 'true'",
            candidate_step,
        )
        self.assertNotIn("verify_github_tag", candidate_step)
        self.assertNotIn("secrets.", candidate_step)
        governance = workflow.split("  governance:\n", 1)[1].split(
            "  android:\n", 1
        )[0]
        production_governance = governance.split(
            "      - name: Verify protected governance for production\n", 1
        )[1].split("      - name:", 1)[0]
        self.assertIn(
            "if: vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED == 'true'",
            production_governance,
        )
        windows_packaging = workflow.split(
            "      - name: Package Windows desktop app\n", 1
        )[1].split("      - name:", 1)[0]
        self.assertIn(
            "WINDOWS_SIGNING_CERTIFICATE_PASSWORD: @@{{ "
            "vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED == 'true' && "
            "secrets.AETHERTUNE_WINDOWS_SIGNING_CERTIFICATE_PASSWORD || '' }}".replace("@@", "$"),
            windows_packaging,
        )
        for name in ("android", "desktop"):
            build = workflow.split(f"  {name}:\n", 1)[1]
            self.assertIn(
                "'production' || 'candidate'",
                re.split(r"(?m)^  [a-z][a-z-]*:$", build, maxsplit=1)[0],
            )

    def test_assembly_checks_out_release_policy_before_running_verifiers(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        assembly = workflow.split("  assemble-release:\n", 1)[1].split(
            "  publish:\n", 1
        )[0]
        publish = workflow.split("  publish:\n", 1)[1]

        self.assertIn("- name: Checkout release policy", assembly)
        self.assertIn("Verify production release metadata", assembly)
        self.assertIn("scripts/ci/verify_release_metadata.py", assembly)
        self.assertIn("Verify GitHub production tag provenance", assembly)
        self.assertIn("scripts/ci/verify_github_tag.py", assembly)
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
        publish = workflow.split("  publish:\n", 1)[1]

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
            "actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6",
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
        macos_contract = (ROOT / "scripts" / "ci" / "macos_signing_contract.py").read_text(encoding="utf-8")
        self.assertIn("aethertune-macos-notarization.json", macos_contract)
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
        self.assertIn("python3 scripts/ci/macos_signing_contract.py notarize", workflow)
        macos_contract = (ROOT / "scripts" / "ci" / "macos_signing_contract.py").read_text(encoding="utf-8")
        self.assertIn('["/usr/bin/xcrun", "notarytool", "submit"', macos_contract)
        self.assertIn("xcrun stapler staple", workflow)
        self.assertIn("spctl --assess --type execute", workflow)
        self.assertIn("--context context:primary-signature", workflow)
        dmg_step = workflow.split("      - name: Notarize macOS production DMG\n", 1)[1].split("      - name:", 1)[0]
        self.assertLess(dmg_step.index("macos_signing_contract.py sign-dmg"),
                        dmg_step.index("macos_signing_contract.py notarize"))
        self.assertLess(dmg_step.index("stapler validate"), dmg_step.index("macos_signing_contract.py finalize"))
        for name in ("PROVISIONING_PROFILE_BASE64", "PROVISIONING_PROFILE_SHA256", "TEAM_ID", "BUNDLE_ID"):
            self.assertIn("AETHERTUNE_MACOS_" + name, workflow)
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
        self.assertIn("Reclaim Linux packaging space", workflow)
        self.assertIn("sudo apt-get clean", workflow)
        self.assertIn("apps/mobile/.dart_tool", workflow)
        self.assertIn("! -name bundle", workflow)
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
        self.assertIn("scripts/ci/server_recovery_runtime.py", workflow)
        self.assertIn('name: Test compiled server recovery', workflow)
        self.assertIn('name: aethertune-server-recovery-${{ matrix.label }}', workflow)
        self.assertIn("name: aethertune-release-bundle", workflow)
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", workflow)
        self.assertIn("vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED == 'true'", workflow)
        self.assertIn("name: production", workflow)
        self.assertIn("'production' || 'candidate'", workflow)
        self.assertIn("  governance:\n", workflow)
        self.assertIn("Verify protected governance for production", workflow)
        governance = workflow.split("  governance:\n", 1)[1].split(
            "  android:\n", 1
        )[0]
        self.assertIn(
            "vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED != 'true' ||",
            governance,
        )
        self.assertIn(
            "github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')",
            governance,
        )
        self.assertNotIn(
            "github.ref == format('refs/heads/{0}', github.event.repository.default_branch)",
            governance,
        )
        self.assertNotIn(
            "github.ref == format('refs/heads/{0}', github.event.repository.default_branch)",
            workflow,
        )
        self.assertIn(
            "github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v')",
            workflow,
        )
        self.assertIn("ref: ${{ github.event.repository.default_branch }}", workflow)
        self.assertIn("AETHERTUNE_GOVERNANCE_TOKEN", workflow)
        self.assertIn("verify_github_governance.py", workflow)
        self.assertIn("needs: [provenance, osv-scan, governance, android, desktop, server]", workflow)
        self.assertIn("  osv-scan:", workflow)
        osv_lines = workflow.split("  osv-scan:\n", 1)[1].split(
            "  android:\n", 1
        )[0].splitlines()
        self.assertTrue(
            any(
                line == "    uses: ./.github/workflows/osv-scan-reusable.yml"
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
        self.assertIn("Verify production release metadata", workflow)
        self.assertIn("metadata_args+=(--tag \"$GITHUB_REF_NAME\")", workflow)
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", workflow)
        self.assertIn("GITHUB_TOKEN: ${{ github.token }}", workflow)
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
        self.assertIn("- name: Probe production before publication", publish)
        self.assertIn("AETHERTUNE_PRODUCTION_BASE_URL is required before publication", publish)
        self.assertIn("AETHERTUNE_OPS_PROBE_TOKEN is required before publication", publish)
        self.assertIn(
            "bash services/server/deploy/aethertune-ops-probe.sh \"$AETHERTUNE_PRODUCTION_BASE_URL\"",
            publish,
        )
        self.assertLess(
            publish.index("Probe production before publication"),
            publish.index("Create immutable GitHub release"),
        )


class SystemdReleaseGateTest(unittest.TestCase):
    def test_linux_release_binary_must_pass_real_deployment_recovery(self):
        workflow = WORKFLOW.read_text(encoding='utf-8')
        step = workflow.split('      - name: Test Linux deployment identity and recovery\n', 1)[1].split('      - name:', 1)[0]
        self.assertIn("if: matrix.label == 'linux-x64'", step)
        self.assertIn('set -euo pipefail', step)
        self.assertIn('sudo -n python3 scripts/ci/test_server_backup_privileges.py', step)
        self.assertIn('python3 scripts/ci/server_systemd_runtime.py', step)
        self.assertIn('services/server/build/${{ matrix.binary_name }}', step)
        self.assertIn('build/server-recovery-${{ matrix.label }}/systemd', step)


if __name__ == "__main__":
    unittest.main()
