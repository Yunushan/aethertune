#!/usr/bin/env python3
"""Install/launch/remove the ordinary release package on a fresh hosted Linux runner.

No application build or test entrypoint is used. Screenshot content needs human
review; window survival alone is not onboarding, audio, or accessibility proof.
"""
from __future__ import annotations

import argparse
import ctypes as C
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import selectors
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import wave
import zlib

PACKAGE = "aethertune"
INSTALL = Path("/opt/aethertune")
DESKTOP = Path("/usr/share/applications/aethertune.desktop")
DESKTOP_BYTES = b"""[Desktop Entry]
Type=Application
Name=AetherTune
Comment=Free and open-source music player
Exec=/opt/aethertune/aethertune
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupNotify=true
"""
MEDIA_SHA256 = "46a9550c85b396e7ec9f89ab2fb407a2cb12078623edc9d686728816ea4babe9"
PRODUCT_COMMIT = "0aaaa5c52ceecb050b017abb21775d729a341419"
PRODUCT_REF = "refs/heads/codex/readiness-linux-behavior"
PRODUCT_DEB = "8147e0f5a5f1015a5577929f380c90a31fdef1db8c22bc0c26c5b795520f2cb8"
PRODUCT_TAR = "687aab31a48fed7e0e47824d2fcc2e48b5340d87a8defb9715dcf260255f3671"
PRODUCT_EXE = "3d8ff13301a5c212be9e020a8d7a20899945d8d5e40401c84136a103357061fc"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(stream, algorithm="sha256"):
    value = hashlib.new(algorithm, usedforsecurity=False)
    while chunk := stream.read(1024 * 1024):
        value.update(chunk)
    return value.hexdigest()


def file_hash(path):
    with Path(path).open("rb") as stream:
        return digest(stream)


def safe_name(name):
    path = PurePosixPath(name)
    require(not path.is_absolute() and ".." not in path.parts, f"Unsafe archive path: {name}")
    return str(path)


def safe_link(name, target):
    require(not PurePosixPath(target).is_absolute(), f"Absolute symlink: {name}")
    parts = list(PurePosixPath(name).parent.parts)
    for part in PurePosixPath(target).parts:
        if part == "..":
            require(bool(parts), f"Escaping symlink: {name}")
            parts.pop()
        elif part != ".":
            parts.append(part)


def tree_manifest(root):
    entries = {}
    for path in sorted(root.rglob("*")):
        name = path.relative_to(root).as_posix()
        info = path.lstat()
        entry = {"mode": stat.S_IMODE(info.st_mode)}
        if path.is_symlink():
            target = os.readlink(path)
            safe_link(name, target)
            entry.update(kind="symlink", target=target)
        elif path.is_dir():
            entry.update(kind="directory")
        else:
            require(path.is_file(), f"Unsupported bundle entry: {name}")
            entry.update(kind="file", size=info.st_size, sha256=file_hash(path))
        entries[name] = entry
    return entries


def package_payload(bundle):
    expected = {f"opt/aethertune/{name}": entry for name, entry in bundle.items()}
    for name in ("opt", "opt/aethertune", "usr", "usr/share", "usr/share/applications"):
        expected[name] = {"kind": "directory", "mode": 0o755}
    expected["usr/share/applications/aethertune.desktop"] = {
        "kind": "file", "mode": 0o644, "size": len(DESKTOP_BYTES),
        "sha256": hashlib.sha256(DESKTOP_BYTES).hexdigest(),
    }
    return expected


def tar_manifest(archive):
    entries, hardlinks = {}, {}
    for member in archive:
        name = safe_name(member.name)
        if name == ".":
            require(member.isdir(), "Archive root must be a directory")
            continue
        require(name not in entries and name not in hardlinks, f"Duplicate archive entry: {name}")
        entry = {"mode": member.mode}
        if member.isdir():
            entry.update(kind="directory")
        elif member.issym():
            safe_link(name, member.linkname)
            entry.update(kind="symlink", target=member.linkname)
        elif member.islnk():
            hardlinks[name] = (safe_name(member.linkname), member.mode)
            continue
        else:
            require(member.isfile(), f"Unsupported archive entry: {name}")
            with archive.extractfile(member) as stream:
                entry.update(kind="file", size=member.size, sha256=digest(stream))
        entries[name] = entry
    while hardlinks:
        resolved = []
        for name, (target, mode) in hardlinks.items():
            if target in entries:
                require(entries[target]["kind"] == "file", f"Invalid hardlink: {name}")
                entries[name] = dict(entries[target], mode=mode)
                resolved.append(name)
        require(bool(resolved), "Unresolved or cyclic archive hardlinks")
        for name in resolved:
            del hardlinks[name]
    return entries


def deb_members(path):
    """Read the exact uncompressed ar layout produced by package_linux_deb.sh."""
    members = {}
    with path.open("rb") as stream:
        require(stream.read(8) == b"!<arch>\n", "Invalid Debian ar header")
        while header := stream.read(60):
            require(len(header) == 60 and header[58:] == b"`\n", "Invalid ar member header")
            name = header[:16].decode("ascii").strip().removesuffix("/")
            size = int(header[48:58].strip())
            require(size >= 0 and name not in members, "Invalid or duplicate ar member")
            offset = stream.tell()
            require(offset + size <= path.stat().st_size, "Truncated ar member")
            members[name] = (offset, size)
            stream.seek(size + size % 2, os.SEEK_CUR)
    require(list(members) == ["debian-binary", "control.tar", "data.tar"], "Unexpected Debian package members")
    return members


class MemberReader:
    """Keep tar parsing inside its authenticated ar member, including read-ahead."""
    def __init__(self, stream, size):
        self.stream, self.remaining = stream, size

    def read(self, size=-1):
        size = self.remaining if size < 0 else min(size, self.remaining)
        value = self.stream.read(size)
        self.remaining -= len(value)
        return value


def verify_archives(bundle, deb, tarball, version):
    require(bundle.get("aethertune", {}).get("kind") == "file", "Bundle executable absent")
    require(bundle["aethertune"]["mode"] & 0o111, "Bundle executable lacks execute mode")
    require("data/flutter_assets/AssetManifest.bin" in bundle, "Flutter assets absent")
    with tarfile.open(tarball, "r:gz") as archive:
        require(tar_manifest(archive) == bundle, "Tarball payload differs from release bundle")
    members = deb_members(deb)
    with deb.open("rb") as stream:
        stream.seek(members["debian-binary"][0])
        require(stream.read(members["debian-binary"][1]) == b"2.0\n", "Invalid Debian format version")
        stream.seek(members["control.tar"][0])
        with tarfile.open(fileobj=MemberReader(stream, members["control.tar"][1]), mode="r|") as archive:
            control = None
            for member in archive:
                name = safe_name(member.name)
                if name == "." and member.isdir():
                    continue
                # No maintainer scripts/triggers are permitted to mutate the host.
                require(name == "control" and member.isfile() and control is None and member.size < 65536,
                        "Unexpected Debian control member (including install hooks)")
                control = archive.extractfile(member).read().decode("utf-8")
            expected_control = f"""Package: aethertune
Version: {version}
Section: sound
Priority: optional
Architecture: amd64
Maintainer: AetherTune Contributors
Description: Free and open-source local-first music player
 AetherTune is a privacy-respecting music player with local files and legal providers.
"""
            require(control == expected_control, "Debian control metadata differs from expected release")
        stream.seek(members["data.tar"][0])
        with tarfile.open(fileobj=MemberReader(stream, members["data.tar"][1]), mode="r|") as archive:
            payload = tar_manifest(archive)
    expected = package_payload(bundle)
    require(payload == expected, "Debian payload/desktop entry differs from release bundle")
    return payload


def run(command, *, env=None, check=True, timeout=30):
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=timeout)
    if check:
        require(result.returncode == 0, f"Command failed ({result.returncode}): {command}\n{result.stdout}\n{result.stderr}")
    return result


def package_record():
    result = run(["dpkg-query", "-W", "-f=${Package}\t${Version}\t${Status}", PACKAGE], check=False)
    if result.returncode == 1 and not result.stdout:
        return None
    require(result.returncode == 0, "Could not establish existing package state")
    return result.stdout


def assert_fresh(record, install=INSTALL, desktop=DESKTOP):
    require(record is None and not install.exists() and not install.is_symlink()
            and not desktop.exists() and not desktop.is_symlink(),
            "Refusing an existing package, installation, or desktop entry")


def validate_purge_inventory(expected, present, package_files, info_entries, *, partial):
    """Name/version never authorize privileged cleanup of foreign package contents."""
    allowed_files = {"/", *('/' + name for name in expected)}
    package_files = {str(PurePosixPath(path)) for path in package_files}
    require(package_files <= allowed_files, "Refused purge: foreign dpkg-owned path")
    # dpkg generates md5sums during unpack when the archive omits it. It cannot
    # execute code; its contents are checked against the original bundle below.
    require("aethertune.list" in info_entries and set(info_entries) <= {"aethertune.list", "aethertune.md5sums"},
            "Refused purge: unexpected control metadata/hooks")
    require(all(name in expected and entry == expected[name] for name, entry in present.items()),
            "Refused purge: foreign or changed installed payload")
    owned_names = {name for name in expected if name == "opt/aethertune" or name.startswith("opt/aethertune/")
                   or name == "usr/share/applications/aethertune.desktop"}
    if not partial:
        require(set(present) == owned_names and set(package_files) == allowed_files,
                "Refused purge: complete installed payload/file list differs")


def verify_purge_ownership(expected, partial, bundle_root):
    present = {}
    if INSTALL.exists() or INSTALL.is_symlink():
        require(INSTALL.is_dir() and not INSTALL.is_symlink(), "Refused purge: unexpected install root")
        present["opt/aethertune"] = {"kind": "directory", "mode": stat.S_IMODE(INSTALL.stat().st_mode)}
        present.update({f"opt/aethertune/{name}": entry for name, entry in tree_manifest(INSTALL).items()})
    if DESKTOP.exists() or DESKTOP.is_symlink():
        require(DESKTOP.is_file() and not DESKTOP.is_symlink(), "Refused purge: unexpected desktop entry type")
        present["usr/share/applications/aethertune.desktop"] = {
            "kind": "file", "mode": stat.S_IMODE(DESKTOP.stat().st_mode),
            "size": DESKTOP.stat().st_size, "sha256": file_hash(DESKTOP)}
    files = run(["dpkg-query", "-L", PACKAGE]).stdout.splitlines()
    # This package has no Multi-Arch field, conffiles, or maintainer hooks.
    info = [path.name for pattern in ("aethertune.*", "aethertune:*.list")
            for path in Path("/var/lib/dpkg/info").glob(pattern)]
    validate_purge_inventory(expected, present, files, info, partial=partial)
    md5_expected = {}
    for name, entry in expected.items():
        if entry["kind"] != "file":
            continue
        if name.startswith("opt/aethertune/"):
            original = bundle_root / name.removeprefix("opt/aethertune/")
            require(file_hash(original) == entry["sha256"], "Refused purge: original bundle changed")
            with original.open("rb") as stream:
                md5_expected[name] = digest(stream, "md5")
        else:
            md5_expected[name] = hashlib.md5(DESKTOP_BYTES, usedforsecurity=False).hexdigest()
    checksums = {}
    if "aethertune.md5sums" in info:
        for line in Path("/var/lib/dpkg/info/aethertune.md5sums").read_text().splitlines():
            checksum, separator, name = line.partition("  ")
            name = safe_name(name)
            require(separator and name not in checksums and md5_expected.get(name) == checksum,
                    "Refused purge: generated checksum metadata differs")
            checksums[name] = checksum
    if not partial:
        require(checksums == md5_expected, "Refused purge: complete checksum metadata differs")
    return {"present_payload": present, "dpkg_files": files, "dpkg_info_entries": info,
            "generated_md5sums": checksums, "partial": partial}


def process_identity(pid):
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return {"pid": pid, "start_ticks": int(fields[19]), "exe": os.readlink(f"/proc/{pid}/exe")}
    except (FileNotFoundError, ProcessLookupError):
        return None


def process_header(pid):
    """Generation and lineage remain readable for a SUID FUSE helper."""
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return {"pid": pid, "parent_pid": int(fields[1]), "start_ticks": int(fields[19])}
    except (FileNotFoundError, ProcessLookupError):
        return None


def generation_alive(record):
    current = process_header(record["pid"])
    # A helper can reparent to PID 1 when the document daemon exits. PPID
    # change never proves absence, and never authorizes sending a signal.
    return current is not None and current["start_ticks"] == record["start_ticks"]


def installed_processes():
    found = []
    for process in Path("/proc").iterdir():
        if not process.name.isdecimal():
            continue
        try:
            executable = os.readlink(process / "exe")
            if executable.startswith(str(INSTALL) + "/"):
                found.append({"pid": int(process.name), "exe": executable})
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return found


class OwnedProcess:
    def __init__(self, command, env, log, **options):
        self.command = command
        self.started_utc = datetime.now(timezone.utc).isoformat()
        self.handle = subprocess.Popen(command, env=env, stdout=options.pop("stdout", log), stderr=log, **options)
        self.identity = process_identity(self.handle.pid)
        require(self.identity is not None, f"Process exited before ownership capture: {command}")

    def stop(self, identity_reader=process_identity):
        if self.handle.poll() is not None:
            return "already-exited"
        require(identity_reader(self.handle.pid) == self.identity, "Refused process cleanup: PID identity changed")
        self.handle.terminate()
        try:
            self.handle.wait(timeout=5)
            return "terminated"
        except subprocess.TimeoutExpired:
            require(identity_reader(self.handle.pid) == self.identity, "Refused force cleanup: PID identity changed")
            self.handle.kill()
            self.handle.wait(timeout=5)
            return "killed"


def failure_exit_diagnostics(app):
    """Read metadata for the owned process only; never enable or export core dumps."""
    result = {"core_payload_collected": False}
    if sys.platform != "linux":
        return dict(result, status="unavailable outside Linux")
    try:
        import resource
        result["core_size_limit"] = list(resource.getrlimit(resource.RLIMIT_CORE))
        result["kernel_core_pattern"] = Path("/proc/sys/kernel/core_pattern").read_text()[:1024].strip()
    except (OSError, ImportError) as error:
        result["core_policy_metadata_error"] = str(error)
    if not shutil.which("coredumpctl"):
        return dict(result, coredumpctl="not installed; core absence not inferred")
    command = ["coredumpctl", "--no-pager", "--since", app.started_utc,
               "--until", datetime.now(timezone.utc).isoformat(), "info", str(app.handle.pid)]
    try:
        captured = run(command, check=False, timeout=5)
        result["coredumpctl"] = {"command": command, "exit_code": captured.returncode,
                                 "stdout": captured.stdout[:8192], "stderr": captured.stderr[:2048],
                                 "scope": "owned PID and launch/exit time interval; metadata only"}
    except (OSError, subprocess.TimeoutExpired) as error:
        result["coredumpctl"] = {"command": command, "error": str(error)}
    return result


def wait_for_ordinary_exit(app, report, evidence, diagnostics=failure_exit_diagnostics, phase=None):
    outcome = {"identity": app.identity, "started_utc": app.started_utc,
               "wm_delete_sent": True, "wait_timeout_seconds": 15}
    name = f"application-exit-{phase}.json" if phase else "application-exit.json"
    if phase:
        report.setdefault("application_exits", {})[phase] = outcome
    else:
        report["application_exit"] = outcome
    try:
        code = app.handle.wait(timeout=15)
    except subprocess.TimeoutExpired:
        outcome.update(returncode=None, timed_out=True)
        write_json(evidence / name, outcome)
        raise RuntimeError("Ordinary app did not exit within 15 seconds after WM_DELETE_WINDOW")
    outcome.update(returncode=code, timed_out=False)
    if code < 0:
        outcome["signal_number"] = -code
        try:
            outcome["signal_name"] = signal.Signals(-code).name
        except ValueError:
            outcome["signal_name"] = "unknown"
    if code != 0:
        outcome["failure_diagnostics"] = diagnostics(app)
    # Persist before asserting, so the real native result survives cleanup.
    write_json(evidence / name, outcome)
    require(code == 0, f"Ordinary app did not exit successfully after WM_DELETE_WINDOW: returncode={code}, signal={outcome.get('signal_name')}")


def read_pipe_line(pipe, timeout=10):
    # Read unbuffered bytes; buffered readline can hide the daemon's second line.
    deadline, result = time.monotonic() + timeout, bytearray()
    with selectors.DefaultSelector() as selector:
        selector.register(pipe, selectors.EVENT_READ)
        while time.monotonic() < deadline:
            require(selector.select(max(0, deadline - time.monotonic())), "Private service startup timed out")
            value = os.read(pipe.fileno(), 1)
            require(value, "Private service exited during startup")
            if value == b"\n":
                return result.decode()
            result.extend(value)
    raise RuntimeError("Private service startup timed out")


def private_environment(fixture, original):
    env = original.copy()
    for key in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "DBUS_SYSTEM_BUS_ADDRESS", "PULSE_SERVER", "PULSE_SINK", "AT_SPI_BUS_ADDRESS", "NO_AT_BRIDGE", "GTK_MODULES", "GNOME_KEYRING_CONTROL", "GNOME_KEYRING_PID", "SSH_AUTH_SOCK"):
        env.pop(key, None)
    env.update(HOME=str(fixture), XDG_CONFIG_HOME=str(fixture / "config"),
               XDG_DATA_HOME=str(fixture / "data"), XDG_CACHE_HOME=str(fixture / "cache"),
               XDG_RUNTIME_DIR=str(fixture / "runtime"), LIBGL_ALWAYS_SOFTWARE="1",
               GDK_BACKEND="x11", LANG="C.UTF-8", LC_ALL="C.UTF-8")
    return env


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def behavior_provenance(path, args, hashes, bundle, environ=os.environ):
    """Bind original product bytes separately from the current harness checkout."""
    require(path is not None and path.is_file() and not path.is_symlink(), "Behavior mode requires verified product provenance")
    require(path.stat().st_size <= 1024 * 1024, "Product provenance is oversized")
    receipt = json.loads(path.read_text(encoding="utf-8"))
    require(receipt.get("schemaVersion") == 1 and receipt.get("status") == "verified-input", "Product provenance is not verified input")
    product, executor = receipt.get("product", {}), receipt.get("executor", {})
    expected = {"repository": "Yunushan/aethertune", "sourceCommit": PRODUCT_COMMIT,
                "sourceRef": PRODUCT_REF, "runId": 37136816470, "runAttempt": 1, "version": "0.1.0"}
    require(all(product.get(k) == v for k, v in expected.items()), "Original product identity differs")
    require(args.version == product["version"], "Original product version differs")
    artifact = product.get("artifact", {})
    require(artifact.get("id") == 11279990421 and artifact.get("name") == "aethertune-release-bundle" and
            artifact.get("outerSha256") == "8359e6c5f62a6afcb13931fb4c8f20fcdc35f9d6c249f228cb4f3b59b1b98065", "Original artifact identity differs")
    linux = product.get("linux", {})
    require(linux.get("debSha256") == hashes["deb"] == PRODUCT_DEB and
            linux.get("tarballSha256") == hashes["tarball"] == PRODUCT_TAR and
            linux.get("executableSha256") == bundle["aethertune"]["sha256"] == PRODUCT_EXE and
            linux.get("bundleEntries") == len(bundle) == 43, "Original Linux product hashes differ")
    certificate = product.get("certificate", {})
    require(certificate.get("subjectAlternativeName") ==
            f"https://github.com/Yunushan/aethertune/.github/workflows/aethertune-release.yml@{PRODUCT_REF}" and
            certificate.get("issuer") == "https://token.actions.githubusercontent.com" and
            certificate.get("buildSignerDigest") == PRODUCT_COMMIT and
            certificate.get("sourceRepositoryDigest") == PRODUCT_COMMIT and
            certificate.get("sourceRepositoryRef") == PRODUCT_REF and
            certificate.get("runnerEnvironment") == "github-hosted" and
            certificate.get("runInvocationURI") == "https://github.com/Yunushan/aethertune/actions/runs/37136816470/attempts/1",
            "Original attestation certificate identity differs")
    require(executor.get("repository") == environ.get("GITHUB_REPOSITORY") and
            executor.get("triggerSha") == environ.get("GITHUB_SHA") and
            executor.get("ref") == environ.get("GITHUB_REF") and
            str(executor.get("runId")) == environ.get("GITHUB_RUN_ID") and
            str(executor.get("runAttempt")) == environ.get("GITHUB_RUN_ATTEMPT"), "Harness executor identity differs")
    checkout = Path(__file__).resolve().parents[2]
    require(executor.get("sourceCommit") == run(["git", "-C", str(checkout), "rev-parse", "HEAD"]).stdout.strip(), "Harness checkout differs")
    drivers = executor.get("driverHashes", {})
    required = {"scripts/ci/linux_packaged_release_acceptance.py", "scripts/ci/linux_release_ui_acceptance.py",
                "scripts/ci/prepare_linux_release_behavior.py", ".github/workflows/linux-release-behavior.yml"}
    require(required.issubset(drivers), "Harness driver bindings are incomplete")
    for name, sha in drivers.items():
        require(isinstance(name, str) and safe_name(name) == name and isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{64}", sha), "Invalid harness driver binding")
        target = checkout / name
        require(target.resolve().is_relative_to(checkout) and target.is_file() and file_hash(target) == sha, "Harness driver hash differs")
    paths = receipt.get("paths", {})
    require(all(paths.get(k) == str(getattr(args, k).resolve()) for k in ("bundle", "deb", "tarball")), "Product input paths differ")
    return {"path": str(path.resolve()), "sha256": file_hash(path), "product": product, "executor": executor}


def package_executable(package, basename):
    """Resolve one real executable from installed package metadata, not PATH guesses."""
    paths = run(["dpkg-query", "-L", package]).stdout.splitlines()
    found = [Path(p) for p in paths if Path(p).name == basename and Path(p).is_absolute()
             and Path(p).is_file() and os.access(p, os.X_OK)]
    require(len(found) == 1, f"Expected one installed {package} executable: {basename}")
    return str(found[0].resolve())


class PrivateBus:
    def __init__(self, address):
        # Lazy import: default onboarding gate retains its original prerequisites.
        from gi.repository import Gio, GLib
        self.GLib, self.Gio = GLib, Gio
        self.connection = Gio.DBusConnection.new_for_address_sync(address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)

    def call(self, destination, path, interface, method, signature=None, values=None):
        parameter = self.GLib.Variant(signature, values) if signature else None
        return self.connection.call_sync(destination, path, interface, method, parameter, None, 0, 5000, None).unpack()

    def pid(self, name):
        return self.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                         "GetConnectionUnixProcessID", "(s)", (name,))[0]

    def wait_owner(self, name, process, timeout=15):
        deadline, last = time.monotonic() + timeout, None
        while time.monotonic() < deadline:
            require(process.handle.poll() is None and process_identity(process.handle.pid) == process.identity,
                    f"Owned service exited or changed identity: {name}")
            try:
                actual = self.pid(name)
            except self.GLib.Error as error:
                # GLib.Error is also a RuntimeError. Classify the real remote
                # error through Gio; a missing name is the only startup retry.
                remote = self.Gio.DBusError.get_remote_error(error) if self.Gio.DBusError.is_remote_error(error) else None
                if remote != "org.freedesktop.DBus.Error.NameHasNoOwner":
                    raise
                last = remote
                time.sleep(min(0.2, max(0, deadline - time.monotonic())))
                continue
            require(actual == process.handle.pid, f"Private bus owner differs: {name}")
            return {"name": name, "identity": process.identity}
        raise RuntimeError(f"Owned service did not acquire {name}: {last}")

    def close(self):
        self.connection.close_sync(None)


def make_media(fixture):
    media = fixture / "documents/aethertune-linux-behavior-180s.wav"
    with wave.open(str(media), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(22050)
        output.writeframes(b"\0\0" * (180 * 22050))
    require(media.stat().st_size == 7938044 and file_hash(media) == MEDIA_SHA256, "Owned WAV fixture differs")
    return media


def decode_snapshot(raw):
    document = json.loads(raw)
    require(isinstance(document, dict) and document.get("format") == 1 and
            isinstance(document.get("generation"), str) and isinstance(document.get("payload"), str), "Invalid native snapshot envelope")
    payload = document["payload"]
    require(hashlib.sha256(payload.encode("utf-8")).hexdigest() == document.get("checksum"), "Native snapshot checksum differs")
    values = json.loads(payload)
    require(isinstance(values, dict), "Invalid native snapshot values")
    return values


def fixture_track(track, fixture):
    require(isinstance(track, dict) and isinstance(track.get("id"), str) and len(track["id"]) <= 1024 and
            isinstance(track.get("localPath"), str), "Imported fixture track is absent")
    path = Path(track["localPath"])
    require(path.is_absolute() and path.resolve().is_relative_to(fixture.resolve()) and path.is_file() and
            path.stat().st_size == 7938044 and file_hash(path) == MEDIA_SHA256, "Stored track does not reference the owned WAV")
    return track["id"]


def snapshot_predicates(library, player, fixture):
    """Return only known-fixture predicates; never export unrelated stored values."""
    tracks = json.loads(library.get("aethertune.tracks.v1", "null"))
    require(isinstance(tracks, list) and len(tracks) == 1, "Expected exactly one UI-imported fixture track")
    track_id = fixture_track(tracks[0], fixture)
    require(library.get("aethertune.onboarding_completed.v1") is True and
            library.get("aethertune.desktop_density_preference.v1") == "compact", "Native onboarding/density state differs")
    queue = json.loads(player.get("aethertune.player_queue.v1", "null"))
    require(isinstance(queue, dict) and isinstance(queue.get("tracks"), list) and len(queue["tracks"]) == 1,
            "Native queue does not contain exactly the imported fixture")
    require(fixture_track(queue["tracks"][0], fixture) == track_id and queue.get("currentTrackId") == track_id and
            queue.get("currentIndex", 0) == 0, "Native current track and UI-imported library differ")
    return {"onboarding_completed": True, "density": "compact", "imported_track_count": 1,
            "queue_track_count": 1, "current_track_matches_import": True,
            "fixture_track_id_sha256": hashlib.sha256(track_id.encode()).hexdigest(),
            # Exact mapping in the original product's vendored MPRIS adapter.
            "fixture_mpris_track_id_sha256": hashlib.sha256(
                ("/org/mpris/MediaPlayer2/TrackList/" + track_id.encode("utf-16-be").hex()).encode()).hexdigest()}


def state_snapshot(fixture):
    root, candidates, visited = fixture / "data", {}, 0
    for directory, directories, files in os.walk(root, followlinks=False):
        directory = Path(directory)
        visited += 1
        require(visited <= 512 and len(directory.relative_to(root).parts) <= 7, "Owned state discovery exceeded bound")
        require(not directory.is_symlink() and directory.resolve().is_relative_to(root.resolve()), "State directory escaped owned profile")
        require(not any((directory / name).is_symlink() for name in directories), "Symlink directory in owned native state")
        if "library.json" not in files or directory.name not in ("library", "player"):
            continue
        path = directory / "library.json"
        before = path.lstat()
        require(stat.S_ISREG(before.st_mode) and 0 < before.st_size <= 64 * 1024 * 1024, "Invalid native state file")
        raw = path.read_bytes()
        after = path.lstat()
        require((before.st_ino, before.st_size, before.st_mtime_ns) == (after.st_ino, after.st_size, after.st_mtime_ns)
                and hashlib.sha256(raw).hexdigest() == file_hash(path), "Native snapshot changed during observation")
        require(directory.name not in candidates, "Ambiguous native snapshot role")
        candidates[directory.name] = (decode_snapshot(raw), {"path": path.relative_to(fixture).as_posix(),
            "size": len(raw), "sha256": hashlib.sha256(raw).hexdigest(), "stable_during_observation": True})
    require(set(candidates) == {"library", "player"}, "Actual native library/player snapshots are absent")
    return {"observed_utc": datetime.now(timezone.utc).isoformat(),
            "files": {key: value[1] for key, value in candidates.items()},
            "predicates": snapshot_predicates(candidates["library"][0], candidates["player"][0], fixture)}


def wait_state(fixture, evidence, phase):
    deadline, last = time.monotonic() + 15, None
    while time.monotonic() < deadline:
        try:
            result = state_snapshot(fixture)
            write_json(evidence / f"state-{phase}.json", result)
            return result
        except (RuntimeError, OSError, ValueError) as error:
            last = str(error)
            time.sleep(0.2)
    raise RuntimeError(f"Native state predicates did not settle: {last}")


def mounts_under(fixture, mountinfo=None):
    text = Path("/proc/self/mountinfo").read_text() if mountinfo is None else mountinfo
    result = []
    for line in text.splitlines():
        fields = line.split()
        require(len(fields) >= 10 and "-" in fields, "Invalid mount inventory")
        mount = Path(re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), fields[4]))
        if mount == fixture or mount.is_relative_to(fixture):
            split = fields.index("-")
            result.append({"mountpoint": str(mount), "filesystem": fields[split + 1],
                           "mount_id": int(fields[0]), "device": fields[2], "options": fields[5], "source": fields[split + 2]})
    return result


def service_children(processes):
    parents = {p.handle.pid for p in processes}
    result = []
    for path in Path("/proc").iterdir():
        if not path.name.isdecimal():
            continue
        try:
            fields = (path / "stat").read_text().rsplit(")", 1)[1].split()
            if int(fields[1]) in parents:
                result.append({"pid": int(path.name), "parent_pid": int(fields[1]), "start_ticks": int(fields[19])})
        except (OSError, ValueError):
            continue
    return [value for value in result if value is not None]


def validate_fuse_helper(record, parent, binary, fixture, uid, mount):
    require(record.get("parent_identity") == parent and record.get("parent_pid") == parent["pid"] and
            type(record.get("pid")) is int and record["pid"] > 1 and record["pid"] != parent["pid"] and
            type(record.get("start_ticks")) is int and record["start_ticks"] >= parent["start_ticks"], "FUSE helper lineage differs")
    require(record.get("exe") == binary and record.get("executable_sha256") == file_hash(binary), "FUSE helper executable differs")
    uids = record.get("uids")
    require(isinstance(uids, list) and len(uids) == 4 and uids[0] == uid and all(value in (uid, 0) for value in uids), "FUSE helper UID differs")
    argv = record.get("argv")
    mountpoint = str(fixture / "runtime/doc")
    require(isinstance(argv, list) and len(argv) == 5 and argv[0] in ("fusermount3", binary) and argv[1] == "-o" and
            isinstance(argv[2], str) and len(argv[2]) <= 1024 and argv[3:] == ["--", mountpoint], "FUSE helper argv/mount differs")
    options = argv[2].split(",")
    require(len(options) == len(set(options)) and set(options) == {"rw", "nosuid", "nodev", "fsname=portal", "subtype=portal", "auto_unmount"},
            "FUSE helper mount options differ")
    require(mount.get("mountpoint") == mountpoint and mount.get("filesystem") == "fuse.portal" and mount.get("source") == "portal" and
            isinstance(mount.get("mount_id"), int) and mount["mount_id"] > 0 and
            {"rw", "nosuid", "nodev"}.issubset(set(mount.get("options", "").split(","))), "Owned document mount identity differs")
    return record


def read_fuse_helper(pid, parent, binary, fixture, uid, mount, expected_start):
    require(process_identity(parent["pid"]) == parent, "Document parent identity changed before helper inspection")
    before = process_header(pid)
    require(before is not None and before["parent_pid"] == parent["pid"] and before["start_ticks"] == expected_start,
            "Discovered FUSE child identity changed")
    executable = os.readlink(f"/proc/{pid}/exe")
    require(executable == binary, "Unexpected document-portal child executable")
    raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    require(0 < len(raw) <= 8192 and raw.endswith(b"\0"), "Invalid FUSE helper arguments")
    status = Path(f"/proc/{pid}/status").read_text()
    require(len(status) <= 65536, "Oversized FUSE helper status")
    line = next((line for line in status.splitlines() if line.startswith("Uid:")), "")
    record = dict(before, exe=executable, executable_sha256=file_hash(binary), argv=raw[:-1].decode().split("\0"),
                  uids=[int(value) for value in line.split()[1:]], parent_identity=parent)
    require(process_header(pid) == before and process_identity(parent["pid"]) == parent, "FUSE child/parent changed during inspection")
    return validate_fuse_helper(record, parent, binary, fixture, uid, mount)


def document_helper(document, services, fixture, evidence, report):
    deadline = time.monotonic() + 15
    while True:
        require(document.handle.poll() is None and process_identity(document.handle.pid) == document.identity,
                "Document portal changed during FUSE startup")
        children = service_children(services)
        candidates = [value for value in children if value["parent_pid"] == document.handle.pid]
        mounts = mounts_under(fixture)
        require(not any(value["parent_pid"] != document.handle.pid for value in children), "An unrelated explicit-service child appeared")
        if candidates and mounts:
            break
        require(time.monotonic() < deadline, "Document portal helper/mount startup timed out")
        time.sleep(0.2)
    require(len(candidates) == 1, "Expected exactly one documented FUSE auto-unmount child")
    candidate = candidates[0]
    require(len(children) == 1, "An unrelated explicit-service child appeared")
    binary = package_executable("fuse3", "fusermount3")
    require(len(mounts) == 1, "Expected one owned document portal mount")
    mount, uid = mounts[0], os.getuid()
    record = {"candidate": candidate, "expected_parent": document.identity, "expected_executable": binary,
              "mount": mount, "privileged_readonly_inspection": False}
    report["fuse_helper_inspection"] = record
    write_json(evidence / "fuse-helper-inspection.json", record)
    try:
        try:
            observed = read_fuse_helper(candidate["pid"], document.identity, binary, fixture, uid, mount, candidate["start_ticks"])
        except PermissionError:
            # Installed fusermount3 may retain euid 0. Inspect only the already
            # discovered child of our exact parent; never signal this helper.
            command = ["sudo", "-n", "/usr/bin/python3", "-I", str(Path(__file__).resolve()), "--inspect-fuse-child", str(candidate["pid"]),
                "--identity", json.dumps(document.identity), "--helper-start", str(candidate["start_ticks"]),
                "--helper-executable", binary, "--fixture", str(fixture), "--fixture-uid", str(uid), "--mount-identity", json.dumps(mount),
                "--evidence", str(evidence)]
            record["privileged_readonly_inspection"] = True
            result = run(command, check=False, timeout=10)
            record["inspection_exit_code"], record["inspection_stderr"] = result.returncode, result.stderr[:2048]
            require(result.returncode == 0 and len(result.stdout) <= 16384, "Bounded privileged FUSE inspection failed")
            observed = json.loads(result.stdout)
            validate_fuse_helper(observed, document.identity, binary, fixture, uid, mount)
        require(process_header(candidate["pid"]) == candidate and process_identity(document.handle.pid) == document.identity,
                "Document helper changed after inspection")
        report["document_portal"] = document.identity
        report["fuse_helper"] = observed
        report["fuse_helper_mount"] = mount
        record["observed"] = observed
        record["result"] = "BOUND"
        return observed
    except Exception as error:
        record.update(result="FAIL", error=f"{type(error).__name__}: {error}")
        raise
    finally:
        write_json(evidence / "fuse-helper-inspection.json", record)


def unexpected_children(services, report, require_live=True):
    children = service_children(services)
    helper = report.get("fuse_helper")
    if not helper:
        return children
    if require_live:
        require(generation_alive(helper), "Bound FUSE helper exited before document parent shutdown")
    return [value for value in children if (value["pid"], value["start_ticks"]) != (helper["pid"], helper["start_ticks"])]


def audio_output_predicate(sinks, inputs, identity):
    require(isinstance(sinks, list) and len(sinks) == 1 and isinstance(inputs, list) and len(inputs) <= 16,
            "Unexpected private PulseAudio output inventory")
    sink = sinks[0]
    require(sink.get("name") == "aethertune_release_fixture" and sink.get("state") == "RUNNING", "Owned null sink is not running")
    matching = [value for value in inputs if str(value.get("properties", {}).get("application.process.id")) == str(identity["pid"])]
    require(len(matching) == 1, "Exactly one owned app output stream is required")
    output = matching[0]
    require(output.get("sink") == sink.get("index") and output.get("corked") is False and
            output.get("properties", {}).get("application.process.binary") == "aethertune",
            "App output is not actively routed to the private null sink")
    require(type(sink.get("index")) is int and sink["index"] >= 0 and type(output.get("index")) is int and output["index"] >= 0 and
            isinstance(output.get("sample_specification"), str) and
            re.fullmatch(r"(?:s(?:16|24|24-32|32)(?:le|be)|float32(?:le|be)|u8) [1-9][0-9]?ch [1-9][0-9]{3,5}Hz", output["sample_specification"]),
            "Invalid native PCM output fields")
    # The fixture server contains no user streams. Export only native routing
    # metadata for the one process; never copy arbitrary application properties.
    return {"sink_index": sink["index"], "sink_name": sink["name"], "sink_state": sink["state"],
            "input_index": output["index"], "corked": False, "app_identity": identity,
            "sample_specification": str(output.get("sample_specification", ""))[:128],
            "scope": "decoder/output pipeline to null sink; no physical-audio claim"}


def audio_output_inventory(sinks, inputs):
    """Retain a bounded failure inventory without arbitrary Pulse properties."""
    require(isinstance(sinks, list) and len(sinks) <= 16 and isinstance(inputs, list) and len(inputs) <= 16,
            "Oversized private PulseAudio output inventory")
    def index(value):
        return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else None
    def sample(value):
        return value if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_ +.-]{1,128}", value) else None
    return {"observed_utc": datetime.now(timezone.utc).isoformat(),
            "sinks": [{"index": index(value.get("index")), "expected_name": value.get("name") == "aethertune_release_fixture",
                       "state": value.get("state") if value.get("state") in ("RUNNING", "IDLE", "SUSPENDED") else "invalid"}
                      for value in sinks],
            "inputs": [{"index": index(value.get("index")), "sink": index(value.get("sink")),
                        "corked": value.get("corked") if isinstance(value.get("corked"), bool) else None,
                        "process_id": int(str(value.get("properties", {}).get("application.process.id")))
                            if re.fullmatch(r"[0-9]{1,10}", str(value.get("properties", {}).get("application.process.id"))) else None,
                        "expected_binary": value.get("properties", {}).get("application.process.binary") == "aethertune",
                        "sample_specification": sample(value.get("sample_specification"))} for value in inputs]}


def mpris_behavior(bus, app, state, evidence, phase, env):
    destination = f"org.mpris.MediaPlayer2.dev.aethertune.playback.instance{app.handle.pid}"
    binding = bus.wait_owner(destination, app)
    path, interface = "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player"
    def prop(name):
        require(process_identity(app.handle.pid) == app.identity and bus.pid(destination) == app.handle.pid, "MPRIS owner changed")
        return bus.call(destination, path, "org.freedesktop.DBus.Properties", "Get", "(ss)", (interface, name))[0]
    def status(expected):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if prop("PlaybackStatus") == expected:
                return
            time.sleep(0.1)
        raise RuntimeError(f"MPRIS did not become {expected}")
    def metadata():
        data = prop("Metadata")
        require(isinstance(data, dict) and isinstance(data.get("mpris:trackid"), str), "MPRIS metadata is absent")
        require(hashlib.sha256(data["mpris:trackid"].encode()).hexdigest() == state["predicates"]["fixture_mpris_track_id_sha256"],
                "MPRIS does not reference the independently observed imported track")
        require(179_000_000 <= data.get("mpris:length", 0) <= 181_000_000 and prop("CanSeek") is True, "MPRIS fixture duration/seek capability differs")
        return data["mpris:trackid"]
    result = {"result": "FAIL", "phase": phase, "binding": binding, "samples": [],
              "sink": "private PulseAudio null sink; physical audio is excluded"}
    def sample(label):
        value = {"label": label, "observed_utc": datetime.now(timezone.utc).isoformat(),
                 "position_us": prop("Position"), "status": prop("PlaybackStatus")}
        require(isinstance(value["position_us"], int) and value["position_us"] >= 0, "Invalid MPRIS position")
        require(metadata() == track_id, "MPRIS current track changed")
        result["samples"].append(value)
        write_json(evidence / f"mpris-{phase}.json", result)
        return value["position_us"]
    try:
        track_id = metadata()
        result["fixture_track_id_sha256"] = hashlib.sha256(track_id.encode()).hexdigest()
        bus.call(destination, path, interface, "Pause")
        status("Paused")
        require(re.fullmatch(r"/(?:[A-Za-z0-9_]+/?)+", track_id), "MPRIS track ID is not an object path")
        bus.call(destination, path, interface, "SetPosition", "(ox)", (track_id, 30_000_000))
        time.sleep(0.5)
        require(abs(sample("paused-after-seek") - 30_000_000) <= 2_000_000, "Native MPRIS seek did not change the actual position")
        bus.call(destination, path, interface, "Play")
        status("Playing")
        before = sample("playing-start")
        time.sleep(3)
        after = sample("playing-progress")
        require(2_000_000 <= after - before <= 5_000_000, "Playback did not progress at ordinary speed")
        require(process_identity(app.handle.pid) == app.identity, "App identity changed before output observation")
        sinks = json.loads(run(["pactl", "--format=json", "list", "sinks"], env=env, timeout=5).stdout)
        inputs = json.loads(run(["pactl", "--format=json", "list", "sink-inputs"], env=env, timeout=5).stdout)
        result["native_output_observation"] = audio_output_inventory(sinks, inputs)
        write_json(evidence / f"mpris-{phase}.json", result)
        require(prop("PlaybackStatus") == "Playing", "Playback stopped during native output observation")
        result["native_output"] = audio_output_predicate(sinks, inputs, app.identity)
        bus.call(destination, path, interface, "Pause")
        status("Paused")
        time.sleep(0.4)
        before = sample("paused-start")
        time.sleep(1.2)
        after = sample("paused-stable")
        require(abs(after - before) <= 300_000, "Playback continued after native Pause")
        result["result"] = "PASS"
    finally:
        write_json(evidence / f"mpris-{phase}.json", result)
    return result


# The X11 observer runs as a child with the private environment. The coordinator
# never changes its own HOME/DISPLAY/Xauthority or attaches to a user's session.
class Attributes(C.Structure):
    _fields_ = [(n, C.c_int) for n in ("x", "y", "width", "height", "border_width", "depth")] + [
        ("visual", C.c_void_p), ("root", C.c_ulong), ("class_", C.c_int),
        ("bit_gravity", C.c_int), ("win_gravity", C.c_int), ("backing_store", C.c_int),
        ("backing_planes", C.c_ulong), ("backing_pixel", C.c_ulong), ("save_under", C.c_int),
        ("colormap", C.c_ulong), ("map_installed", C.c_int), ("map_state", C.c_int),
        ("all_event_masks", C.c_long), ("your_event_mask", C.c_long),
        ("do_not_propagate_mask", C.c_long), ("override_redirect", C.c_int), ("screen", C.c_void_p)]


class Image(C.Structure):
    _fields_ = [(n, C.c_int) for n in ("width", "height", "xoffset", "format")] + [
        ("data", C.c_void_p)] + [(n, C.c_int) for n in
        ("byte_order", "bitmap_unit", "bitmap_bit_order", "bitmap_pad", "depth", "bytes_per_line", "bits_per_pixel")] + [
        (n, C.c_ulong) for n in ("red_mask", "green_mask", "blue_mask")] + [
        ("obdata", C.c_void_p), ("functions", C.c_void_p * 6)]


class MessageData(C.Union):
    _fields_ = [("bytes", C.c_char * 20), ("shorts", C.c_short * 10), ("longs", C.c_long * 5)]


class Message(C.Structure):
    _fields_ = [("type", C.c_int), ("serial", C.c_ulong), ("send_event", C.c_int),
                ("display", C.c_void_p), ("window", C.c_ulong), ("message_type", C.c_ulong),
                ("format", C.c_int), ("data", MessageData)]


class Event(C.Union):
    _fields_ = [("message", Message), ("padding", C.c_long * 24)]


class X11:
    def __init__(self):
        self.lib = C.CDLL("libX11.so.6")
        signatures = {
            "XOpenDisplay": (C.c_void_p, [C.c_char_p]), "XCloseDisplay": (C.c_int, [C.c_void_p]),
            "XDefaultRootWindow": (C.c_ulong, [C.c_void_p]),
            "XInternAtom": (C.c_ulong, [C.c_void_p, C.c_char_p, C.c_int]),
            "XQueryTree": (C.c_int, [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ulong)), C.POINTER(C.c_uint)]),
            "XGetWindowAttributes": (C.c_int, [C.c_void_p, C.c_ulong, C.POINTER(Attributes)]),
            "XGetWindowProperty": (C.c_int, [C.c_void_p, C.c_ulong, C.c_ulong, C.c_long, C.c_long, C.c_int, C.c_ulong, C.POINTER(C.c_ulong), C.POINTER(C.c_int), C.POINTER(C.c_ulong), C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ubyte))]),
            "XGetImage": (C.POINTER(Image), [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_ulong, C.c_int]),
            "XDestroyImage": (C.c_int, [C.POINTER(Image)]),
            "XSendEvent": (C.c_int, [C.c_void_p, C.c_ulong, C.c_int, C.c_long, C.POINTER(Event)]),
            "XSync": (C.c_int, [C.c_void_p, C.c_int]), "XFree": (C.c_int, [C.c_void_p]),
        }
        for name, (restype, argtypes) in signatures.items():
            function = getattr(self.lib, name)
            function.restype, function.argtypes = restype, argtypes
        self.errors = []
        self.error_handler = C.CFUNCTYPE(C.c_int, C.c_void_p, C.c_void_p)(
            lambda display, error: self.errors.append("X11 protocol error") or 0)
        self.lib.XSetErrorHandler.argtypes = [type(self.error_handler)]
        self.lib.XSetErrorHandler(self.error_handler)
        self.display = self.lib.XOpenDisplay(os.environ["DISPLAY"].encode())
        require(self.display, "Cannot connect to private Xvfb")

    def atom(self, name):
        return self.lib.XInternAtom(self.display, name.encode(), 0)

    def property(self, window, name):
        actual, format_, count, remaining = C.c_ulong(), C.c_int(), C.c_ulong(), C.c_ulong()
        data = C.POINTER(C.c_ubyte)()
        status = self.lib.XGetWindowProperty(self.display, window, self.atom(name), 0, 4096, 0, 0,
                                             C.byref(actual), C.byref(format_), C.byref(count), C.byref(remaining), C.byref(data))
        try:
            require(status == 0 and remaining.value == 0, "Cannot read owned window property")
            if format_.value == 32:
                return list(C.cast(data, C.POINTER(C.c_ulong))[:count.value])
            if format_.value == 8:
                return C.string_at(data, count.value)
            return []
        finally:
            if data:
                self.lib.XFree(data)

    def attributes(self, window):
        value = Attributes()
        require(self.lib.XGetWindowAttributes(self.display, window, C.byref(value)), "Owned window disappeared")
        return value

    def find_window(self, pid):
        pending, visited = [self.lib.XDefaultRootWindow(self.display)], 0
        while pending:
            window = pending.pop()
            visited += 1
            require(visited < 2048, "Unexpected private X11 window tree size")
            if self.property(window, "_NET_WM_PID") == [pid]:
                value = self.attributes(window)
                if value.map_state == 2 and value.width >= 640 and value.height >= 400:
                    title = self.property(window, "_NET_WM_NAME") or self.property(window, "WM_NAME")
                    require(isinstance(title, bytes) and b"aethertune" in title.lower(), "Unexpected ordinary app window title")
                    return window, title.decode("utf-8", "replace")
            root, parent, children, count = C.c_ulong(), C.c_ulong(), C.POINTER(C.c_ulong)(), C.c_uint()
            if self.lib.XQueryTree(self.display, window, C.byref(root), C.byref(parent), C.byref(children), C.byref(count)):
                pending.extend(children[:count.value])
            if children:
                self.lib.XFree(children)
        return None

    def screenshot(self, window, output):
        value = self.attributes(window)
        image = self.lib.XGetImage(self.display, window, 0, 0, value.width, value.height, C.c_ulong(-1).value, 2)
        require(image, "Cannot capture ordinary app window")
        try:
            info = image.contents
            require(info.bits_per_pixel == 32 and info.byte_order == 0 and
                    (info.red_mask, info.green_mask, info.blue_mask) == (0xff0000, 0xff00, 0xff),
                    "Unsupported Xvfb image encoding")
            pixels = C.string_at(info.data, info.bytes_per_line * info.height)
            rows, colors = [], set()
            for y in range(info.height):
                row = bytearray(b"\0")
                for x in range(info.width):
                    offset = y * info.bytes_per_line + x * 4
                    pixel = pixels[offset:offset + 3][::-1]
                    row.extend(pixel)
                    if len(colors) < 64:
                        colors.add(pixel)
                rows.append(row)
            require(len(colors) >= 16, "Ordinary app window is blank")
            def chunk(kind, data):
                return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
            output.write_bytes(b"\x89PNG\r\n\x1a\n" +
                               chunk(b"IHDR", struct.pack(">IIBBBBB", info.width, info.height, 8, 2, 0, 0, 0)) +
                               chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))
            return {"width": info.width, "height": info.height, "sha256": file_hash(output),
                    "content_review": "required: ordinary onboarding must be visible"}
        finally:
            self.lib.XDestroyImage(image)

    def close_window(self, window):
        delete = self.atom("WM_DELETE_WINDOW")
        require(delete in self.property(window, "WM_PROTOCOLS"), "Ordinary window does not support WM_DELETE_WINDOW")
        event = Event()
        event.message.type, event.message.display, event.message.window = 33, self.display, window
        event.message.message_type, event.message.format = self.atom("WM_PROTOCOLS"), 32
        event.message.data.longs[0], event.message.data.longs[1] = delete, 0
        require(self.lib.XSendEvent(self.display, window, 0, 0, C.byref(event)), "WM_DELETE_WINDOW could not be sent")
        self.lib.XSync(self.display, 0)
        require(not self.errors, "Private X11 observer encountered a protocol error")


def observe(pid, identity, evidence):
    x11 = X11()
    try:
        deadline, window = time.monotonic() + 30, None
        while time.monotonic() < deadline:
            require(process_identity(pid) == identity, "Ordinary installed app exited before its window appeared")
            window = x11.find_window(pid)
            if window:
                break
            time.sleep(0.2)
        require(window, "Ordinary installed app did not show a window")
        owned_window, title = window
        started = time.monotonic()
        while time.monotonic() - started < 15:
            require(process_identity(pid) == identity, "Ordinary installed app exited during window observation")
            require(x11.attributes(owned_window).map_state == 2, "Ordinary app window stopped being visible")
            time.sleep(0.2)
        screenshot = x11.screenshot(owned_window, evidence / "ordinary-onboarding.png")
        modules = set()
        for line in Path(f"/proc/{pid}/maps").read_text().splitlines():
            fields = line.split(maxsplit=5)
            if len(fields) == 6 and fields[5].startswith(str(INSTALL) + "/"):
                modules.add(fields[5])
        require(str(INSTALL / "aethertune") in modules, "Ordinary executable mapping absent")
        require(any(name.endswith("/libflutter_linux_gtk.so") for name in modules), "Flutter native runtime mapping absent")
        report = {"pid": pid, "identity": identity, "window": owned_window, "title": title,
                  "visible_seconds": time.monotonic() - started, "screenshot": screenshot,
                  "modules": {name: file_hash(name) for name in sorted(modules)}}
        # Retain launch/screenshot evidence even if the subsequent close fails.
        write_json(evidence / "window.json", report)
        x11.close_window(owned_window)
        report["wm_delete_sent"] = True
        write_json(evidence / "window.json", report)
    finally:
        x11.lib.XCloseDisplay(x11.display)


def close_behavior_window(pid, identity, window, evidence, phase):
    require(phase in ("initial", "reopen"), "Invalid close phase")
    require(process_identity(pid) == identity and identity["exe"] == str(INSTALL / "aethertune"), "App identity changed before normal close")
    x11 = X11()
    try:
        require(x11.property(window, "_NET_WM_PID") == [pid] and x11.attributes(window).map_state == 2,
                "Observed UI window is no longer owned and visible")
        modules = set()
        for line in Path(f"/proc/{pid}/maps").read_text().splitlines():
            fields = line.split(maxsplit=5)
            if len(fields) == 6 and fields[5].startswith(str(INSTALL) + "/"):
                modules.add(fields[5])
        require(str(INSTALL / "aethertune") in modules and
                any(name.endswith("/libflutter_linux_gtk.so") for name in modules), "Ordinary native mappings are absent")
        receipt = {"identity": identity, "phase": phase, "window_xid": window, "wm_delete_sent": False,
                   "modules": {name: file_hash(name) for name in sorted(modules)}}
        write_json(evidence / f"close-{phase}.json", receipt)
        require(process_identity(pid) == identity, "App identity changed before WM_DELETE")
        x11.close_window(window)
        receipt.update(wm_delete_sent=True, observed_utc=datetime.now(timezone.utc).isoformat())
        write_json(evidence / f"close-{phase}.json", receipt)
    finally:
        x11.lib.XCloseDisplay(x11.display)


def ui_receipt(evidence, phase, app, portal, media):
    path = evidence / f"behavior-{phase}.json"
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 2 * 1024 * 1024, "UI receipt is absent or invalid")
    receipt = json.loads(path.read_text())
    require(receipt.get("schema_version") == 1 and receipt.get("result") == "PASS" and receipt.get("phase") == phase and
            receipt.get("app_identity") == app.identity and receipt.get("portal_identity") == portal.identity,
            "UI receipt phase/process binding differs")
    require(receipt.get("media") == {"path": str(media), "sha256": MEDIA_SHA256, "size": 7938044} and
            isinstance(receipt.get("window_xid"), int) and receipt["window_xid"] > 0,
            "UI receipt media/window binding differs")
    screenshots = receipt.get("screenshots", {})
    require(isinstance(screenshots, dict) and screenshots, "UI screenshot bindings are absent")
    for record in screenshots.values():
        target = Path(record["path"])
        if not target.is_absolute():
            target = evidence / target
        require(target.resolve().is_relative_to(evidence.resolve()) and not target.is_symlink() and target.is_file() and
                target.stat().st_size <= 64 * 1024 * 1024 and file_hash(target) == record["sha256"], "UI screenshot binding differs")
    return receipt


def behavior_acceptance(start, env, fixture, evidence, report, base_services):
    env.update(XDG_CURRENT_DESKTOP="GNOME", GTK_MODULES="atk-bridge")
    env.pop("NO_AT_BRIDGE", None)
    services = []
    owners = []
    main_bus = PrivateBus(env["DBUS_SESSION_BUS_ADDRESS"])
    a11y_bus = None
    try:
        config = fixture / "private-a11y-bus.conf"
        config.write_text((fixture / "private-bus.conf").read_text().replace("runtime/private-bus", "runtime/private-a11y-bus"))
        a11y = start("a11y-dbus", ["dbus-daemon", f"--config-file={config}", "--nofork", "--print-address=1", "--print-pid=1"], stdout=subprocess.PIPE)
        services.append(a11y)
        env["AT_SPI_BUS_ADDRESS"] = read_pipe_line(a11y.handle.stdout)
        require(read_pipe_line(a11y.handle.stdout) == str(a11y.handle.pid), "Private accessibility D-Bus PID mismatch")
        a11y.handle.stdout.close()
        a11y_bus = PrivateBus(env["AT_SPI_BUS_ADDRESS"])
        registry = start("a11y-registry", [package_executable("at-spi2-core", "at-spi2-registryd")])
        services.append(registry)
        owners.append(a11y_bus.wait_owner("org.a11y.atspi.Registry", registry))
        portal_config = fixture / "config/xdg-desktop-portal"
        portal_config.mkdir(mode=0o700)
        (portal_config / "portals.conf").write_text("[preferred]\ndefault=gtk\n")
        for name, binary, service_name in (
            ("permission-store", "xdg-permission-store", "org.freedesktop.impl.portal.PermissionStore"),
            ("document-portal", "xdg-document-portal", "org.freedesktop.portal.Documents")):
            service = start(name, [package_executable("xdg-desktop-portal", binary)])
            services.append(service)
            if name == "document-portal":
                document = service
                report["document_portal"] = document.identity
            owners.append(main_bus.wait_owner(service_name, service))
        document_helper(document, services, fixture, evidence, report)
        gtk = start("gtk-portal", [package_executable("xdg-desktop-portal-gtk", "xdg-desktop-portal-gtk")])
        services.append(gtk)
        owners.append(main_bus.wait_owner("org.freedesktop.impl.portal.desktop.gtk", gtk))
        dispatcher = start("desktop-portal", [package_executable("xdg-desktop-portal", "xdg-desktop-portal")])
        services.append(dispatcher)
        owners.append(main_bus.wait_owner("org.freedesktop.portal.Desktop", dispatcher))
        report["behavior_services"] = owners
        report["behavior_mounts_during_runtime"] = mounts_under(fixture)
        children = unexpected_children(services, report)
        report["unexpected_service_children"] = children
        require(not children, "An explicit desktop service spawned an untracked child")
        media = make_media(fixture)
        report["media"] = {"path": str(media), "sha256": MEDIA_SHA256, "size": media.stat().st_size,
                           "channels": 1, "rate_hz": 22050, "pcm_bits": 16, "duration_seconds": 180}
        states, first_identity = {}, None
        observer_script = Path(__file__).with_name("linux_release_ui_acceptance.py").resolve()
        for phase in ("initial", "reopen"):
            if phase == "reopen":
                require(report["application_exits"]["initial"]["returncode"] == 0 and
                        process_identity(first_identity["pid"]) != first_identity and not installed_processes(),
                        "Reopen requires the first ordinary process to have exited normally")
            app = start(f"application-{phase}", [str(INSTALL / "aethertune")], cwd=fixture)
            require(app.identity["exe"] == str(INSTALL / "aethertune") and file_hash(INSTALL / "aethertune") == PRODUCT_EXE,
                    "Unexpected installed behavior process identity")
            if first_identity is None:
                first_identity = app.identity
            else:
                require(app.identity["pid"] != first_identity["pid"], "Reopen process PID was reused unexpectedly")
            observer = start(f"ui-{phase}", [sys.executable, str(observer_script), "--phase", phase,
                "--pid", str(app.handle.pid), "--identity", json.dumps(app.identity), "--portal-identity", json.dumps(gtk.identity),
                "--media", str(media), "--media-sha256", MEDIA_SHA256, "--evidence", str(evidence)])
            require(observer.handle.wait(timeout=180) == 0, f"Ordinary UI {phase} acceptance failed; see ui-{phase}.log")
            receipt = ui_receipt(evidence, phase, app, gtk, media)
            report.setdefault("behavior_ui", {})[phase] = receipt
            states[phase] = wait_state(fixture, evidence, phase)
            report.setdefault("behavior_mpris", {})[phase] = mpris_behavior(main_bus, app, states[phase], evidence, phase, env)
            if phase == "reopen":
                require(states[phase]["predicates"] == states["after-initial-close"]["predicates"], "Native persisted fixture state changed on reopen")
            closer = start(f"normal-close-{phase}", [sys.executable, str(Path(__file__).resolve()), "--close", str(app.handle.pid),
                "--identity", json.dumps(app.identity), "--window", str(receipt["window_xid"]), "--phase", phase, "--evidence", str(evidence)])
            require(closer.handle.wait(timeout=15) == 0, "Normal WM_DELETE request failed")
            wait_for_ordinary_exit(app, report, evidence, phase=phase)
            require(all(p.handle.poll() is None and process_identity(p.handle.pid) == p.identity for p in base_services + services),
                    "An owned desktop service exited or changed identity during acceptance")
            children = unexpected_children(services, report)
            report["unexpected_service_children"] = children
            require(not children, "An explicit desktop service spawned an untracked child")
            states[f"after-{phase}-close"] = wait_state(fixture, evidence, f"after-{phase}-close")
        require(states["after-initial-close"]["predicates"] == states["after-reopen-close"]["predicates"], "Closed-profile persistence differs")
        require(file_hash(media) == MEDIA_SHA256, "UI-imported fixture bytes changed")
        report["behavior_native_state"] = states
        report["ordinary_two_process_behavior_and_graceful_exits"] = True
        report["behavior_scope"] = ["ordinary native file-picker import", "desktop keyboard navigation and Compact preference",
            "WAV playback and native MPRIS Play/Pause/SetPosition", "library/current queue/preference continuity across normal close/reopen"]
    finally:
        # Preserve unexpected live descendants even when an earlier predicate
        # fails; these records do not authorize sending them a signal.
        report["unexpected_service_children"] = list({
            (value["pid"], value["start_ticks"]): value
            for value in report.get("unexpected_service_children", []) + unexpected_children(services, report, require_live=False)
        }.values())
        if a11y_bus:
            a11y_bus.close()
        main_bus.close()


def acceptance(args):
    require(sys.platform == "linux" and os.geteuid() != 0 and
            os.environ.get("GITHUB_ACTIONS") == "true" and
            os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted" and
            os.environ.get("RUNNER_OS") == "Linux", "Only a non-root ephemeral GitHub-hosted Linux runner is supported")
    evidence = args.evidence.resolve()
    require(not evidence.exists(), "Evidence destination must be new")
    evidence.mkdir(parents=True)
    report = {"result": "FAIL", "source_sha": os.environ.get("GITHUB_SHA"),
              "run_id": os.environ.get("GITHUB_RUN_ID"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
              "scope": "ordinary unchanged release payload; isolated hosted CI fixture",
              "excluded": ["production signing/trust", "physical audio", "accessibility", "versioned upgrade"],
              "screenshot_review": "pending", "cleanup": {}, "processes": []}
    if args.behavior:
        report["mode"] = "behavior"
        report["excluded"] = ["production signing/trust", "physical audio/device coverage", "screen reader acceptance",
                              "all-platform accessibility", "versioned upgrade/rollback", "sync/provider acceptance", "other codecs"]
        report["source_sha_scope"] = "executor checkout only; product source is separately pinned in product_provenance"
    fixture, owned, logs, attempted = None, [], [], False
    expected_record, bundle, payload = None, None, None
    try:
        for tool in ("sudo", "dpkg", "dpkg-query", "Xvfb", "dbus-daemon", "gnome-keyring-daemon", "gdbus", "pulseaudio", "pactl"):
            require(shutil.which(tool), f"Existing Linux acceptance prerequisite absent: {tool}")
        assert_fresh(package_record())
        require(not installed_processes(), "Refusing existing processes from the installation path")
        bundle = tree_manifest(args.bundle.resolve())
        hashes = {"deb": file_hash(args.deb), "tarball": file_hash(args.tarball)}
        payload = verify_archives(bundle, args.deb, args.tarball, args.version)
        if args.behavior:
            report["product_provenance"] = behavior_provenance(args.product_provenance, args, hashes, bundle)
        write_json(evidence / "bundle-manifest.json", bundle)
        report.update(archives=hashes, package={"name": PACKAGE, "version": args.version, "architecture": "amd64"})
        # Recheck absence immediately before taking install ownership.
        assert_fresh(package_record())
        attempted = True
        installation = run(["sudo", "-n", "dpkg", "--install", str(args.deb.resolve())], check=False, timeout=60)
        (evidence / "install.log").write_text(installation.stdout + installation.stderr)
        expected_record = f"{PACKAGE}\t{args.version}\tinstall ok installed"
        require(installation.returncode == 0 and package_record() == expected_record, "Exact package installation failed")
        require(tree_manifest(INSTALL) == bundle and DESKTOP.read_bytes() == DESKTOP_BYTES, "Installed payload differs from release archives")
        require(stat.S_IMODE(DESKTOP.stat().st_mode) == 0o644, "Installed desktop entry mode differs")
        report["installed_payload_matches"] = True
        report["installed_executable_sha256"] = file_hash(INSTALL / "aethertune")
        fixture = Path(tempfile.mkdtemp(prefix="aethertune-release-fixture-", dir="/tmp"))
        (fixture / ".owned-release-fixture").write_text("aethertune-linux-release-v1\n")
        for name in ("config", "data", "cache", "runtime", "documents"):
            (fixture / name).mkdir(mode=0o700)
        (fixture / "config/user-dirs.dirs").write_text(f'XDG_DOCUMENTS_DIR="{fixture}/documents"\n')
        (fixture / "config/pulse").mkdir(mode=0o700)
        (fixture / "config/pulse/client.conf").write_text("autospawn = no\n")
        bus_config = fixture / "private-bus.conf"
        # No activation directories. Behavior mode starts each real portal and
        # accessibility daemon explicitly; default mode makes no such claim.
        bus_config.write_text(f"""<busconfig>
  <type>session</type>
  <listen>unix:path={fixture}/runtime/private-bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow user="{os.getuid()}"/>
    <allow own="*"/>
    <allow send_destination="*"/>
    <allow receive_sender="*"/>
  </policy>
</busconfig>
""")
        env = private_environment(fixture, os.environ)
        def start(name, command, **options):
            log = (evidence / f"{name}.log").open("wb")
            logs.append(log)
            process = OwnedProcess(command, env, log, **options)
            owned.append(process)
            report["processes"].append({"name": name, "argv": command, "started_utc": process.started_utc, **process.identity})
            write_json(evidence / "result.json", report)
            return process
        authority = fixture / "Xauthority"
        cookie = os.urandom(16)
        def write_authority(number):
            fields = [b"", number.encode(), b"MIT-MAGIC-COOKIE-1", cookie]
            authority.write_bytes(struct.pack(">H", 65535) + b"".join(struct.pack(">H", len(value)) + value for value in fields))
        # The server reads the cookie from its explicitly owned auth file; the
        # client record is then bound to the display selected by -displayfd.
        write_authority("0")
        authority.chmod(0o600)
        env["XAUTHORITY"] = str(authority)
        read_fd, write_fd = os.pipe()
        try:
            xvfb = start("xvfb", ["Xvfb", "-displayfd", str(write_fd), "-screen", "0", "1280x900x24", "-nolisten", "tcp", "-auth", str(authority)], pass_fds=(write_fd,))
            os.close(write_fd)
            write_fd = None
            with os.fdopen(read_fd, "rb", buffering=0) as stream:
                read_fd = None
                display = read_pipe_line(stream)
            require(display.isdecimal(), "Invalid private Xvfb display")
            write_authority(display)
            env["DISPLAY"] = f":{display}"
        finally:
            for descriptor in (read_fd, write_fd):
                if descriptor is not None:
                    os.close(descriptor)
        dbus = start("dbus", ["dbus-daemon", f"--config-file={bus_config}", "--nofork", "--print-address=1", "--print-pid=1"], stdout=subprocess.PIPE)
        env["DBUS_SESSION_BUS_ADDRESS"] = read_pipe_line(dbus.handle.stdout)
        env["DBUS_SYSTEM_BUS_ADDRESS"] = env["DBUS_SESSION_BUS_ADDRESS"]
        require(read_pipe_line(dbus.handle.stdout) == str(dbus.handle.pid), "Private D-Bus PID mismatch")
        dbus.handle.stdout.close()
        keyring_command = ["gnome-keyring-daemon", "--foreground", "--unlock", "--components=secrets"]
        if args.behavior:
            control = fixture / "runtime/keyring"
            control.mkdir(mode=0o700)
            keyring_command += [f"--control-directory={control}"]
            env["GNOME_KEYRING_CONTROL"] = str(control)
        keyring = start("keyring", keyring_command, stdin=subprocess.PIPE)
        keyring.handle.stdin.write(b"ci-fixture-only\n")
        keyring.handle.stdin.close()
        run(["gdbus", "wait", "--session", "--timeout", "10", "org.freedesktop.secrets"], env=env, timeout=15)
        socket = fixture / "runtime/pulse/native"
        socket.parent.mkdir(mode=0o700)
        env.update(PULSE_SERVER=f"unix:{socket}", PULSE_SINK="aethertune_release_fixture")
        pulse = start("pulse", ["pulseaudio", "--daemonize=no", "--exit-idle-time=-1", "--log-target=stderr", "-n",
                              f"--load=module-native-protocol-unix socket={socket}",
                              "--load=module-null-sink sink_name=aethertune_release_fixture"])
        deadline = time.monotonic() + 10
        while True:
            require(pulse.handle.poll() is None, "Private PulseAudio exited")
            if run(["pactl", "info"], env=env, check=False).returncode == 0:
                break
            require(time.monotonic() < deadline, "Private PulseAudio startup timed out")
            time.sleep(0.2)
        if args.behavior:
            behavior_acceptance(start, env, fixture, evidence, report, [xvfb, dbus, keyring, pulse])
        else:
            app = start("application", [str(INSTALL / "aethertune")], cwd=fixture)
            require(app.identity["exe"] == str(INSTALL / "aethertune"), "Unexpected installed executable process identity")
            observer = start("observer", [sys.executable, str(Path(__file__).resolve()), "--observe", str(app.handle.pid),
                                         "--identity", json.dumps(app.identity), "--evidence", str(evidence)])
            require(observer.handle.wait(timeout=55) == 0, "Ordinary window acceptance failed; see observer.log")
            wait_for_ordinary_exit(app, report, evidence)
            require(all(process.handle.poll() is None for process in (xvfb, dbus, keyring, pulse)),
                    "A private desktop service exited during ordinary app observation")
            report["ordinary_window_and_graceful_exit"] = True
            report["window"] = json.loads((evidence / "window.json").read_text())
        require(tree_manifest(INSTALL) == bundle, "Installed payload changed during ordinary launch")
        require(file_hash(args.deb) == hashes["deb"] and file_hash(args.tarball) == hashes["tarball"]
                and tree_manifest(args.bundle.resolve()) == bundle, "Original release inputs changed")
        if args.behavior:
            require(file_hash(args.product_provenance) == report["product_provenance"]["sha256"], "Original product provenance changed")
        report["result"] = "PASS"
    except Exception as error:
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        cleanup_errors = []
        for process in reversed(owned):
            try:
                outcome = process.stop()
                report["cleanup"][str(process.handle.pid)] = outcome
                require(process.handle.poll() is not None and process_identity(process.handle.pid) is None,
                        "Owned process remains after cleanup")
                if process.identity == report.get("document_portal"):
                    report["cleanup"]["document_portal_exit"] = {"outcome": outcome, "returncode": process.handle.returncode}
                    require(outcome == "terminated" and process.handle.returncode == 0, "Document portal did not complete normal SIGTERM/unmount shutdown")
            except Exception as error:
                cleanup_errors.append(str(error))
        for log in logs:
            log.close()
        if attempted:
            try:
                record = package_record()
                if record is not None:
                    require(record.split("\t")[:2] == [PACKAGE, args.version], "Refused purge: installed package identity changed")
                    require(file_hash(args.deb) == hashes["deb"], "Refused purge: original package changed")
                    report["purge_ownership"] = verify_purge_ownership(payload, partial=record != expected_record,
                                                                       bundle_root=args.bundle.resolve())
                    removal = run(["sudo", "-n", "dpkg", "--purge", PACKAGE], check=False, timeout=60)
                    (evidence / "uninstall.log").write_text(removal.stdout + removal.stderr)
                    require(removal.returncode == 0, "Exact package purge failed")
                assert_fresh(package_record())
                require(not installed_processes(), "Processes from the installation path remain after removal")
                report["cleanup"]["package_install_path_desktop_entry_absent"] = True
            except Exception as error:
                cleanup_errors.append(str(error))
        if fixture:
            try:
                # A document portal may mount FUSE under runtime/doc. Never walk
                # or recursively delete a mounted view of any other files.
                deadline = time.monotonic() + 5
                while (mounts_under(fixture) or (report.get("fuse_helper") and generation_alive(report["fuse_helper"]))) and time.monotonic() < deadline:
                    time.sleep(0.2)
                remaining_mounts = mounts_under(fixture)
                report["cleanup"]["mounts_below_owned_profile"] = remaining_mounts
                require(not remaining_mounts, "Refused profile cleanup: a portal mount remains")
                if report.get("fuse_helper"):
                    report["cleanup"]["fuse_helper_absent"] = not generation_alive(report["fuse_helper"])
                    require(report["cleanup"]["fuse_helper_absent"], "Refused profile cleanup: the bound FUSE helper remains")
                if report.get("document_portal"):
                    require(report["cleanup"].get("document_portal_exit") == {"outcome": "terminated", "returncode": 0},
                            "Refused profile cleanup: document portal normal shutdown is unproven")
                require(not any(generation_alive(child) for child in report.get("unexpected_service_children", [])),
                        "Refused profile cleanup: an untracked service child remains")
                report["profile_leftovers_before_fixture_removal"] = [
                    {"path": path.relative_to(fixture).as_posix(), "mode": oct(path.lstat().st_mode)}
                    for path in sorted(fixture.rglob("*"))]
                report["user_data_removal_scope"] = "owned CI profile only; dpkg does not remove user profiles"
                require(fixture.parent == Path("/tmp") and fixture.name.startswith("aethertune-release-fixture-")
                        and not fixture.is_symlink() and (fixture / ".owned-release-fixture").read_text() == "aethertune-linux-release-v1\n",
                        "Refused cleanup of an unexpected profile")
                shutil.rmtree(fixture)
                require(not fixture.exists(), "Owned profile remains")
                report["cleanup"]["owned_profile_absent"] = True
            except Exception as error:
                cleanup_errors.append(str(error))
        if cleanup_errors:
            report["result"], report["cleanup_errors"] = "FAIL", cleanup_errors
        write_json(evidence / "result.json", report)
    print(json.dumps({key: report.get(key) for key in ("result", "error", "cleanup_errors", "screenshot_review")}))
    return 0 if report["result"] == "PASS" else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--deb", type=Path)
    parser.add_argument("--tarball", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--observe", type=int)
    parser.add_argument("--behavior", action="store_true", help="Real native import/playback/keyboard/close/reopen acceptance")
    parser.add_argument("--product-provenance", type=Path)
    parser.add_argument("--close", type=int)
    parser.add_argument("--window", type=int)
    parser.add_argument("--phase", choices=("initial", "reopen"))
    parser.add_argument("--inspect-fuse-child", type=int)
    parser.add_argument("--helper-start", type=int)
    parser.add_argument("--helper-executable")
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--fixture-uid", type=int)
    parser.add_argument("--mount-identity")
    parser.add_argument("--identity")
    args = parser.parse_args()
    if args.inspect_fuse_child:
        require(sys.platform == "linux" and os.geteuid() == 0 and not args.behavior and not args.observe and not args.close,
                "FUSE inspection is an isolated privileged read-only mode")
        parent, fixture, mount = json.loads(args.identity), args.fixture, json.loads(args.mount_identity)
        require(fixture is not None and fixture.is_absolute() and fixture.parent == Path("/tmp") and
                fixture.name.startswith("aethertune-release-fixture-") and not fixture.is_symlink() and
                type(args.fixture_uid) is int and args.fixture_uid > 0 and fixture.stat().st_uid == args.fixture_uid and
                (fixture / ".owned-release-fixture").read_text() == "aethertune-linux-release-v1\n", "Invalid owned FUSE fixture")
        require(parent.get("exe") == package_executable("xdg-desktop-portal", "xdg-document-portal") and
                args.helper_executable == package_executable("fuse3", "fusermount3"), "Inspection executable package binding differs")
        require(mounts_under(fixture) == [mount], "Inspection mount identity changed")
        print(json.dumps(read_fuse_helper(args.inspect_fuse_child, parent, args.helper_executable, fixture,
                                         args.fixture_uid, mount, args.helper_start)))
        return 0
    if args.observe:
        require(not args.behavior and not args.close, "Observer mode cannot be mixed with behavior")
        observe(args.observe, json.loads(args.identity), args.evidence)
        return 0
    if args.close:
        require(args.window and args.phase and args.identity and not args.behavior, "Bound close identity/window/phase are required")
        close_behavior_window(args.close, json.loads(args.identity), args.window, args.evidence, args.phase)
        return 0
    require(all((args.bundle, args.deb, args.tarball, args.version)), "Release bundle, archives, and version are required")
    return acceptance(args)


if __name__ == "__main__":
    # Interruption follows the same owned-process/package cleanup as failure.
    signal.signal(signal.SIGTERM, lambda signum, frame: (_ for _ in ()).throw(RuntimeError("Acceptance interrupted")))
    sys.exit(main())
