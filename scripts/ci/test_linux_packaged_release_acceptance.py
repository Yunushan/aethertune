#!/usr/bin/env python3
"""Behavioral regressions for release payload and cleanup ownership boundaries."""
from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

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
                    "PULSE_SERVER": "shared", "WAYLAND_DISPLAY": "wayland-0", "PATH": "/bin",
                    "GNOME_KEYRING_CONTROL": "/personal/keyring", "GNOME_KEYRING_PID": "99", "SSH_AUTH_SOCK": "/personal/agent"}
        before = original.copy()
        child = gate.private_environment(self.root, original)
        self.assertEqual(original, before)
        self.assertEqual(child["HOME"], str(self.root))
        for name in ("DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "PULSE_SERVER", "WAYLAND_DISPLAY", "GNOME_KEYRING_CONTROL", "GNOME_KEYRING_PID", "SSH_AUTH_SOCK"):
            self.assertNotIn(name, child)
        self.assertEqual(child["PATH"], "/bin")

    def test_real_nonzero_exit_is_retained_and_fails_the_gate(self):
        handle = subprocess.Popen([sys.executable, "-c", "raise SystemExit(7)"])
        app = SimpleNamespace(handle=handle, started_utc="2026-10-02T00:00:00+00:00",
                              identity={"pid": handle.pid, "exe": sys.executable, "start_ticks": 1})
        report = {}
        with self.assertRaisesRegex(RuntimeError, "returncode=7"):
            gate.wait_for_ordinary_exit(app, report, self.root, lambda process: {"core_payload_collected": False})
        retained = json.loads((self.root / "application-exit.json").read_text())
        self.assertEqual(retained["returncode"], 7)
        self.assertEqual(retained["identity"], app.identity)
        self.assertEqual(retained, report["application_exit"])
        self.assertFalse(retained["failure_diagnostics"]["core_payload_collected"])

    def test_native_signal_is_retained_without_accepting_it(self):
        app = SimpleNamespace(handle=SimpleNamespace(pid=12345, wait=lambda timeout: -11),
                              started_utc="2026-10-02T00:00:00+00:00",
                              identity={"pid": 12345, "exe": "/opt/aethertune/aethertune", "start_ticks": 1})
        report = {}
        with self.assertRaisesRegex(RuntimeError, "signal=SIGSEGV"):
            gate.wait_for_ordinary_exit(app, report, self.root, lambda process: {"availability": "not installed"})
        retained = json.loads((self.root / "application-exit.json").read_text())
        self.assertEqual((retained["returncode"], retained["signal_number"], retained["signal_name"]),
                         (-11, 11, "SIGSEGV"))

    def test_zero_exit_is_retained_as_the_only_success(self):
        handle = subprocess.Popen([sys.executable, "-c", "raise SystemExit(0)"])
        app = SimpleNamespace(handle=handle, started_utc="2026-10-02T00:00:00+00:00",
                              identity={"pid": handle.pid, "exe": sys.executable, "start_ticks": 1})
        report = {}
        gate.wait_for_ordinary_exit(app, report, self.root)
        self.assertEqual(report["application_exit"]["returncode"], 0)
        self.assertNotIn("failure_diagnostics", report["application_exit"])

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


class OrdinaryBehaviorTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in ("data", "documents"):
            (self.root / name).mkdir()
        self.media = gate.make_media(self.root)
        self.track = {"id": "known-fixture-😀", "localPath": str(self.media), "title": "owned WAV"}
        self.library = {"aethertune.tracks.v1": json.dumps([self.track]),
                        "aethertune.onboarding_completed.v1": True,
                        "aethertune.desktop_density_preference.v1": "compact",
                        "unrelated-credential-value": "must not appear in evidence"}
        self.player = {"aethertune.player_queue.v1": json.dumps({"tracks": [self.track],
                        "currentTrackId": self.track["id"], "currentIndex": 0})}

    def raw(self, values):
        payload = json.dumps(values)
        return json.dumps({"format": 1, "generation": "a" * 32, "payload": payload,
                           "checksum": hashlib.sha256(payload.encode()).hexdigest()}).encode()

    def save(self):
        for role, values in (("library", self.library), ("player", self.player)):
            directory = self.root / f"data/dev.aethertune/aethertune/{role}"
            directory.mkdir(parents=True, exist_ok=True)
            (directory / "library.json").write_bytes(self.raw(values))

    def test_real_fixture_hash_and_snapshot_metadata_preserve_only_known_predicates(self):
        self.save()
        receipt = gate.state_snapshot(self.root)
        self.assertEqual(set(receipt["files"]), {"library", "player"})
        self.assertTrue(all(value["stable_during_observation"] for value in receipt["files"].values()))
        self.assertEqual(receipt["predicates"]["density"], "compact")
        mpris_path = "/org/mpris/MediaPlayer2/TrackList/" + self.track["id"].encode("utf-16-be").hex()
        self.assertEqual(receipt["predicates"]["fixture_mpris_track_id_sha256"], hashlib.sha256(mpris_path.encode()).hexdigest())
        self.assertNotIn("must not appear", json.dumps(receipt))
        self.assertNotIn(self.track["localPath"], json.dumps(receipt))

    def test_empty_or_checksum_tampered_state_cannot_claim_persistence(self):
        with self.assertRaisesRegex(RuntimeError, "snapshots are absent"):
            gate.state_snapshot(self.root)
        self.save()
        path = self.root / "data/dev.aethertune/aethertune/library/library.json"
        content = json.loads(path.read_bytes())
        content["payload"] = content["payload"].replace("compact", "comfortable")
        path.write_text(json.dumps(content))
        with self.assertRaisesRegex(RuntimeError, "checksum differs"):
            gate.state_snapshot(self.root)

    def test_wrong_queue_or_media_bytes_fail_even_with_valid_envelope(self):
        self.player["aethertune.player_queue.v1"] = json.dumps({"tracks": [self.track], "currentTrackId": "foreign", "currentIndex": 0})
        with self.assertRaisesRegex(RuntimeError, "current track"):
            gate.snapshot_predicates(self.library, self.player, self.root)
        self.media.write_bytes(b"changed")
        with self.assertRaisesRegex(RuntimeError, "owned WAV"):
            gate.snapshot_predicates(self.library, self.player, self.root)

    def test_native_state_role_alias_is_rejected(self):
        self.save()
        directory = self.root / "data/other/library"
        directory.mkdir(parents=True)
        (directory / "library.json").write_bytes(self.raw(self.library))
        with self.assertRaisesRegex(RuntimeError, "Ambiguous"):
            gate.state_snapshot(self.root)

    def test_mount_cleanup_guard_distinguishes_owned_subtree_and_prefix_alias(self):
        owned = Path("/tmp/aethertune-release-fixture-owned")
        info = "1 0 0:1 / /tmp/aethertune-release-fixture-owned/runtime/doc rw - fuse.portal portal rw\n"
        info += "2 0 0:2 / /tmp/aethertune-release-fixture-owned-foreign rw - tmpfs tmpfs rw\n"
        self.assertEqual(gate.mounts_under(owned, info), [{"mountpoint": str(owned / "runtime/doc"), "filesystem": "fuse.portal",
                                                       "mount_id": 1, "device": "0:1", "options": "rw", "source": "portal"}])

    def test_first_phase_nonzero_exit_is_retained_and_does_not_authorize_reopen(self):
        app = SimpleNamespace(handle=SimpleNamespace(pid=42, wait=lambda timeout: 7), started_utc="fixture",
                              identity={"pid": 42, "start_ticks": 1, "exe": "/opt/aethertune/aethertune"})
        report = {}
        with self.assertRaisesRegex(RuntimeError, "returncode=7"):
            gate.wait_for_ordinary_exit(app, report, self.root, lambda process: {}, phase="initial")
        receipt = json.loads((self.root / "application-exit-initial.json").read_text())
        self.assertEqual(receipt, report["application_exits"]["initial"])
        self.assertEqual(receipt["returncode"], 7)
        self.assertNotIn("application_exit", report)

    def test_behavior_requires_provenance_before_any_native_call(self):
        with self.assertRaisesRegex(RuntimeError, "requires verified"):
            gate.behavior_provenance(None, SimpleNamespace(), {}, {})
        path = self.root / "provenance.json"
        path.write_text(json.dumps({"schemaVersion": 1, "status": "PASS"}))
        with self.assertRaisesRegex(RuntimeError, "not verified input"):
            gate.behavior_provenance(path, SimpleNamespace(), {}, {})

    def test_timer_progress_cannot_replace_owned_uncorked_native_output(self):
        identity = {"pid": 42, "start_ticks": 7, "exe": "/opt/aethertune/aethertune"}
        sinks = [{"index": 1, "name": "aethertune_release_fixture", "state": "RUNNING"}]
        stream = {"index": 2, "sink": 1, "corked": False, "sample_specification": "float32le 2ch 44100Hz",
                  "properties": {"application.process.id": "42", "application.process.binary": "aethertune", "unrelated": "secret"}}
        receipt = gate.audio_output_predicate(sinks, [stream], identity)
        self.assertFalse(receipt["corked"])
        self.assertNotIn("secret", json.dumps(receipt))
        inventory = gate.audio_output_inventory(sinks, [dict(stream, corked=True)])
        self.assertTrue(inventory["inputs"][0]["corked"])
        self.assertNotIn("secret", json.dumps(inventory))
        for changed in (dict(stream, corked=True), dict(stream, sink=99), dict(stream, index=True),
                        dict(stream, sample_specification="missing PCM fields"),
                        dict(stream, properties={"application.process.id": "99", "application.process.binary": "aethertune"})):
            with self.assertRaises(RuntimeError):
                gate.audio_output_predicate(sinks, [changed], identity)

    def test_document_helper_exception_rejects_foreign_lineage_uid_argv_binary_or_mount(self):
        binary = self.root / "fusermount3"
        binary.write_bytes(b"owned installed helper predicate fixture")
        parent = {"pid": 41, "start_ticks": 7, "exe": "/usr/libexec/xdg-document-portal"}
        mount = {"mountpoint": str(self.root / "runtime/doc"), "filesystem": "fuse.portal", "source": "portal",
                 "mount_id": 3, "device": "0:2", "options": "rw,nosuid,nodev,relatime"}
        record = {"pid": 42, "start_ticks": 8, "parent_pid": 41, "exe": str(binary), "executable_sha256": gate.file_hash(binary),
                  "parent_identity": parent, "uids": [1001, 0, 0, 0],
                  "argv": ["fusermount3", "-o", "rw,nosuid,nodev,fsname=portal,subtype=portal,auto_unmount", "--", mount["mountpoint"]]}
        self.assertEqual(gate.validate_fuse_helper(record, parent, str(binary), self.root, 1001, mount), record)
        invalid = [dict(record, parent_pid=99), dict(record, parent_identity=dict(parent, start_ticks=6)),
                   dict(record, start_ticks=6), dict(record, uids=[0, 0, 0, 0]), dict(record, exe="/foreign/fusermount3"),
                   dict(record, executable_sha256="f" * 64),
                   dict(record, argv=record["argv"][:-1] + [str(self.root.parent / "foreign")]),
                   dict(record, argv=["fusermount3", "-u", "--", mount["mountpoint"]]),
                   dict(record, argv=["fusermount3", "-o", record["argv"][2] + ",allow_other", "--", mount["mountpoint"]])]
        for changed in invalid:
            with self.subTest(changed=changed), self.assertRaises(RuntimeError):
                gate.validate_fuse_helper(changed, parent, str(binary), self.root, 1001, mount)
        with self.assertRaisesRegex(RuntimeError, "mount identity"):
            gate.validate_fuse_helper(record, parent, str(binary), self.root, 1001, dict(mount, mountpoint=str(self.root.parent / "foreign")))

    def test_reparented_helper_is_still_live_until_the_original_generation_disappears(self):
        record = {"pid": 42, "start_ticks": 8, "parent_pid": 41}
        with patch.object(gate, "process_header", return_value={"pid": 42, "start_ticks": 8, "parent_pid": 1}):
            self.assertTrue(gate.generation_alive(record))
        with patch.object(gate, "process_header", return_value={"pid": 42, "start_ticks": 9, "parent_pid": 1}):
            self.assertFalse(gate.generation_alive(record))
        with patch.object(gate, "process_header", return_value=None):
            self.assertFalse(gate.generation_alive(record))

    def mpris_fixture(self, metadata, can_seek=True, failure=None, foreign_owner=False):
        identity = {"pid": 42, "start_ticks": 7, "exe": "/opt/aethertune/aethertune"}
        app = SimpleNamespace(handle=SimpleNamespace(pid=42, poll=lambda: None), identity=identity)
        track_id = "/org/mpris/MediaPlayer2/TrackList/known_fixture"
        state = {"predicates": {"fixture_mpris_track_id_sha256": hashlib.sha256(track_id.encode()).hexdigest()}}
        bus = object.__new__(gate.PrivateBus)
        bus.GLib = SimpleNamespace(Error=type("RemoteError", (RuntimeError,), {}))
        bus.pid = Mock(side_effect=[42, 99] if foreign_owner else None, return_value=42)
        calls = []
        def call(destination, path, interface, method, signature=None, arguments=()):
            calls.append((method, arguments))
            if method == "Get":
                name = arguments[1]
                if name == failure:
                    raise RuntimeError("owned partial-read boundary")
                return (metadata if name == "Metadata" else can_seek,)
            # Stop after valid metadata without fabricating native transport/output.
            raise RuntimeError("owned transport boundary")
        bus.call = call
        return bus, app, state, identity, track_id, calls

    def test_mpris_duration_or_seek_failure_retains_bounded_observed_values_without_metadata(self):
        secret = "https://foreign.invalid/?credential=must-not-export"
        missing = object()
        cases = [(0, True), (178_999_999, True), (181_000_001, True), (missing, True),
                 (180_000_000, False), (180_000_000, 1), (180_000_000, secret),
                 (secret, True), (float("nan"), True), (float("inf"), True), (2 ** 100, True)]
        for index, (length, can_seek) in enumerate(cases):
            with self.subTest(index=index):
                track_id = "/org/mpris/MediaPlayer2/TrackList/known_fixture"
                metadata = {"mpris:trackid": track_id, "xesam:url": secret, "foreign": {"credential": secret}}
                if length is not missing:
                    metadata["mpris:length"] = length
                bus, app, state, identity, _, calls = self.mpris_fixture(metadata, can_seek)
                with patch.object(gate, "process_identity", return_value=identity), self.assertRaises((RuntimeError, TypeError)):
                    gate.mpris_behavior(bus, app, state, self.root, "initial", {})
                receipt = json.loads((self.root / "mpris-initial.json").read_text())
                self.assertEqual(receipt["result"], "FAIL")
                self.assertEqual(receipt["samples"], [])
                observed = receipt["metadata_observations"][-1]
                self.assertTrue(observed["fixture_track_match"])
                self.assertTrue(observed["metadata_read"])
                self.assertTrue(observed["length"]["read"])
                self.assertEqual(observed["length"]["present"], length is not missing)
                self.assertTrue(observed["can_seek"]["read"])
                self.assertIn("metadata_observed_utc", observed)
                self.assertIn("can_seek_observed_utc", observed)
                if length is missing:
                    self.assertEqual(observed["length"]["type"], "absent")
                elif type(length) is int and -(2 ** 63) <= length <= 2 ** 63 - 1:
                    self.assertEqual(observed["length"]["value"], length)
                else:
                    self.assertIsNone(observed["length"]["value"])
                    self.assertFalse(observed["length"]["value_supported"])
                self.assertNotIn(secret, json.dumps(receipt))
                self.assertNotIn(track_id, json.dumps(receipt))
                self.assertEqual([arguments[1] for method, arguments in calls], ["Metadata", "CanSeek"])

    def test_mpris_partial_reads_or_changed_owner_preserve_failure_receipt_before_transport(self):
        track_id = "/org/mpris/MediaPlayer2/TrackList/known_fixture"
        metadata = {"mpris:trackid": track_id, "mpris:length": 180_000_000}
        for failure, foreign_owner in (("Metadata", False), ("CanSeek", False), (None, True)):
            with self.subTest(failure=failure, foreign_owner=foreign_owner):
                bus, app, state, identity, _, calls = self.mpris_fixture(metadata, failure=failure, foreign_owner=foreign_owner)
                with patch.object(gate, "process_identity", return_value=identity), self.assertRaises(RuntimeError):
                    gate.mpris_behavior(bus, app, state, self.root, "initial", {})
                receipt = json.loads((self.root / "mpris-initial.json").read_text())
                self.assertEqual(receipt["result"], "FAIL")
                observed = receipt["metadata_observations"][-1]
                self.assertEqual(observed["metadata_read"], failure == "CanSeek")
                self.assertFalse(observed["can_seek"]["read"])
                if failure == "CanSeek":
                    self.assertEqual(observed["length"]["value"], 180_000_000)
                    self.assertTrue(observed["fixture_track_match"])
                self.assertTrue(all(method == "Get" for method, arguments in calls))
                if foreign_owner:
                    self.assertEqual(calls, [])

    def test_valid_mpris_metadata_retains_observations_before_existing_transport_boundary(self):
        track_id = "/org/mpris/MediaPlayer2/TrackList/known_fixture"
        bus, app, state, identity, _, calls = self.mpris_fixture({"mpris:trackid": track_id, "mpris:length": 180_000_000})
        with patch.object(gate, "process_identity", return_value=identity), self.assertRaisesRegex(RuntimeError, "transport boundary"):
            gate.mpris_behavior(bus, app, state, self.root, "initial", {})
        receipt = json.loads((self.root / "mpris-initial.json").read_text())
        self.assertEqual(receipt["result"], "FAIL")
        self.assertEqual(receipt["fixture_track_id_sha256"], state["predicates"]["fixture_mpris_track_id_sha256"])
        observed = receipt["metadata_observations"][-1]
        self.assertEqual(observed["length"]["value"], 180_000_000)
        self.assertEqual(observed["length"]["type"], "int")
        self.assertIs(observed["can_seek"]["value"], True)
        self.assertEqual(observed["can_seek"]["type"], "bool")
        self.assertEqual([method for method, arguments in calls], ["Get", "Get", "Pause"])

    def test_glib_runtimeerror_subclass_retries_only_actual_missing_remote_name(self):
        class RemoteError(RuntimeError):
            def __init__(self, remote):
                super().__init__("deliberately not the protocol name")
                self.remote = remote
        bus = object.__new__(gate.PrivateBus)
        bus.GLib = SimpleNamespace(Error=RemoteError)
        bus.Gio = SimpleNamespace(DBusError=SimpleNamespace(is_remote_error=lambda error: error.remote is not None,
                                                           get_remote_error=lambda error: error.remote))
        identity = {"pid": 42, "start_ticks": 7, "exe": "/usr/libexec/at-spi2-registryd"}
        process = SimpleNamespace(handle=SimpleNamespace(pid=42, poll=lambda: None), identity=identity)
        with patch.object(gate, "process_identity", return_value=identity), patch.object(gate.time, "sleep"):
            bus.pid = Mock(side_effect=[RemoteError("org.freedesktop.DBus.Error.NameHasNoOwner"), 42])
            self.assertEqual(bus.wait_owner("org.a11y.atspi.Registry", process)["identity"], identity)
            self.assertEqual(bus.pid.call_count, 2)
            bus.pid = Mock(return_value=99)
            with self.assertRaisesRegex(RuntimeError, "owner differs"):
                bus.wait_owner("org.a11y.atspi.Registry", process)
            self.assertEqual(bus.pid.call_count, 1)
            for remote in (None, "org.freedesktop.DBus.Error.AccessDenied", "org.freedesktop.DBus.Error.NoReply"):
                bus.pid = Mock(side_effect=RemoteError(remote))
                with self.assertRaises(RemoteError):
                    bus.wait_owner("org.a11y.atspi.Registry", process)
                self.assertEqual(bus.pid.call_count, 1)
            # Even a string resembling the remote name is not an API identity.
            bus.pid = Mock(side_effect=RuntimeError("org.freedesktop.DBus.Error.NameHasNoOwner"))
            with self.assertRaises(RuntimeError):
                bus.wait_owner("org.a11y.atspi.Registry", process)
            self.assertEqual(bus.pid.call_count, 1)
            bus.pid = Mock(side_effect=RemoteError("org.freedesktop.DBus.Error.NameHasNoOwner"))
            with patch.object(gate.time, "monotonic", side_effect=[0, 0.1, 0.2, 1.1]), \
                 self.assertRaisesRegex(RuntimeError, "did not acquire"):
                bus.wait_owner("org.a11y.atspi.Registry", process, timeout=1)
            self.assertEqual(bus.pid.call_count, 1)

    def test_rebound_harness_and_original_product_are_independently_checked(self):
        checkout = self.root / "checkout"
        drivers = {}
        for name in ("scripts/ci/linux_packaged_release_acceptance.py", "scripts/ci/linux_release_ui_acceptance.py",
                     "scripts/ci/prepare_linux_release_behavior.py", ".github/workflows/linux-release-behavior.yml"):
            path = checkout / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"bound harness")
            drivers[name] = gate.file_hash(path)
        args = SimpleNamespace(version="0.1.0", bundle=self.root / "bundle", deb=self.root / "app.deb", tarball=self.root / "app.tar.gz")
        env = {"GITHUB_REPOSITORY": "Yunushan/aethertune", "GITHUB_SHA": "b" * 40, "GITHUB_REF": "refs/heads/codex/behavior",
               "GITHUB_RUN_ID": "12", "GITHUB_RUN_ATTEMPT": "1"}
        receipt = {"schemaVersion": 1, "status": "verified-input", "product": {
            "repository": "Yunushan/aethertune", "sourceCommit": gate.PRODUCT_COMMIT, "sourceRef": gate.PRODUCT_REF,
            "runId": 37136816470, "runAttempt": 1, "version": "0.1.0",
            "artifact": {"id": 11279990421, "name": "aethertune-release-bundle", "outerSha256": "8359e6c5f62a6afcb13931fb4c8f20fcdc35f9d6c249f228cb4f3b59b1b98065"},
            "linux": {"debSha256": gate.PRODUCT_DEB, "tarballSha256": gate.PRODUCT_TAR, "executableSha256": gate.PRODUCT_EXE, "bundleEntries": 43},
            "certificate": {"subjectAlternativeName": f"https://github.com/Yunushan/aethertune/.github/workflows/aethertune-release.yml@{gate.PRODUCT_REF}",
                "issuer": "https://token.actions.githubusercontent.com", "buildSignerDigest": gate.PRODUCT_COMMIT,
                "sourceRepositoryDigest": gate.PRODUCT_COMMIT, "sourceRepositoryRef": gate.PRODUCT_REF,
                "runnerEnvironment": "github-hosted", "runInvocationURI": "https://github.com/Yunushan/aethertune/actions/runs/37136816470/attempts/1"}},
            "executor": {"repository": env["GITHUB_REPOSITORY"], "sourceCommit": "b" * 40, "triggerSha": env["GITHUB_SHA"],
                "ref": env["GITHUB_REF"], "runId": 12, "runAttempt": 1, "driverHashes": drivers},
            "paths": {name: str(getattr(args, name).resolve()) for name in ("bundle", "deb", "tarball")}}
        bundle = {"aethertune": {"sha256": gate.PRODUCT_EXE}, **{str(i): {} for i in range(42)}}
        hashes = {"deb": gate.PRODUCT_DEB, "tarball": gate.PRODUCT_TAR}
        path = self.root / "provenance.json"
        def verify():
            path.write_text(json.dumps(receipt))
            return gate.behavior_provenance(path, args, hashes, bundle, env)
        with patch.object(gate, "__file__", str(checkout / "scripts/ci/linux_packaged_release_acceptance.py")), \
             patch.object(gate, "run", return_value=SimpleNamespace(stdout="b" * 40 + "\n")):
            self.assertEqual(verify()["product"]["sourceCommit"], gate.PRODUCT_COMMIT)
            receipt["product"]["sourceCommit"] = "b" * 40
            with self.assertRaisesRegex(RuntimeError, "Original product identity"):
                verify()
            receipt["product"]["sourceCommit"] = gate.PRODUCT_COMMIT
            receipt["executor"]["driverHashes"]["scripts/ci/linux_release_ui_acceptance.py"] = "f" * 64
            with self.assertRaisesRegex(RuntimeError, "driver hash differs"):
                verify()


if __name__ == "__main__":
    unittest.main()
