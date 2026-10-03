#!/usr/bin/env python3
"""Portable rejection guards; these fixtures never establish native UI acceptance."""
import ctypes as C
import hashlib
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import linux_release_ui_acceptance as ui


def node(path, name="", role="panel", states=("VISIBLE", "SHOWING", "ENABLED"), actions=()):
    return {"path": tuple(path), "name": name, "role": role, "states": list(states), "actions": list(actions)}


class ObserverGuards(unittest.TestCase):
    def test_navigation_uses_actual_selected_semantics_and_rejects_aliases(self):
        home = node((0, 1), "Home\nTab 1 of 6", states=("VISIBLE", "SHOWING", "ENABLED", "SELECTED"), actions=("Tap",))
        library = node((0, 2), "Library\nTab 2 of 6", actions=("Tap",))
        self.assertIs(ui.selected_destination([home, library], "Home"), home)
        with self.assertRaisesRegex(RuntimeError, "not selected"):
            ui.selected_destination([home, library], "Library")
        alias = dict(home, path=(0, 3))
        with self.assertRaisesRegex(RuntimeError, "exactly one"):
            ui.selected_destination([home, alias], "Home")
        heading = node((0, 4), "Home", role="heading")
        self.assertIs(ui.selected_destination([home, heading], "Home"), home)

    def test_seek_is_scoped_to_elapsed_remaining_and_excludes_volume(self):
        seek = node((0, 2, 0), role="slider", actions=("Increase", "Decrease"))
        elapsed = node((0, 2, 1, 0), "Elapsed time 0:09")
        remaining = node((0, 2, 1, 1), "Remaining time 2:51")
        volume = node((0, 3, 0), role="slider", actions=("Increase", "Decrease"))
        self.assertIs(ui.seek_slider([seek, elapsed, remaining, volume]), seek)
        with self.assertRaisesRegex(RuntimeError, "unambiguous"):
            ui.seek_slider([seek, elapsed, volume])
        with self.assertRaisesRegex(RuntimeError, "unambiguous"):
            ui.seek_slider([seek, elapsed, remaining, dict(seek, path=(0, 2, 2))])

    def test_hidden_and_defunct_nodes_cannot_trigger_ui_mutation(self):
        hidden = node((0,), "Play", states=("ENABLED",), actions=("Tap", "ShowOnScreen"))
        self.assertFalse(ui.actionable(hidden, "Tap"))
        self.assertTrue(ui.actionable(hidden, "ShowOnScreen"))
        self.assertFalse(ui.actionable(dict(hidden, states=["ENABLED", "DEFUNCT"]), "ShowOnScreen"))
        self.assertFalse(ui.actionable(node((0,), "Play", states=("VISIBLE", "SHOWING"), actions=("Tap",)), "Tap"))

    def test_elapsed_requires_observed_formatter_not_invented_slider_value(self):
        self.assertEqual(ui.elapsed_seconds("Elapsed time 2:59"), 179)
        for label in ("Elapsed time 0:60", "2:59", "Elapsed time -0:01", "Elapsed time 2:59 of 3:00"):
            with self.subTest(label=label), self.assertRaises(RuntimeError):
                ui.elapsed_seconds(label)

    def test_scroll_undefined_enabled_state_differs_from_explicitly_disabled(self):
        # Actual pinned fl_accessible_node.cc mapping: None -> neither flag;
        # False -> SENSITIVE only; True -> SENSITIVE and ENABLED.
        undefined = node((0,), "Options list", states=("VISIBLE", "SHOWING"),
                         actions=("ScrollDown", "ShowOnScreen", "Tap", "Increase", "Decrease"))
        disabled = dict(undefined, states=["VISIBLE", "SHOWING", "SENSITIVE"])
        enabled = dict(undefined, states=["VISIBLE", "SHOWING", "SENSITIVE", "ENABLED"])
        for action in ("ScrollDown", "ShowOnScreen"):
            self.assertTrue(ui.actionable(undefined, action))
            self.assertFalse(ui.actionable(disabled, action))
            self.assertTrue(ui.actionable(enabled, action))
            self.assertFalse(ui.actionable(dict(undefined, actions=[]), action))
            self.assertFalse(ui.actionable(dict(undefined, states=["DEFUNCT"]), action))
        for action in ("Tap", "Increase", "Decrease"):
            self.assertFalse(ui.actionable(undefined, action))
            self.assertFalse(ui.actionable(disabled, action))
            self.assertTrue(ui.actionable(enabled, action))
        hidden = dict(undefined, states=[])
        self.assertFalse(ui.actionable(hidden, "ScrollDown"))
        self.assertTrue(ui.actionable(hidden, "ShowOnScreen"))
        self.assertFalse(ui.actionable(dict(hidden, states=["SENSITIVE"]), "ShowOnScreen"))

    def test_only_observed_custom_current_track_tap_allows_unset_enabled(self):
        control = node((0,), "Open now playing for owned-track\nowned-track\nUnknown artist",
                       states=("VISIBLE", "SHOWING"), actions=("Tap", "Increase", "Decrease"))
        self.assertTrue(ui.actionable(control, "Tap"))
        for changed in (dict(control, states=["VISIBLE", "SHOWING", "SENSITIVE"]),
                        dict(control, states=["VISIBLE", "SHOWING", "DEFUNCT"]),
                        dict(control, states=[]), dict(control, actions=[]),
                        dict(control, name="Play"), dict(control, name="Open now playing for ")):
            with self.subTest(control=changed):
                self.assertFalse(ui.actionable(changed, "Tap"))
        self.assertFalse(ui.actionable(control, "Increase"))
        self.assertFalse(ui.actionable(control, "Decrease"))

    def test_pause_rejects_progression_and_inadequate_observation(self):
        ui.valid_pause_samples(9, [9, 9, 10, 9], 2.1)
        for samples, duration in (([9, 10, 11], 2.1), ([9], 2.1), ([9, 9, 9], 0.1), ([9, 9, "9"], 2.1)):
            with self.subTest(samples=samples), self.assertRaises(RuntimeError):
                ui.valid_pause_samples(9, samples, duration)

    def test_private_bus_refuses_host_fallback_or_other_socket(self):
        fixture = Path("/tmp/aethertune-release-fixture-owned")
        ui.private_bus_address("unix:path=/tmp/aethertune-release-fixture-owned/runtime/a11y,guid=abc", fixture)
        for address in ("unix:path=/run/user/1000/bus", "unix:abstract=host", "tcp:host=localhost,port=123",
                        "unix:path=/tmp/aethertune-release-fixture-owned/runtime/a11y;unix:path=/run/user/1000/bus"):
            with self.subTest(address=address), self.assertRaises(RuntimeError):
                ui.private_bus_address(address, fixture)

    def test_identity_and_media_digest_reject_stale_or_mixed_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            media = Path(directory) / "owned.wav"
            media.write_bytes(b"owned synthetic media")
            identity = {"pid": 12, "start_ticks": 100, "exe": "/opt/aethertune/aethertune"}
            portal = {"pid": 13, "start_ticks": 101, "exe": "/usr/libexec/xdg-desktop-portal-gtk"}
            args = SimpleNamespace(phase="initial", pid=12, identity=json.dumps(identity), portal_identity=json.dumps(portal),
                                   media=media.resolve(), media_sha256=hashlib.sha256(media.read_bytes()).hexdigest())
            ui.validate_inputs(args)
            args.pid = 13
            with self.assertRaisesRegex(RuntimeError, "PID binding"):
                ui.validate_inputs(args)
            args.pid = 12
            media.write_bytes(b"changed after binding")
            with self.assertRaisesRegex(RuntimeError, "digest changed"):
                ui.validate_inputs(args)
            args.media_sha256 = "g" * 64
            with self.assertRaisesRegex(RuntimeError, "Invalid media digest"):
                ui.validate_inputs(args)

    def test_native_focus_identity_guard_prevents_cross_process_input(self):
        identity = {"pid": 12, "start_ticks": 100, "exe": "/opt/aethertune/aethertune"}
        fake = object.__new__(ui.NativeKeys)
        fake.display, fake.errors = 1, []
        fake.property = lambda window, name: [12]
        def focused(display, result, revert):
            C.cast(result, C.POINTER(C.c_ulong)).contents.value = 99
        fake.lib = SimpleNamespace(XGetInputFocus=focused)
        with patch.object(ui, "process_identity", return_value=identity):
            fake.assert_focus(99, identity)
            with self.assertRaisesRegex(RuntimeError, "focus changed"):
                fake.assert_focus(100, identity)
            fake.property = lambda window, name: [13]
            with self.assertRaisesRegex(RuntimeError, "PID mismatch"):
                fake.assert_focus(99, identity)
        with patch.object(ui, "process_identity", return_value=dict(identity, start_ticks=101)):
            with self.assertRaisesRegex(RuntimeError, "identity changed"):
                fake.assert_focus(99, identity)

    def test_missing_or_ambiguous_fresh_control_never_invokes_action(self):
        observer = object.__new__(ui.Observer)
        observer.app = {"pid": 12}
        observer.tree = lambda identity=None: [node((0,), "Play", actions=("Tap",)), node((1,), "Play", actions=("Tap",))]
        with self.assertRaisesRegex(RuntimeError, "exactly one"):
            observer.act("Play")
        observer.tree = lambda identity=None: []
        with self.assertRaisesRegex(RuntimeError, "observed 0"):
            observer.act("Play")


if __name__ == "__main__":
    unittest.main()
