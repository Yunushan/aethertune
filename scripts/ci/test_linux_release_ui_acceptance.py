#!/usr/bin/env python3
"""Portable rejection guards; these fixtures never establish native UI acceptance."""
import ctypes as C
from contextlib import redirect_stderr
import hashlib
from io import StringIO
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import linux_release_ui_acceptance as ui


def node(path, name="", role="panel", states=("VISIBLE", "SHOWING", "ENABLED"), actions=()):
    return {"path": tuple(path), "name": name, "role": role, "states": list(states), "actions": list(actions)}


# Exact 36-node ordinary native failure tree, run37134370976/artifact11278660508.
# Captured executor d4a9db4; raw tree SHA256 d5e035e4b9ac74b09715b4732a502318ad28891a3b8cf4a80f75f11eec8e1d1d.
# This retained observation is not a positive native action result.
ACTUAL_ONBOARDING_TREE_SHA256 = '09c30142ab45ccdbc537b5cc4beae647895efbf3a352a522f5082959c99993d3'
ACTUAL_ONBOARDING_TREE_JSON = r'''[
{"actions": [], "name": "dev.aethertune.aethertune", "path": [], "role": "application", "states": []},
{"actions": [], "name": "aethertune", "path": [0], "role": "frame", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE", "FOCUSED"]},
{"actions": [], "name": "", "path": [0, 0, 0], "role": "filler", "states": []},
{"actions": [], "name": "", "path": [0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING", "FOCUSED"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["ScrollUp"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "AetherTune", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "Welcome to AetherTune", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "Start with music you control, or choose a legal source. You can change every choice later in Options.", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "Set up a local library\nImport audio files or a folder, then keep watched folders in sync while the app is open.", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Import audio", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "Explore legal sources\nAdd podcast RSS feeds, browse Radio Browser, Internet Archive, or connect your own supported media server.", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Open Sources", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "Connect your music server\nAdd a Jellyfin or Navidrome / Subsonic library using a secure, tested connection.", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Connect server", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11], "role": "panel", "states": ["SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12], "role": "panel", "states": ["SHOWING"]},
{"actions": [], "name": "Privacy first\nAetherTune has no telemetry. Network providers disclose the domains they contact before use.", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0], "role": "panel", "states": ["SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Start at Home", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 12, 0, 0], "role": "push button", "states": ["SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 13], "role": "panel", "states": ["SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 14], "role": "panel", "states": ["SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Skip setup", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 14, 0], "role": "push button", "states": ["SHOWING", "ENABLED", "SENSITIVE"]}
]'''


class ObserverGuards(unittest.TestCase):
    def test_actual_36_node_onboarding_tree_selects_forward_scroll_without_hidden_tap(self):
        nodes = json.loads(ACTUAL_ONBOARDING_TREE_JSON)
        canonical = json.dumps(nodes, sort_keys=True, separators=(",", ":")).encode()
        self.assertEqual(hashlib.sha256(canonical).hexdigest(), ACTUAL_ONBOARDING_TREE_SHA256)
        self.assertEqual(len(nodes), 36)
        skip = ui.unique([n for n in nodes if n["name"] == "Skip setup"], "captured Skip setup")
        self.assertEqual(set(skip["states"]), {"SHOWING", "ENABLED", "SENSITIVE"})
        self.assertFalse(ui.actionable(skip, "Tap"))
        self.assertNotIn("ShowOnScreen", skip["actions"])
        target, action = ui.onboarding_target(nodes)
        self.assertEqual(target["path"], [0] * 11)
        self.assertEqual(target["actions"], ["ScrollUp"])
        self.assertEqual(action, "ScrollUp")
        # The backward action is not a permitted substitute for forward reveal.
        wrong_direction = [dict(n, actions=["ScrollDown"]) if n is target else n for n in nodes]
        with self.assertRaises(RuntimeError):
            ui.onboarding_target(wrong_direction)

    def test_density_requests_observed_forward_scroll_bound_to_options_list(self):
        observer = object.__new__(ui.Observer)
        advanced, actions = [False], []
        scroll = node((0, 0), states=("VISIBLE", "SHOWING"), actions=("ScrollUp",))
        title = node((0, 0, 0), "Options")
        compact = node((0, 0, 1), "Compact", actions=("Tap",))
        unrelated = node((0, 1), states=("VISIBLE", "SHOWING"), actions=("ScrollUp",))
        observer.nav = lambda index: self.assertEqual(index, 5)
        observer.tree = lambda identity=None: [scroll, title, unrelated] + ([compact] if advanced[0] else [])
        def act(label, action="Tap", identity=None, predicate=None):
            self.assertEqual((label, action), ("Options list scroll", "ScrollUp"))
            self.assertTrue(ui.actionable(scroll, action))
            self.assertTrue(predicate(scroll, observer.tree()))
            self.assertFalse(predicate(unrelated, observer.tree()))
            actions.append(action)
            advanced[0] = True
        observer.act = act
        observer.find = lambda label: ui.unique([n for n in observer.tree()
            if ui.actionable(n, "Tap") and ui.name_line(n["name"], label)], "model density control")
        observer.wait = lambda predicate, label: predicate()
        observer.record = lambda *args, **kwargs: None
        observer.capture = lambda label: self.assertEqual(label, "compact")
        with patch.object(ui.time, "sleep"):
            observer.density(initial=False)
        self.assertEqual(actions, ["ScrollUp"])

    def onboarding_model(self, reveal_action="ShowOnScreen", required_reveals=1):
        # Portable model of changing native state/actions; never native acceptance.
        status = {"reveals": 0, "actions": [], "events": [], "trees": 0, "pid": 12, "disabled": False}
        observer = object.__new__(ui.Observer)
        observer.app, observer.deadline = {"pid": 12}, float("inf")
        observer.report = {"actions": [], "observations": []}
        observer.bound = lambda: None
        observer.capture = lambda label: status["events"].append(("capture", label))
        observer.atspi = SimpleNamespace(StateType=SimpleNamespace(**{name: name for name in
            ("VISIBLE", "SHOWING", "ENABLED", "SENSITIVE", "DEFUNCT")}))
        def visible():
            return status["reveals"] >= required_reveals
        def native_states(name):
            if name == "Skip setup":
                flags = {"SENSITIVE"} if status["disabled"] else {"SENSITIVE", "ENABLED"}
                return flags | ({"VISIBLE", "SHOWING"} if visible() else set())
            return {"VISIBLE", "SHOWING"}
        def accessible(value):
            def state_set():
                snapshot = frozenset(native_states(value["name"]))
                status["events"].append(("state", value["name"], snapshot))
                return SimpleNamespace(contains=lambda name: name in snapshot)
            def do_action(index):
                action = value["actions"][index]
                if action == "Tap":
                    self.assertTrue(visible(), "Skip was tapped while still offscreen")
                    self.assertFalse(status["disabled"])
                else:
                    status["reveals"] += 1
                status["actions"].append(action)
                status["events"].append(("action", action))
                return True
            return SimpleNamespace(clear_cache_single=lambda: status["events"].append(("clear", value["name"])),
                get_process_id=lambda: status["pid"], get_name=lambda: value["name"], get_state_set=state_set,
                get_action_iface=lambda: SimpleNamespace(get_n_actions=lambda: len(value["actions"]),
                    get_action_name=lambda index: value["actions"][index], do_action=do_action))
        def tree(identity=None):
            status["trees"] += 1
            values = []
            if reveal_action == "ShowOnScreen" or visible():
                values.append(node((0, 0), "Skip setup", states=native_states("Skip setup"),
                                   actions=("Tap", "ShowOnScreen")))
            if reveal_action == "ScrollUp":
                values.extend([node((0, 1), states=native_states("list"), actions=("ScrollUp",)),
                               node((0, 1, 0), "Explore legal sources"),
                               node((0, 1, 1), "Connect your music server")])
            for value in values:
                value["accessible"] = accessible(value)
            return values
        observer.tree = tree
        return observer, status

    def test_onboarding_hidden_skip_is_revealed_before_strict_tap(self):
        observer, status = self.onboarding_model()
        with patch.object(ui.time, "sleep"):
            observer.skip_onboarding()
        self.assertEqual(status["actions"], ["ShowOnScreen", "Tap"])
        self.assertGreaterEqual(status["trees"], 5)
        self.assertLess(status["events"].index(("action", "ShowOnScreen")),
                        status["events"].index(("capture", "onboarding")))
        self.assertLess(status["events"].index(("capture", "onboarding")),
                        status["events"].index(("action", "Tap")))
        self.assertEqual([event for event in status["events"] if event[0] == "clear"],
                         [("clear", "Skip setup"), ("clear", "Skip setup")])

    def test_onboarding_lazy_skip_uses_only_scoped_observed_scroll(self):
        observer, status = self.onboarding_model("ScrollUp")
        with patch.object(ui.time, "sleep"):
            observer.skip_onboarding()
        self.assertEqual(status["actions"], ["ScrollUp", "Tap"])
        self.assertGreaterEqual(status["trees"], 5)

    def test_onboarding_final_tap_rejects_hidden_duplicate_introduced_during_capture(self):
        observer, status = self.onboarding_model(required_reveals=0)
        original_tree, original_capture = observer.tree, observer.capture
        def capture(label):
            original_capture(label)
            status["duplicate"] = True
        def tree(identity=None):
            values = original_tree(identity)
            if status.get("duplicate"):
                # A nonactionable alias cannot be removed by Tap's visibility
                # filter before the selector checks the whole fresh tree.
                values.append(node((0, 9), "Skip setup", states=("ENABLED",), actions=("Tap",)))
            return values
        observer.capture, observer.tree = capture, tree
        with self.assertRaisesRegex(RuntimeError, "Ambiguous onboarding Skip setup"):
            observer.skip_onboarding()
        self.assertIn(("capture", "onboarding"), status["events"])
        self.assertEqual(status["actions"], [])

    def test_onboarding_rejects_unrelated_ambiguous_and_unusable_reveal_targets(self):
        scroll = node((0, 0), states=("VISIBLE", "SHOWING"), actions=("ScrollUp",))
        headings = [node((0, 0, 0), "Welcome to AetherTune"), node((0, 0, 1), "Set up a local library")]
        self.assertEqual(ui.onboarding_target([scroll, *headings]), (scroll, "ScrollUp"))
        cases = [[], [scroll, node((0, 0, 0), "Options"), node((0, 0, 1), "Library")],
                 [scroll, headings[0]], [scroll, dict(headings[0], path=(0, 0, 2)), headings[0]],
                 [scroll, *[dict(value, path=(0, 1, index)) for index, value in enumerate(headings)]],
                 [dict(scroll, states=["VISIBLE", "SHOWING", "SENSITIVE"]), *headings],
                 [dict(scroll, states=["VISIBLE", "SHOWING", "DEFUNCT"]), *headings],
                 [dict(scroll, states=[]), *headings], [dict(scroll, actions=[]), *headings],
                 [scroll, *headings, dict(scroll, path=(0, 1)),
                  *[dict(value, path=(0, 1, index)) for index, value in enumerate(headings)]],
                 [node((0, 2), "Skip setup", actions=("Tap",)), node((0, 3), "Skip setup", actions=("Tap",))]]
        for values in cases:
            with self.subTest(values=values), self.assertRaises(RuntimeError):
                ui.onboarding_target(values)
        for states in (("SENSITIVE",), ("ENABLED", "DEFUNCT")):
            with self.subTest(states=states), self.assertRaisesRegex(RuntimeError, "disabled or defunct"):
                ui.onboarding_target([node((0, 2), "Skip setup", states=states, actions=("ShowOnScreen",)),
                                      scroll, *headings])

    def test_onboarding_reveal_budget_is_four_actions_without_hidden_tap(self):
        observer, status = self.onboarding_model("ScrollUp", required_reveals=5)
        with patch.object(ui.time, "sleep"), self.assertRaisesRegex(RuntimeError, "reveal budget exhausted"):
            observer.skip_onboarding()
        self.assertEqual(status["actions"], ["ScrollUp"] * ui.MAX_ONBOARDING_REVEALS)
        self.assertNotIn(("capture", "onboarding"), status["events"])

    def test_onboarding_reveal_revalidates_new_ambiguity_identity_and_disabled_state(self):
        observer, status = self.onboarding_model("ScrollUp")
        original_tree = observer.tree
        def changed_tree(identity=None):
            values = original_tree(identity)
            if status["trees"] >= 3:
                values.extend([node((0, 2), states=("VISIBLE", "SHOWING"), actions=("ScrollUp",)),
                               node((0, 2, 0), "Welcome to AetherTune"),
                               node((0, 2, 1), "Set up a local library")])
            return values
        observer.tree = changed_tree
        with self.assertRaisesRegex(RuntimeError, "observed 2"):
            observer.skip_onboarding()
        self.assertEqual(status["actions"], [])
        for changed, message in (({"pid": 13}, "PID binding changed"),
                                 ({"disabled": True}, "disabled or defunct")):
            observer, status = self.onboarding_model()
            found = observer.find("Skip setup", "ShowOnScreen")
            status.update(changed)
            with patch.object(observer, "find", return_value=found), self.assertRaisesRegex(RuntimeError, message):
                observer.act("Skip setup", "ShowOnScreen")
            self.assertEqual(status["actions"], [])

    def test_checkpoint_is_persisted_before_blocking_gi_initialization(self):
        with tempfile.TemporaryDirectory() as directory:
            app = {"pid": 12, "start_ticks": 100, "exe": "/opt/aethertune/aethertune"}
            portal = {"pid": 13, "start_ticks": 101, "exe": "/usr/libexec/xdg-desktop-portal-gtk"}
            args = SimpleNamespace(phase="initial", evidence=Path(directory),
                                   identity=json.dumps(app), portal_identity=json.dumps(portal))
            report, log = {}, StringIO()
            observer = object.__new__(ui.Observer)
            def blocked_import():
                saved = json.loads((args.evidence / "behavior-initial-progress.json").read_text(encoding="utf-8"))
                self.assertEqual(saved["last_checkpoint"]["label"], "before GI import")
                self.assertEqual(saved["result"], "IN_PROGRESS")
                self.assertEqual(observer.deadline, 100 + ui.OBSERVER_SECONDS)
                self.assertIn('"before GI import"', log.getvalue())
                raise RuntimeError("synthetic blocking import boundary")
            with redirect_stderr(log), patch.object(ui.time, "monotonic", return_value=100), \
                    patch.object(ui, "process_identity", side_effect=lambda pid: app if pid == 12 else portal), \
                    patch.object(ui, "load_atspi", side_effect=blocked_import), \
                    patch.object(ui.os, "fsync", wraps=ui.os.fsync) as synced:
                with self.assertRaisesRegex(RuntimeError, "blocking import"):
                    observer.__init__(args, report)
                synced.assert_called_once()
            self.assertEqual(report["last_checkpoint"]["label"], "before GI import")
            self.assertIsNone(observer.x11)

    def test_tree_stops_between_remote_calls_when_phase_budget_is_consumed(self):
        # A slow get_name must prevent the subsequent role/child remote calls,
        # even on the first node. Checking only once per node permits them.
        with tempfile.TemporaryDirectory() as directory:
            app, portal = {"pid": 12}, {"pid": 13}
            clock, calls = [0], []
            def slow_name():
                calls.append("name")
                clock[0] = 4
                return "owned application"
            root = SimpleNamespace(clear_cache=lambda: None, clear_cache_single=lambda: None,
                get_process_id=lambda: 12, set_cache_mask=lambda mask: None,
                get_state_set=lambda: SimpleNamespace(contains=lambda state: False),
                get_action_iface=lambda: None, get_name=slow_name,
                get_role_name=lambda: calls.append("role") or "frame", get_child_count=lambda: 0)
            desktop = SimpleNamespace(get_child_count=lambda: 1, get_child_at_index=lambda index: root)
            observer = object.__new__(ui.Observer)
            observer.args = SimpleNamespace(phase="initial", evidence=Path(directory))
            observer.report, observer.app, observer.portal = {}, app, portal
            observer.deadline, observer.last_tree = 3, []
            observer.glib = SimpleNamespace(MainContext=SimpleNamespace(default=lambda: SimpleNamespace(pending=lambda: False)))
            observer.atspi = SimpleNamespace(get_desktop=lambda index: desktop, Cache=SimpleNamespace(STATES=1),
                StateType=SimpleNamespace(**{key: key for key in ("VISIBLE", "SHOWING", "ENABLED", "SENSITIVE",
                                                                "SELECTED", "FOCUSED", "EDITABLE", "DEFUNCT")}))
            with redirect_stderr(StringIO()), patch.object(ui.time, "monotonic", side_effect=lambda: clock[0]), \
                    patch.object(ui, "process_identity", side_effect=lambda pid: app if pid == 12 else portal):
                with self.assertRaisesRegex(RuntimeError, "overall bound"):
                    observer.tree()
            self.assertEqual(calls, ["name"])
            self.assertEqual(observer.last_tree, [])
            saved = json.loads((observer.args.evidence / "behavior-initial-progress.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["last_checkpoint"]["label"], "before semantic tree node traversal")

    def test_checkpoint_history_is_bounded_and_latest_progress_is_flushed(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stderr(StringIO()):
            args, report = SimpleNamespace(phase="initial", evidence=Path(directory)), {}
            for index in range(ui.MAX_CHECKPOINTS + 4):
                ui.checkpoint(args, report, "before semantic tree node traversal")
            self.assertEqual(len(report["checkpoints"]), ui.MAX_CHECKPOINTS)
            self.assertEqual(report["checkpoint_count"], ui.MAX_CHECKPOINTS + 4)
            saved = json.loads((args.evidence / "behavior-initial-progress.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["checkpoint_count"], ui.MAX_CHECKPOINTS + 4)
            self.assertEqual(saved["last_checkpoint"], report["last_checkpoint"])
            self.assertEqual(set(saved["last_checkpoint"]), {"utc", "monotonic", "label"})
            self.assertNotIn("identity", saved)

    def test_states_only_policy_invalidates_each_snapshot_and_revalidates_action_state(self):
        # Model libatspi's documented STATES bit contract, not a native positive:
        # get_state_set records fresh native flags, and subsequent membership
        # must inspect that snapshot without requiring a remote refresh.
        with tempfile.TemporaryDirectory() as directory, redirect_stderr(StringIO()):
            app, portal = {"pid": 12}, {"pid": 13}
            events, action_calls, policy = [], [], [None]
            class Accessible:
                def __init__(self, name, children=()):
                    self.name, self.children = name, children
                    self.native = {"VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"}
                    self.snapshot, self.invalidated = None, False
                def clear_cache(self):
                    events.append((self.name, "clear_application"))
                    self.clear_cache_single()
                def clear_cache_single(self):
                    events.append((self.name, "clear_node"))
                    self.snapshot, self.invalidated = None, True
                def set_cache_mask(self, value):
                    events.append((self.name, "mask", value))
                    policy[0] = value
                def get_state_set(self):
                    self_test.assertTrue(self.invalidated, "State read reused an earlier traversal/action snapshot")
                    self_test.assertEqual(policy[0], "states-only")
                    events.append((self.name, "fresh_state"))
                    self.snapshot, self.invalidated = frozenset(self.native), False
                    return self
                def contains(self, value):
                    self_test.assertIsNotNone(self.snapshot, "Membership was evaluated before a fresh native state read")
                    self_test.assertEqual(policy[0], "states-only", "State membership would require another remote refresh")
                    events.append((self.name, "membership", value))
                    return value in self.snapshot
                def get_process_id(self):
                    return 12
                def get_name(self):
                    return self.name
                def get_role_name(self):
                    return "application" if self.children else "push button"
                def get_child_count(self):
                    return len(self.children)
                def get_child_at_index(self, index):
                    return self.children[index]
                def get_action_iface(self):
                    if self.children:
                        return None
                    return SimpleNamespace(get_n_actions=lambda: 1, get_action_name=lambda index: "Tap",
                                           do_action=lambda index: action_calls.append(index) or True)
            self_test = self
            button = Accessible("Play")
            root = Accessible("owned application", [button])
            desktop = SimpleNamespace(get_child_count=lambda: 1, get_child_at_index=lambda index: root)
            observer = object.__new__(ui.Observer)
            observer.args = SimpleNamespace(phase="initial", evidence=Path(directory))
            observer.report = {"actions": [], "observations": []}
            observer.app, observer.portal, observer.deadline, observer.last_tree = app, portal, 150, []
            observer.glib = SimpleNamespace(MainContext=SimpleNamespace(default=lambda: SimpleNamespace(pending=lambda: False)))
            observer.atspi = SimpleNamespace(get_desktop=lambda index: desktop,
                Cache=SimpleNamespace(NONE="none", STATES="states-only", ALL="all"),
                StateType=SimpleNamespace(**{key: key for key in ("VISIBLE", "SHOWING", "ENABLED", "SENSITIVE",
                                                                "SELECTED", "FOCUSED", "EDITABLE", "DEFUNCT")}))
            with patch.object(ui.time, "monotonic", return_value=0), \
                    patch.object(ui, "process_identity", side_effect=lambda pid: app if pid == 12 else portal):
                first = unique_button(observer.tree())
                self.assertTrue(ui.actionable(first, "Tap"))
                button.native.remove("ENABLED")
                second = unique_button(observer.tree())
                self.assertNotIn("ENABLED", second["states"])
                self.assertIn("SENSITIVE", second["states"])
                self.assertFalse(ui.actionable(second, "Tap"))
                # Simulate a real change after find and before action validation.
                button.native.add("ENABLED")
                before_race = unique_button(observer.tree())
                button.native.remove("ENABLED")
                with patch.object(observer, "find", return_value=before_race):
                    with self.assertRaisesRegex(RuntimeError, "disabled or defunct"):
                        observer.act("Play")
            self.assertEqual(action_calls, [])
            self.assertEqual([event[2] for event in events if event[1] == "mask"], ["states-only"] * 3)
            for name in ("owned application", "Play"):
                operations = [event[1] for event in events if event[0] == name]
                for index, operation in enumerate(operations):
                    if operation == "fresh_state":
                        self.assertEqual(operations[index-1], "clear_node")
            self.assertEqual([event for event in events if event[:2] == ("Play", "fresh_state")], [("Play", "fresh_state")] * 4)

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
                         actions=("ScrollUp", "ScrollDown", "ShowOnScreen", "Tap", "Increase", "Decrease"))
        disabled = dict(undefined, states=["VISIBLE", "SHOWING", "SENSITIVE"])
        enabled = dict(undefined, states=["VISIBLE", "SHOWING", "SENSITIVE", "ENABLED"])
        for action in ("ScrollUp", "ScrollDown", "ShowOnScreen"):
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


def unique_button(nodes):
    return ui.unique([value for value in nodes if value["name"] == "Play"], "fixture button")


if __name__ == "__main__":
    unittest.main()
