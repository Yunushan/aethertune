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


def wait_for_ordinary_exit(app, report, evidence, diagnostics=failure_exit_diagnostics):
    outcome = {"identity": app.identity, "started_utc": app.started_utc,
               "wm_delete_sent": True, "wait_timeout_seconds": 15}
    report["application_exit"] = outcome
    try:
        code = app.handle.wait(timeout=15)
    except subprocess.TimeoutExpired:
        outcome.update(returncode=None, timed_out=True)
        write_json(evidence / "application-exit.json", outcome)
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
    write_json(evidence / "application-exit.json", outcome)
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
    for key in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "DBUS_SYSTEM_BUS_ADDRESS", "PULSE_SERVER", "PULSE_SINK"):
        env.pop(key, None)
    env.update(HOME=str(fixture), XDG_CONFIG_HOME=str(fixture / "config"),
               XDG_DATA_HOME=str(fixture / "data"), XDG_CACHE_HOME=str(fixture / "cache"),
               XDG_RUNTIME_DIR=str(fixture / "runtime"), LIBGL_ALWAYS_SOFTWARE="1",
               GDK_BACKEND="x11", LANG="C.UTF-8", LC_ALL="C.UTF-8")
    return env


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


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
        # No activation service directories: portals/AT-SPI cannot spawn unowned
        # descendants. Accessibility is explicitly outside this fixture's claim.
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
        keyring = start("keyring", ["gnome-keyring-daemon", "--foreground", "--unlock", "--components=secrets"], stdin=subprocess.PIPE)
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
    parser.add_argument("--identity")
    args = parser.parse_args()
    if args.observe:
        observe(args.observe, json.loads(args.identity), args.evidence)
        return 0
    require(all((args.bundle, args.deb, args.tarball, args.version)), "Release bundle, archives, and version are required")
    return acceptance(args)


if __name__ == "__main__":
    # Interruption follows the same owned-process/package cleanup as failure.
    signal.signal(signal.SIGTERM, lambda signum, frame: (_ for _ in ()).throw(RuntimeError("Acceptance interrupted")))
    sys.exit(main())
