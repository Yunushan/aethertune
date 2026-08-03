#!/usr/bin/env python3
"""Regression checks for production Android signing configuration."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONFIGURE = ROOT / "scripts" / "configure_audio_service_platforms.py"
BOOTSTRAP = ROOT / "scripts" / "bootstrap_client.sh"
WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-release.yml"


class AndroidSigningContractTest(unittest.TestCase):
    def test_release_build_uses_workflow_keystore_properties(self) -> None:
        configure = CONFIGURE.read_text(encoding="utf-8")
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
        workflow = WORKFLOW.read_text(encoding="utf-8")

        for property_name in (
            "AETHERTUNE_RELEASE_STORE_FILE",
            "AETHERTUNE_RELEASE_STORE_PASSWORD",
            "AETHERTUNE_RELEASE_KEY_ALIAS",
            "AETHERTUNE_RELEASE_KEY_PASSWORD",
        ):
            self.assertIn(property_name, configure)
            self.assertIn(property_name, workflow)

        self.assertIn("providers.environmentVariable(name)", configure)
        self.assertIn("providers.gradleProperty(name).orElse", configure)
        self.assertIn('create("aethertuneRelease")', configure)
        self.assertIn('signingConfigs.getByName("aethertuneRelease")', configure)
        self.assertIn('applicationId = "dev.aethertune.aethertune"', configure)
        self.assertIn('application.set(f"{ANDROID}label", "AetherTune")', configure)
        self.assertIn("Android release builds must not fall back to debug signing", configure)
        self.assertIn('create("aethertuneRelease")', bootstrap)
        self.assertIn("Android release signing configuration is missing", bootstrap)
        self.assertIn("--require-signing", workflow)


if __name__ == "__main__":
    unittest.main()
