#!/usr/bin/env python3
"""Require a GitHub-verified annotated tag for production releases."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]


def verify_tag_payloads(
    ref_payload: dict[str, Any],
    tag_payload: dict[str, Any] | None,
    *,
    expected_tag: str,
    expected_sha: str,
) -> None:
    ref_object = ref_payload.get("object")
    if not isinstance(ref_object, dict):
        raise ValueError("GitHub tag ref has no object")
    if ref_object.get("type") != "tag":
        raise ValueError("production releases require an annotated Git tag")
    tag_sha = ref_object.get("sha")
    if not isinstance(tag_sha, str) or not tag_sha:
        raise ValueError("GitHub tag ref has no annotated tag object SHA")
    if not isinstance(tag_payload, dict):
        raise ValueError("GitHub annotated tag object is missing")
    if tag_payload.get("tag") != expected_tag:
        raise ValueError("GitHub tag object name does not match the release tag")
    verification = tag_payload.get("verification")
    if not isinstance(verification, dict) or verification.get("verified") is not True:
        reason = verification.get("reason") if isinstance(verification, dict) else "missing"
        raise ValueError(f"GitHub release tag is not verified: {reason}")
    target = tag_payload.get("object")
    if not isinstance(target, dict) or target.get("type") != "commit":
        raise ValueError("GitHub annotated release tag does not point to a commit")
    if target.get("sha") != expected_sha:
        raise ValueError("GitHub release tag does not point to the workflow commit")


def _get_json(url: str, token: str) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "aethertune-production-tag-audit",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"GitHub tag API returned HTTP {error.code}: {error.reason}") from error
    if not isinstance(payload, dict):
        raise RuntimeError(f"GitHub tag API returned a non-object for {url}")
    return payload


def verify_github_tag(
    repository: str,
    tag: str,
    expected_sha: str,
    token: str,
    api_url: str,
) -> None:
    base = api_url.rstrip("/") + "/repos/" + repository
    encoded_tag = urllib.parse.quote(tag, safe="")
    ref_payload = _get_json(f"{base}/git/ref/tags/{encoded_tag}", token)
    ref_object = ref_payload.get("object")
    if not isinstance(ref_object, dict) or ref_object.get("type") != "tag":
        verify_tag_payloads(
            ref_payload,
            None,
            expected_tag=tag,
            expected_sha=expected_sha,
        )
        return
    tag_payload = _get_json(f"{base}/git/tags/{ref_object['sha']}", token)
    verify_tag_payloads(
        ref_payload,
        tag_payload,
        expected_tag=tag,
        expected_sha=expected_sha,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--tag", default=os.environ.get("GITHUB_REF_NAME"))
    parser.add_argument("--sha", default=os.environ.get("GITHUB_SHA"))
    parser.add_argument(
        "--token", default=os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    )
    parser.add_argument(
        "--api-url", default=os.environ.get("GITHUB_API_URL", "https://api.github.com")
    )
    arguments = parser.parse_args()
    if not arguments.repository:
        parser.error("--repository or GITHUB_REPOSITORY is required")
    if not arguments.tag:
        parser.error("--tag or GITHUB_REF_NAME is required")
    if not arguments.sha:
        parser.error("--sha or GITHUB_SHA is required")
    if not arguments.token:
        parser.error("--token, GITHUB_TOKEN, or GH_TOKEN is required")
    try:
        verify_github_tag(
            arguments.repository,
            arguments.tag,
            arguments.sha,
            arguments.token,
            arguments.api_url,
        )
    except (OSError, RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
    print(f"GitHub verified annotated tag passed: {arguments.tag}")


if __name__ == "__main__":
    main()
