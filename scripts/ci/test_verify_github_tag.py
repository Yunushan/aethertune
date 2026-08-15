#!/usr/bin/env python3
"""Regression checks for the production tag provenance gate."""

from __future__ import annotations

import unittest

from verify_github_tag import verify_tag_payloads


def valid_ref() -> dict[str, object]:
    return {"object": {"type": "tag", "sha": "tag-object-sha"}}


def valid_tag() -> dict[str, object]:
    return {
        "tag": "v0.1.0",
        "object": {"type": "commit", "sha": "commit-sha"},
        "verification": {"verified": True, "reason": "valid"},
    }


class VerifyGithubTagTest(unittest.TestCase):
    def test_accepts_verified_annotated_tag_pointing_to_workflow_commit(self) -> None:
        verify_tag_payloads(
            valid_ref(),
            valid_tag(),
            expected_tag="v0.1.0",
            expected_sha="commit-sha",
        )

    def test_rejects_lightweight_tag(self) -> None:
        with self.assertRaisesRegex(ValueError, "annotated Git tag"):
            verify_tag_payloads(
                {"object": {"type": "commit", "sha": "commit-sha"}},
                None,
                expected_tag="v0.1.0",
                expected_sha="commit-sha",
            )

    def test_rejects_unverified_tag(self) -> None:
        tag = valid_tag()
        tag["verification"] = {"verified": False, "reason": "unknown_key"}
        with self.assertRaisesRegex(ValueError, "not verified"):
            verify_tag_payloads(
                valid_ref(),
                tag,
                expected_tag="v0.1.0",
                expected_sha="commit-sha",
            )

    def test_rejects_tag_pointing_to_another_commit(self) -> None:
        tag = valid_tag()
        tag["object"] = {"type": "commit", "sha": "another-commit"}
        with self.assertRaisesRegex(ValueError, "workflow commit"):
            verify_tag_payloads(
                valid_ref(),
                tag,
                expected_tag="v0.1.0",
                expected_sha="commit-sha",
            )


if __name__ == "__main__":
    unittest.main()
