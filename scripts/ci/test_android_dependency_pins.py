#!/usr/bin/env python3
"""Regression checks for Android dependency compatibility overrides."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PUBSPEC = ROOT / "apps" / "mobile" / "pubspec.yaml"


class AndroidDependencyPinsTest(unittest.TestCase):
    def test_pins_pre_jni_path_provider_android(self) -> None:
        pubspec = PUBSPEC.read_text(encoding="utf-8")

        self.assertIn("dependency_overrides:", pubspec)
        self.assertIn("  path_provider_android: 2.2.23", pubspec)


if __name__ == "__main__":
    unittest.main()
