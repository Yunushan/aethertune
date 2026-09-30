#!/usr/bin/env python3
"""Run the immutable OSV scanner binary and require usable, fresh scan evidence."""

from __future__ import annotations

import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Sequence

from verify_osv_scan import verify_osv_scan


# Official google/osv-scanner-action v2.6.0, Linux amd64 manifest. Invoke the
# binary directly: the image's legacy wrapper remaps no-packages exit 128 to 0.
OSV_SCANNER_IMAGE = (
    "ghcr.io/google/osv-scanner-action@"
    "sha256:13cef841c7b8de79248e572de0c278d64eaf0a4006e2973fa690b777be30eee4"
)


def run_osv_scan(
    workspace: Path,
    scan_args: str,
    *,
    docker_command: Sequence[str] = ("docker",),
    output_name: str = "results.json",
) -> None:
    if output_name not in {"results.json", "old-results.json", "new-results.json"}:
        raise ValueError("scanner output must be one of the fixed evidence filenames")
    arguments = shlex.split(scan_args)
    if not arguments:
        raise ValueError("scan arguments must not be empty")
    workspace = workspace.resolve(strict=True)
    if not workspace.is_dir():
        raise ValueError("scanner workspace must be a directory")
    # Remove only this scan's known output and the reporter file before launching.
    # Checkout-seeded or previous results cannot stand in for current evidence.
    results = workspace / output_name
    results.unlink(missing_ok=True)
    (workspace / "results.sarif").unlink(missing_ok=True)
    command = [
        *docker_command, "run", "--rm", "--platform", "linux/amd64",
        "--env", "GOTOOLCHAIN=auto", "--volume", f"{workspace}:/github/workspace",
        "--workdir", "/github/workspace", "--entrypoint", "/root/osv-scanner",
        OSV_SCANNER_IMAGE, *arguments, f"--output={output_name}", "--format=json",
    ]
    completed = subprocess.run(command, check=False)
    # Reject Docker/runtime/API/configuration/no-package errors regardless of
    # whether a crash left a partial but well-formed findings file behind.
    verify_osv_scan(results, completed.returncode)


def main() -> int:
    try:
        run_osv_scan(
            Path(os.environ.get("GITHUB_WORKSPACE", os.getcwd())),
            os.environ.get("OSV_SCAN_ARGS", ""),
            output_name=os.environ.get("OSV_SCAN_OUTPUT", "results.json"),
        )
    except (ValueError, OSError) as error:
        print(f"::error::OSV scan gate failed: {error}", file=sys.stderr)
        return 1
    print("OSV scanner completed with usable evidence; the reporter will enforce finding policy.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
