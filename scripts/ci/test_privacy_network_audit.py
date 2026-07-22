#!/usr/bin/env python3
"""Static privacy guardrails for the AetherTune dependency and CI surface."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-ci.yml"
MANIFESTS = (
    ROOT / "apps" / "mobile" / "pubspec.yaml",
    ROOT / "services" / "server" / "pubspec.yaml",
)
SOURCE_ROOTS = (
    ROOT / "apps" / "mobile" / "lib",
    ROOT / "services" / "server" / "lib",
)
FORBIDDEN_DEPENDENCIES = frozenset(
    {
        "amplitude_flutter",
        "appsflyer_sdk",
        "firebase_analytics",
        "firebase_crashlytics",
        "mixpanel_flutter",
        "posthog_flutter",
        "segment_analytics",
        "sentry",
        "sentry_flutter",
    }
)
FORBIDDEN_IMPORTS = tuple(
    f"package:{dependency}/" for dependency in FORBIDDEN_DEPENDENCIES
)
SECTION_PATTERN = re.compile(r"^(dependencies|dev_dependencies):\s*$")
DEPENDENCY_PATTERN = re.compile(r"^  ([A-Za-z0-9_-]+):")


def manifest_dependencies(path: Path) -> set[str]:
    """Reads top-level Pub dependency names without requiring a YAML package."""

    section: str | None = None
    dependencies: set[str] = set()
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        match = SECTION_PATTERN.match(raw_line)
        if match is not None:
            section = match.group(1)
            continue
        if raw_line and not raw_line.startswith(" "):
            section = None
            continue
        if section is None:
            continue
        dependency = DEPENDENCY_PATTERN.match(raw_line)
        if dependency is not None:
            dependencies.add(dependency.group(1).replace("-", "_"))
    return dependencies


class PrivacyNetworkAuditTest(unittest.TestCase):
    def test_pub_manifests_do_not_add_tracking_sdks(self) -> None:
        dependencies = set().union(
            *(manifest_dependencies(manifest) for manifest in MANIFESTS),
        )
        self.assertFalse(
            dependencies & FORBIDDEN_DEPENDENCIES,
            "Telemetry and remote crash-reporting SDKs require an explicit "
            "privacy policy change, not an incidental dependency addition.",
        )

    def test_application_source_does_not_import_tracking_sdks(self) -> None:
        offenders: list[str] = []
        for source_root in SOURCE_ROOTS:
            for source in source_root.rglob("*.dart"):
                text = source.read_text(encoding="utf-8")
                for forbidden_import in FORBIDDEN_IMPORTS:
                    if forbidden_import in text:
                        offenders.append(
                            f"{source.relative_to(ROOT)} imports {forbidden_import}",
                        )
        self.assertEqual(offenders, [])

    def test_ci_keeps_provider_privacy_contract_in_the_flutter_suite(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn(
            "flutter test test/music_source_provider_test.dart",
            workflow,
        )


if __name__ == "__main__":
    unittest.main()
