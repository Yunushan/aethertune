#!/usr/bin/env python3
"""Build the locked host transport for Flutter tests (Python 3.11+, Rustup)."""

from __future__ import annotations

import argparse
import os
import subprocess
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "apps/mobile"
CRATE = APP / "packages/rhttp/rust"


def build_commands(app: Path, *, install: bool, test: bool) -> list[list[str]]:
    policy = tomllib.loads((app / "rust-toolchain.toml").read_text(encoding="utf-8"))
    version = policy["toolchain"]["channel"]
    if not isinstance(version, str) or len(version.split(".")) != 3 or not all(
        part.isdecimal() for part in version.split(".")
    ):
        raise ValueError("Native transport requires an exact Rust version")
    commands = []
    if install:
        commands.append(["rustup", "toolchain", "install", version, "--profile", "minimal"])
    arguments = [
        "--manifest-path", str(app / "packages/rhttp/rust/Cargo.toml"),
        "--locked", "--release", "--target-dir", str(app / "rust/target"),
    ]
    commands.append(["rustup", "run", version, "cargo", "build", *arguments])
    if test:
        commands.append(["rustup", "run", version, "cargo", "test", *arguments, "--lib"])
    return commands


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install-toolchain", action="store_true")
    parser.add_argument("--test", action="store_true")
    args = parser.parse_args()
    environment = os.environ.copy()
    environment["RUSTFLAGS"] = "--cfg reqwest_unstable"
    # Encoded flags take precedence over RUSTFLAGS; do not inherit incompatible
    # cross-compilation flags when preparing this host-only test library.
    environment.pop("CARGO_ENCODED_RUSTFLAGS", None)
    environment.pop("CARGO_BUILD_TARGET", None)
    for command in build_commands(APP, install=args.install_toolchain, test=args.test):
        subprocess.run(command, cwd=APP, env=environment, check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
