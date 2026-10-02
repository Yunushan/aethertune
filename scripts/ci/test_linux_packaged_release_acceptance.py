#!/usr/bin/env python3
"""Behavioral regressions for release payload and cleanup ownership boundaries."""
from __future__ import annotations

import hashlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

import linux_packaged_release_acceptance as gate


def tar_bytes(entries):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w", format=tarfile.GNU_FORMAT) as archive:
        for name, kind, value, mode in entries:
            entry = tarfile.TarInfo(name)
            entry.mode = mode
            if kind == "directory":
                entry.type = tarfile.DIRTYPE
            elif kind in ("symlink", "hardlink"):
                entry.type = tarfile.SYMTYPE if kind == "symlink" else tarfile.LNKTYPE
                entry.linkname = value
            else:
                entry.size = len(value)
            archive.addfile(entry, io.BytesIO(value) if kind == "file" else None)
    return stream.getvalue()


def ar_bytes(members):
    output = bytearray(b"!<arch>\n")
    for name, data in members:
        header = f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n".encode()
        assert len(header) == 60
        output.extend(header + data + (b"\n" if len(data) % 2 else b""))
    return bytes(output)


class PackagedReleaseTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.deb, self.tarball = self.root / "app.deb", self.root / "app.tar.gz"
        self.entries = [("aethertune", "file", b"ordinary executable fixture", 0o755),
                        ("data", "directory", None, 0o755),
                        ("data/flutter_assets", "directory", None, 0o755),
                        ("data/flutter_assets/AssetManifest.bin", "file", b"assets", 0o644),
                        ("lib", "directory", None, 0o755),
                        ("lib/libflutter_linux_gtk.so", "file", b"native fixture", 0o644)]
        with tarfile.open(fileobj=io.BytesIO(tar_bytes(self.entries)), mode="r:") as archive:
            self.bundle = gate.tar_manifest(archive)
        self.control = [("control", "file", b"""Package: aethertune
Version: 0.1.0
Section: sound
Priority: optional
Architecture: amd64
Maintainer: AetherTune Contributors
Description: Free and open-source local-first music player
 AetherTune is a privacy-respecting music player with local files and legal providers.
""", 0o644)]
        self.payload = [(name, "directory", None, 0o755) for name in
                        ("opt", "opt/aethertune", "usr", "usr/share", "usr/share/applications")]
        self.payload.extend((f"opt/aethertune/{name}", kind, value, mode) for name, kind, value, mode in self.entries)
        self.payload.append(("usr/share/applications/aethertune.desktop", "file", gate.DESKTOP_BYTES, 0o644))
        self.write()

    def write(self):
        with tarfile.open(self.tarball, "w:gz") as archive:
            with tarfile.open(fileobj=io.BytesIO(tar_bytes(self.entries)), mode="r:") as source:
                for entry in source:
                    archive.addfile(entry, source.extractfile(entry) if entry.isfile() else None)
        self.deb.write_bytes(ar_bytes([("debian-binary", b"2.0\n"),
                                      ("control.tar", tar_bytes(self.control)),
                                      ("data.tar", tar_bytes(self.payload))]))

    def verify(self):
        return gate.verify_archives(self.bundle, self.deb, self.tarball, "0.1.0")

    def test_valid_exact_release_archives_and_native_hashes(self):
        payload = self.verify()
        self.assertEqual(payload["opt/aethertune/aethertune"]["sha256"],
                         hashlib.sha256(b"ordinary executable fixture").hexdigest())
        self.assertEqual(payload["opt/aethertune/lib/libflutter_linux_gtk.so"],
                         self.bundle["lib/libflutter_linux_gtk.so"])

    def test_tampered_tarball_cannot_claim_bundle_identity(self):
        self.entries[0] = ("aethertune", "file", b"different executable", 0o755)
        self.write()
        with self.assertRaisesRegex(RuntimeError, "Tarball payload differs"):
            self.verify()

    def test_tampered_deb_native_payload_rejected(self):
        index = next(i for i, entry in enumerate(self.payload) if entry[0].endswith(".so"))
        self.payload[index] = (self.payload[index][0], "file", b"different native code", 0o644)
        self.write()
        with self.assertRaisesRegex(RuntimeError, "Debian payload"):
            self.verify()

    def test_install_hook_rejected_before_dpkg(self):
        marker = self.root / "unexpected-install-side-effect"
        self.control.append(("postinst", "file", f"touch {marker}".encode(), 0o755))
        self.write()
        with self.assertRaisesRegex(RuntimeError, "install hooks"):
            self.verify()
        self.assertFalse(marker.exists())

    def test_archive_traversal_rejected_without_extraction(self):
        self.payload.append(("../escaped", "file", b"forbidden", 0o644))
        self.write()
        with self.assertRaisesRegex(RuntimeError, "Unsafe archive path"):
            self.verify()
        self.assertFalse((self.root.parent / "escaped").exists())

    def test_escaping_bundle_symlink_rejected(self):
        with tarfile.open(fileobj=io.BytesIO(tar_bytes([("outside", "symlink", "../personal", 0o777)])), mode="r:") as archive:
            with self.assertRaisesRegex(RuntimeError, "Escaping symlink"):
                gate.tar_manifest(archive)

    def test_hardlink_preserves_hash_and_mode(self):
        values = [("original", "file", b"same bytes", 0o755),
                  ("linked", "hardlink", "original", 0o755)]
        with tarfile.open(fileobj=io.BytesIO(tar_bytes(values)), mode="r:") as archive:
            manifest = gate.tar_manifest(archive)
        self.assertEqual(manifest["original"], manifest["linked"])

    def test_control_tar_cannot_read_into_next_ar_member(self):
        # A forged member length cannot borrow the following data.tar header or payload.
        value = self.deb.read_bytes()
        offset = value.index(b"control.tar/")
        header = value[offset:offset + 60]
        self.deb.write_bytes(value[:offset] + header[:48] + f"{512:<10}".encode() + header[58:] + value[offset + 60:])
        with self.assertRaises((RuntimeError, tarfile.TarError, ValueError, UnicodeError)):
            self.verify()

    def test_existing_install_or_package_is_never_taken_over(self):
        install, desktop = self.root / "install", self.root / "desktop"
        gate.assert_fresh(None, install, desktop)
        install.mkdir()
        marker = install / "personal-state"
        marker.write_bytes(b"preserve")
        with self.assertRaisesRegex(RuntimeError, "Refusing an existing"):
            gate.assert_fresh(None, install, desktop)
        self.assertEqual(marker.read_bytes(), b"preserve")
        with self.assertRaisesRegex(RuntimeError, "Refusing an existing"):
            gate.assert_fresh("aethertune\t0.1.0\tdeinstall ok config-files", self.root / "missing", desktop)

    def test_failed_same_version_install_rejects_foreign_payload_before_purge(self):
        expected = gate.package_payload(self.bundle)
        name = "opt/aethertune/aethertune"
        files = ["/", *('/' + path for path in expected)]
        # Missing original entries are legitimate after interruption.
        gate.validate_purge_inventory(expected, {name: expected[name]}, files,
                                      ["aethertune.list"], partial=True)
        changed = dict(expected[name], sha256="f" * 64)
        for present in ({name: changed}, {"opt/aethertune/foreign": expected[name]}):
            with self.assertRaisesRegex(RuntimeError, "foreign or changed"):
                gate.validate_purge_inventory(expected, present, files, ["aethertune.list"], partial=True)
        with self.assertRaisesRegex(RuntimeError, "foreign dpkg-owned"):
            gate.validate_purge_inventory(expected, {}, files + ["/personal/path"], ["aethertune.list"], partial=True)
        with self.assertRaisesRegex(RuntimeError, "control metadata/hooks"):
            gate.validate_purge_inventory(expected, {}, files, ["aethertune.list", "aethertune.prerm"], partial=True)

    def test_installed_status_cannot_hide_missing_original_files(self):
        expected = gate.package_payload(self.bundle)
        files = ["/", *('/' + path for path in expected)]
        with self.assertRaisesRegex(RuntimeError, "complete installed payload"):
            gate.validate_purge_inventory(expected, {}, files, ["aethertune.list"], partial=False)

    def test_private_environment_does_not_change_coordinator_or_attach_shared_session(self):
        original = {"HOME": "/personal", "DISPLAY": ":0", "DBUS_SESSION_BUS_ADDRESS": "shared",
                    "PULSE_SERVER": "shared", "WAYLAND_DISPLAY": "wayland-0", "PATH": "/bin"}
        before = original.copy()
        child = gate.private_environment(self.root, original)
        self.assertEqual(original, before)
        self.assertEqual(child["HOME"], str(self.root))
        for name in ("DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "PULSE_SERVER", "WAYLAND_DISPLAY"):
            self.assertNotIn(name, child)
        self.assertEqual(child["PATH"], "/bin")

    def test_pid_reuse_guard_refuses_then_cleans_only_its_owned_child(self):
        # A real disposable child proves the refusal sends no signal. The identity
        # reader is supplied so this ownership regression also runs on Windows.
        handle = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
        process = gate.OwnedProcess.__new__(gate.OwnedProcess)
        process.handle = handle
        process.identity = {"pid": handle.pid, "start_ticks": 1, "exe": sys.executable}
        try:
            with self.assertRaisesRegex(RuntimeError, "PID identity changed"):
                process.stop(lambda pid: dict(process.identity, start_ticks=2))
            self.assertIsNone(handle.poll())
            self.assertEqual(process.stop(lambda pid: process.identity), "terminated")
            self.assertIsNotNone(handle.poll())
        finally:
            if handle.poll() is None:
                handle.terminate()
                handle.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
