#!/usr/bin/env python3
"""Regression checks for the mobile coverage gate."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from check_lcov_coverage import coverage_percent


class LcovCoverageTest(unittest.TestCase):
    def test_counts_line_hits(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            report = Path(temporary_directory) / "lcov.info"
            report.write_text(
                "SF:lib/example.dart\nDA:1,2\nDA:2,0\nend_of_record\n",
                encoding="utf-8",
            )
            self.assertEqual(coverage_percent(report), (2, 1, 50.0))

    def test_rejects_a_report_without_executable_lines(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            report = Path(temporary_directory) / "lcov.info"
            report.write_text("SF:lib/example.dart\nend_of_record\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "no executable lines"):
                coverage_percent(report)


if __name__ == "__main__":
    unittest.main()
