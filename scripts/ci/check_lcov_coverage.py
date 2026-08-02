#!/usr/bin/env python3
"""Check line coverage from an LCOV report without counting generated files."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def coverage_percent(path: Path) -> tuple[int, int, float]:
    total = 0
    covered = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("DA:"):
            continue
        _, payload = line.split(":", 1)
        _, hits, *_ = payload.split(",")
        total += 1
        covered += int(hits) > 0
    if total == 0:
        raise ValueError("LCOV report contains no executable lines")
    return total, covered, covered * 100.0 / total


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lcov", required=True, type=Path)
    parser.add_argument("--minimum", required=True, type=float)
    arguments = parser.parse_args()
    if not arguments.lcov.is_file():
        parser.error(f"LCOV report does not exist: {arguments.lcov}")
    try:
        total, covered, percentage = coverage_percent(arguments.lcov)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
    print(
        f"LCOV line coverage: {covered}/{total} ({percentage:.2f}%), "
        f"minimum {arguments.minimum:.2f}%"
    )
    if percentage < arguments.minimum:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
