#!/usr/bin/env python3
"""Focused regression checks for the deterministic Dart SBOM generator."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "ci" / "generate_dart_sbom.py"


class GenerateDartSbomTest(unittest.TestCase):
    def _graph(self) -> dict[str, object]:
        return {
            "root": "mobile",
            "packages": [
                {
                    "name": "mobile",
                    "version": "1.2.3",
                    "source": "root",
                    "kind": "root",
                },
                {
                    "name": "zeta",
                    "version": "2.0.0",
                    "source": "git",
                    "kind": "transitive",
                },
                {
                    "name": "alpha",
                    "version": "1.0.0",
                    "source": "hosted",
                    "kind": "direct main",
                },
            ],
        }

    def test_generates_stable_sorted_cyclonedx_document(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            graph_path = directory_path / "deps.json"
            output_path = directory_path / "sbom.cdx.json"
            graph_path.write_text(json.dumps(self._graph()), encoding="utf-8")
            command = [
                sys.executable,
                str(SCRIPT),
                "--deps-json",
                str(graph_path),
                "--component-name",
                "aethertune-mobile",
                "--output",
                str(output_path),
            ]
            subprocess.run(command, check=True, capture_output=True, text=True)
            subprocess.run(command + ["--check"], check=True, capture_output=True, text=True)

            sbom = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual("CycloneDX", sbom["bomFormat"])
            self.assertEqual("1.5", sbom["specVersion"])
            self.assertEqual("aethertune-mobile", sbom["metadata"]["component"]["name"])
            self.assertEqual(["alpha", "zeta"], [item["name"] for item in sbom["components"]])
            self.assertEqual("pkg:pub/alpha@1.0.0", sbom["components"][0]["purl"])
            self.assertEqual("pkg:generic/zeta@2.0.0", sbom["components"][1]["purl"])

    def test_rejects_duplicate_dependency_names(self) -> None:
        graph = self._graph()
        packages = graph["packages"]
        assert isinstance(packages, list)
        packages.append(
            {"name": "alpha", "version": "1.0.1", "source": "hosted", "kind": "transitive"}
        )
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            graph_path = directory_path / "deps.json"
            output_path = directory_path / "sbom.cdx.json"
            graph_path.write_text(json.dumps(graph), encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--deps-json",
                    str(graph_path),
                    "--component-name",
                    "aethertune-mobile",
                    "--output",
                    str(output_path),
                ],
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(0, result.returncode)
            self.assertIn("duplicate package", result.stderr)


if __name__ == "__main__":
    unittest.main()
