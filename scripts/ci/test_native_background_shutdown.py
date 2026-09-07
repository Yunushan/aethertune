#!/usr/bin/env python3
"""Compile and execute the exact Kotlin/Swift shutdown gates in the generator.

This is portable state-machine coverage, not an Android/iOS framework or device
test. Missing compilers and mismatched/partial results fail the explicit command.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "native_background_shutdown"
CHECKS = {
    "normal_completion",
    "cancel_before_ready",
    "coalesced_cancellation",
    "timeout_does_not_destroy",
    "timeout_before_ready",
    "negative_reply_can_retry",
    "forced_termination_is_not_acknowledgment",
    "failed_disposal_never_acknowledges",
    "completion_wins_stop_reply_race",
    "stop_reply_wins_completion_race",
    "reentrant_waiter_observes_disposed_engine",
    "synchronous_stop_reply",
    "no_work_reopens_after_termination",
    "complete_after_timeout",
}


def execute(command: list[str], log: Path) -> str:
    result = subprocess.run(command, capture_output=True, text=True, timeout=180)
    output = result.stdout + result.stderr
    log.write_text(output, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log}:\n{output}")
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--language", choices=("kotlin", "swift"), required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--kotlin-compiler-classpath")
    parser.add_argument("--kotlin-runtime-classpath")
    args = parser.parse_args()
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    summary = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "language": args.language,
        "result": "failed",
        "scope": "Exact generated native shutdown gate; not OS scheduling or Flutter engine acceptance",
    }
    try:
        spec = importlib.util.spec_from_file_location(
            "background_platform_config", ROOT / "scripts/configure_audio_service_platforms.py"
        )
        if spec is None or spec.loader is None:
            raise RuntimeError("Cannot load platform generator")
        generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generator)
        if args.language == "kotlin":
            source = generator._OFFLINE_CACHE_SHUTDOWN_KOTLIN
            if not generator._OFFLINE_CACHE_JOB_KOTLIN.endswith(source):
                raise RuntimeError("Kotlin probe differs from generated job helper")
            gate = evidence / "OfflineCacheShutdownGate.kt"
            fixture = evidence / "ShutdownProbe.kt"
            gate.write_text(source, encoding="utf-8")
            shutil.copyfile(FIXTURES / fixture.name, fixture)
            artifact = evidence / "shutdown.jar"
            if args.kotlin_compiler_classpath:
                if not args.kotlin_runtime_classpath:
                    raise RuntimeError("Embedded compiler requires an explicit runtime classpath")
                compiler = ["java", "-cp", args.kotlin_compiler_classpath, "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler"]
                compile_command = [*compiler, "-no-stdlib", "-no-reflect", "-classpath", args.kotlin_runtime_classpath]
                run_command = ["java", "-cp", os.pathsep.join([str(artifact), args.kotlin_runtime_classpath]), "ShutdownProbeKt"]
            else:
                compiler = ["kotlinc"]
                compile_command = [*compiler, "-include-runtime"]
                run_command = ["java", "-jar", str(artifact)]
            execute([*compiler, "-version"], evidence / "compiler.log")
            execute([*compile_command, "-Werror", str(gate), str(fixture), "-d", str(artifact)], evidence / "compile.log")
        else:
            source = generator._OFFLINE_CACHE_SHUTDOWN_SWIFT
            if not generator._APP_DELEGATE_SWIFT.endswith(source):
                raise RuntimeError("Swift probe differs from generated delegate helper")
            gate = evidence / "OfflineCacheShutdownGate.swift"
            fixture = evidence / "main.swift"
            gate.write_text(source, encoding="utf-8")
            shutil.copyfile(FIXTURES / fixture.name, fixture)
            artifact = evidence / "shutdown"
            execute(["swiftc", "--version"], evidence / "compiler.log")
            execute(["swiftc", "-warnings-as-errors", str(gate), str(fixture), "-o", str(artifact)], evidence / "compile.log")
            run_command = [str(artifact)]
        summary["helper_sha256"] = hashlib.sha256(source.encode()).hexdigest()
        summary["fixture_sha256"] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        output = execute(run_command, evidence / "runtime.log")
        checks = [line.removeprefix("PASS ") for line in output.splitlines() if line.startswith("PASS ")]
        if len(checks) != len(CHECKS) or set(checks) != CHECKS:
            raise RuntimeError(f"Incomplete or duplicate runtime evidence: {checks}")
        summary["checks"] = checks
        summary["result"] = "passed"
        print(f"{args.language}: {len(checks)} native shutdown state-machine checks passed")
        return 0
    except Exception as error:
        summary["error"] = str(error)
        raise
    finally:
        (evidence / "runtime.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
