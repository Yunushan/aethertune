#!/usr/bin/env python3
"""Observe/action the ordinary installed release on an owned Linux desktop.

Uses the real AT-SPI tree, GTK portal chooser and X11 keyboard events. No app
test entrypoint, seeded app storage, portal mock or coordinate fallback exists.
The coordinator owns launch, normal WM_DELETE, reopen and all service cleanup.
Portable predicate tests are not native acceptance evidence.
"""
from __future__ import annotations

import argparse
import ctypes as C
from datetime import datetime, timezone
import faulthandler
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import time

from linux_packaged_release_acceptance import X11, file_hash, process_identity, require, write_json

DESTINATIONS = ("Home", "Library", "Playlists", "History", "Sources", "Options")
MAX_NODES, MAX_DEPTH = 1800, 48
OBSERVER_SECONDS, TRACEBACK_SECONDS, MAX_CHECKPOINTS = 150, 30, 128
SCROLL_ACTIONS = frozenset(("ScrollLeft", "ScrollRight", "ScrollUp", "ScrollDown", "ShowOnScreen"))
MAX_ONBOARDING_REVEALS = 4
ONBOARDING_LABELS = frozenset(("Welcome to AetherTune", "Set up a local library", "Explore legal sources",
                              "Connect your music server", "Privacy first"))
# Pinned Flutter semantics names finger motion: a normal, nonreversed vertical
# ListView advances via ScrollUp (ScrollPosition._updateSemanticActions).
FORWARD_LIST_ACTION = "ScrollUp"


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def checkpoint(args, report, label):
    # Fixed stage names only: no accessible text, arguments, locals or memory.
    item = {"utc": timestamp(), "monotonic": time.monotonic(), "label": label}
    report["checkpoint_count"] = report.get("checkpoint_count", 0) + 1
    history = report.setdefault("checkpoints", [])
    if len(history) < MAX_CHECKPOINTS:
        history.append(item)
    report["last_checkpoint"] = item
    progress = {"schema_version": 1, "result": "IN_PROGRESS", "phase": args.phase,
                "checkpoint_count": report["checkpoint_count"], "last_checkpoint": item}
    path = args.evidence / f"behavior-{args.phase}-progress.json"
    with path.open("w", encoding="utf-8") as output:
        json.dump(progress, output, sort_keys=True)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())
    print(json.dumps(progress, sort_keys=True), file=sys.stderr, flush=True)


def load_atspi():
    import gi
    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi, GLib
    return Atspi, GLib


def unique(items, purpose):
    require(len(items) == 1, f"Expected exactly one {purpose}; observed {len(items)}")
    return items[0]


def name_line(name, label):
    return label in name.splitlines()


def available(node):
    return {"VISIBLE", "SHOWING"} <= set(node["states"]) and "DEFUNCT" not in node["states"]


def supports_unset_enabled(node, action):
    # This original custom label wraps InkWell without enabled semantics. The
    # caller still uniquely matches the actual owned-media title before acting.
    prefix = "Open now playing for "
    return action in SCROLL_ACTIONS or (action == "Tap" and node["name"].startswith(prefix)
                                       and bool(node["name"][len(prefix):].strip()))


def actionable(node, action):
    exposed = available(node) or (action == "ShowOnScreen" and "DEFUNCT" not in node["states"])
    # Pinned Flutter Linux maps is_enabled=None to neither SENSITIVE nor
    # ENABLED; False to SENSITIVE only; True to both. Scroll semantics do not
    # set is_enabled. Accept their observed capability without treating an
    # explicitly disabled control as enabled. Other Tap/seek require ENABLED.
    enabled = "ENABLED" in node["states"] or (supports_unset_enabled(node, action) and "SENSITIVE" not in node["states"])
    return exposed and action in node["actions"] and enabled


def elapsed_seconds(name):
    match = re.fullmatch(r"Elapsed time (\d+):([0-5]\d)", name)
    require(match is not None, "Malformed elapsed-time semantics")
    return int(match[1]) * 60 + int(match[2])


def selected_destination(nodes, destination):
    candidates = [n for n in nodes if available(n) and name_line(n["name"], destination)
                  and "Tap" in n["actions"]]
    chosen = unique(candidates, f"navigation destination {destination}")
    require("SELECTED" in chosen["states"], f"Destination {destination} is not selected")
    selected = [n for n in nodes if available(n) and "SELECTED" in n["states"]
                and "Tap" in n["actions"] and any(name_line(n["name"], d) for d in DESTINATIONS)]
    require(len(selected) == 1, "Ambiguous selected navigation state")
    return chosen


def descendant(node, ancestor):
    return node["path"][:len(ancestor["path"])] == ancestor["path"]


def onboarding_target(nodes):
    skip = [n for n in nodes if name_line(n["name"], "Skip setup")]
    require(len(skip) <= 1, "Ambiguous onboarding Skip setup control")
    if skip:
        chosen = skip[0]
        require("DEFUNCT" not in chosen["states"] and not (
            "SENSITIVE" in chosen["states"] and "ENABLED" not in chosen["states"]),
            "Onboarding Skip setup control is disabled or defunct")
        for action in ("Tap", "ShowOnScreen"):
            if actionable(chosen, action):
                return chosen, action
    # The ListView can omit its offscreen final button. Bind a real scroll
    # capability to two distinct visible headings/cards from exact English l10n.
    scrolls = []
    for candidate in nodes:
        if not actionable(candidate, FORWARD_LIST_ACTION):
            continue
        labels = {label for child in nodes if child["path"] != candidate["path"]
                  and descendant(child, candidate) and available(child)
                  for label in ONBOARDING_LABELS if name_line(child["name"], label)}
        if len(labels) >= 2:
            scrolls.append(candidate)
    return unique(scrolls, f"onboarding {FORWARD_LIST_ACTION} container bound to visible setup labels"), FORWARD_LIST_ACTION


def seek_slider(nodes):
    elapsed = unique([n for n in nodes if available(n) and n["name"].startswith("Elapsed time ")],
                     "visible elapsed-time label")
    elapsed_seconds(elapsed["name"])
    # Choose the nearest observed ancestor that contains the real elapsed and
    # remaining labels and exactly one actionable slider. This excludes volume.
    for length in range(len(elapsed["path"]) - 1, 0, -1):
        prefix = elapsed["path"][:length]
        scope = [n for n in nodes if n["path"][:length] == prefix]
        if not any(available(n) and n["name"].startswith("Remaining time ") for n in scope):
            continue
        sliders = [n for n in scope if n["role"] == "slider" and actionable(n, "Increase")]
        if len(sliders) == 1:
            return sliders[0]
    raise RuntimeError("No unambiguous seek slider bound to elapsed/remaining labels")


def private_bus_address(address, fixture):
    # Multiple endpoints can silently fall back to an unrelated desktop bus.
    require(isinstance(address, str) and ";" not in address and address.startswith("unix:path="),
            "Desktop bus must be a single owned filesystem socket")
    socket = PurePosixPath(address[len("unix:path="):].split(",", 1)[0])
    root = PurePosixPath(fixture.as_posix()) / "runtime"
    require(socket.is_absolute() and ".." not in socket.parts and socket.is_relative_to(root), "Desktop bus socket is outside owned runtime")


def valid_pause_samples(paused, samples, duration):
    require(duration >= 2 and len(samples) >= 3 and all(type(value) is int for value in samples),
            "Pause stability lacks bounded elapsed samples")
    require(all(abs(value - paused) <= 1 for value in samples), "UI elapsed advanced while paused")


class NativeKeys(X11):
    def __init__(self):
        super().__init__()
        signatures = {
            "XSetInputFocus": (C.c_int, [C.c_void_p, C.c_ulong, C.c_int, C.c_ulong]),
            "XGetInputFocus": (C.c_int, [C.c_void_p, C.POINTER(C.c_ulong), C.POINTER(C.c_int)]),
            "XRaiseWindow": (C.c_int, [C.c_void_p, C.c_ulong]),
            "XStringToKeysym": (C.c_ulong, [C.c_char_p]),
            "XKeysymToKeycode": (C.c_uint, [C.c_void_p, C.c_ulong]),
        }
        for name, (restype, argtypes) in signatures.items():
            function = getattr(self.lib, name)
            function.restype, function.argtypes = restype, argtypes
        self.xtst = C.CDLL("libXtst.so.6")
        self.xtst.XTestFakeKeyEvent.restype = C.c_int
        self.xtst.XTestFakeKeyEvent.argtypes = [C.c_void_p, C.c_uint, C.c_int, C.c_ulong]

    def windows(self, pid, title, bound=None):
        found, pending, count = [], [self.lib.XDefaultRootWindow(self.display)], 0
        while pending:
            if bound is not None:
                bound()
            window = pending.pop()
            count += 1
            require(count <= 2048, "Private window inventory exceeds bound")
            if self.property(window, "_NET_WM_PID") == [pid]:
                attributes = self.attributes(window)
                value = self.property(window, "_NET_WM_NAME") or self.property(window, "WM_NAME")
                if attributes.map_state == 2 and isinstance(value, bytes) and title.casefold() in value.decode("utf-8", "replace").casefold():
                    found.append(window)
            root, parent, children, size = C.c_ulong(), C.c_ulong(), C.POINTER(C.c_ulong)(), C.c_uint()
            if self.lib.XQueryTree(self.display, window, C.byref(root), C.byref(parent), C.byref(children), C.byref(size)):
                pending.extend(children[:size.value])
            if children:
                self.lib.XFree(children)
            if bound is not None:
                bound()
        return found

    def assert_focus(self, window, identity):
        require(process_identity(identity["pid"]) == identity, "Keyboard target process identity changed")
        require(self.property(window, "_NET_WM_PID") == [identity["pid"]], "Keyboard target window PID mismatch")
        focus, revert = C.c_ulong(), C.c_int()
        self.lib.XGetInputFocus(self.display, C.byref(focus), C.byref(revert))
        require(focus.value == window, "Native keyboard focus changed from the exact owned window")
        require(not self.errors, "Private X11 keyboard encountered a protocol error")

    def chord(self, window, identity, key, modifiers=(), may_close=False):
        require(process_identity(identity["pid"]) == identity, "Refusing changed native keyboard target")
        require(self.property(window, "_NET_WM_PID") == [identity["pid"]], "Refusing unbound native keyboard window")
        self.lib.XRaiseWindow(self.display, window)
        self.lib.XSetInputFocus(self.display, window, 2, 0)
        self.lib.XSync(self.display, 0)
        pressed = []
        try:
            for symbol in (*modifiers, key):
                self.assert_focus(window, identity)
                code = self.lib.XKeysymToKeycode(self.display, self.lib.XStringToKeysym(symbol.encode("ascii")))
                require(code > 0, f"Key {symbol} is absent from the actual X11 keyboard map")
                require(self.xtst.XTestFakeKeyEvent(self.display, code, 1, 0), "Native key press failed")
                pressed.append(code)
                self.lib.XSync(self.display, 0)
        finally:
            # Release every key pressed by this owned private-display observer,
            # even if a target disappears. Never leave a latched modifier.
            released = []
            for code in reversed(pressed):
                released.append(bool(self.xtst.XTestFakeKeyEvent(self.display, code, 0, 0)))
            self.lib.XSync(self.display, 0)
            require(all(released), "Native key release failed")
        if not may_close:
            self.assert_focus(window, identity)


class Observer:
    def __init__(self, args, report):
        self.args, self.report = args, report
        self.app, self.portal = json.loads(args.identity), json.loads(args.portal_identity)
        # Establish this before importing/initializing potentially blocking native
        # libraries. The coordinator still owns the separate 180-second child bound.
        self.deadline = time.monotonic() + OBSERVER_SECONDS
        self.last_tree, self.window, self.x11 = [], None, None
        self.checkpoint("before GI import")
        self.bound()
        self.atspi, self.glib = load_atspi()
        self.bound()
        self.checkpoint("before AT-SPI timeout configuration")
        self.remote(self.atspi.set_timeout, 1500, 4000)
        self.checkpoint("before AT-SPI client initialization")
        require(self.remote(self.atspi.init) == 0, "Cannot initialize the private AT-SPI client")
        self.checkpoint("before native X11 setup")
        self.x11 = self.remote(NativeKeys)
        self.checkpoint("native observer initialized")

    def checkpoint(self, label):
        checkpoint(self.args, self.report, label)

    def remote(self, function, *args):
        # A node can need many remote calls. Bound each call rather than letting
        # the rest of a traversal continue after one consumes the phase budget.
        self.bound()
        result = function(*args)
        self.bound()
        return result

    def windows(self, identity, title):
        self.bound()
        return self.x11.windows(identity["pid"], title, bound=self.bound)

    def bound(self):
        require(time.monotonic() < self.deadline, "Native observer exceeded its overall bound")
        for identity in (self.app, self.portal):
            require(process_identity(identity["pid"]) == identity, "Owned app/portal process identity changed")

    def record(self, kind, label, **value):
        self.report[kind].append({"utc": timestamp(), "monotonic": time.monotonic(), "label": label, **value})

    def tree(self, identity=None):
        self.bound()
        identity = identity or self.app
        self.checkpoint("before semantic tree GLib context")
        context = self.remote(self.glib.MainContext.default)
        for _ in range(32):
            if not self.remote(context.pending):
                break
            self.remote(context.iteration, False)
        self.checkpoint("before semantic tree desktop lookup")
        desktop = self.remote(self.atspi.get_desktop, 0)
        self.checkpoint("before semantic tree application discovery")
        roots = []
        desktop_count = self.remote(desktop.get_child_count)
        require(0 <= desktop_count <= MAX_NODES, "Invalid accessibility desktop child count")
        for index in range(desktop_count):
            app = self.remote(desktop.get_child_at_index, index)
            self.remote(app.clear_cache)
            if self.remote(app.get_process_id) == identity["pid"]:
                roots.append(app)
        root = unique(roots, "AT-SPI application with exact owned PID")
        # libatspi membership calls refresh remotely unless STATES can be
        # marked cached. Invalidate each node below before its fresh read, then
        # inspect that native state snapshot locally; other metadata stays uncached.
        self.remote(root.set_cache_mask, self.atspi.Cache.STATES)
        self.checkpoint("before semantic tree node traversal")
        pending, nodes = [(root, ())], []
        while pending:
            accessible, path = pending.pop()
            self.bound()
            require(len(nodes) < MAX_NODES and len(path) <= MAX_DEPTH, "Accessibility tree exceeds bound")
            self.remote(accessible.clear_cache_single)
            require(self.remote(accessible.get_process_id) == identity["pid"], "Accessibility node belongs to another process")
            states = self.remote(accessible.get_state_set)
            flags = [name for name in ("VISIBLE", "SHOWING", "ENABLED", "SENSITIVE", "SELECTED", "FOCUSED", "EDITABLE", "DEFUNCT")
                     if self.remote(states.contains, getattr(self.atspi.StateType, name))]
            action = self.remote(accessible.get_action_iface)
            action_count = self.remote(action.get_n_actions) if action else 0
            require(0 <= action_count <= 32, "Accessibility action count exceeds bound")
            names = [self.remote(action.get_action_name, i) for i in range(action_count)]
            name = self.remote(accessible.get_name) or ""
            require(len(name) <= 2048, "Accessibility metadata exceeds bound")
            node = {"path": path, "name": name, "role": self.remote(accessible.get_role_name), "states": flags,
                    "actions": names, "accessible": accessible}
            nodes.append(node)
            child_count = self.remote(accessible.get_child_count)
            require(0 <= child_count <= MAX_NODES, "Invalid accessibility child count")
            for index in reversed(range(child_count)):
                pending.append((self.remote(accessible.get_child_at_index, index), path + (index,)))
        self.bound()
        self.last_tree = [self.describe(n) for n in nodes]
        self.checkpoint("semantic tree traversal completed")
        return nodes

    @staticmethod
    def describe(node):
        return {key: value for key, value in node.items() if key != "accessible"}

    def wait(self, predicate, label, seconds=15):
        deadline, last = min(time.monotonic() + seconds, getattr(self, "deadline", float("inf"))), None
        while time.monotonic() < deadline:
            try:
                result = predicate()
                if result is not None and result is not False:
                    self.record("observations", label)
                    return result
            except Exception as error:
                last = str(error)
            time.sleep(0.25)
        raise RuntimeError(f"Timed out waiting for {label}: {last or 'predicate remained false'}")

    def find(self, label, action="Tap", identity=None, predicate=None):
        nodes = self.tree(identity)
        matches = [n for n in nodes if actionable(n, action) and
                   (predicate(n, nodes) if predicate else name_line(n["name"], label))]
        return unique(matches, f"fresh actionable {label}")

    def act(self, label, action="Tap", identity=None, predicate=None):
        # Resolve immediately before action; never reuse an accessible from an
        # earlier navigation state or a saved tree dump.
        node = self.find(label, action, identity, predicate)
        self.bound()
        accessible = node["accessible"]
        accessible.clear_cache_single()
        require(accessible.get_process_id() == (identity or self.app)["pid"], "Action PID binding changed")
        require(accessible.get_name() == node["name"], "Action semantic label changed")
        states = accessible.get_state_set()
        enabled = states.contains(self.atspi.StateType.ENABLED) or (
            supports_unset_enabled(node, action) and not states.contains(self.atspi.StateType.SENSITIVE))
        require(enabled and not states.contains(self.atspi.StateType.DEFUNCT),
                "Action state changed to disabled or defunct")
        if action != "ShowOnScreen":
            require(states.contains(self.atspi.StateType.VISIBLE) and states.contains(self.atspi.StateType.SHOWING),
                    "Action state changed to hidden")
        interface = accessible.get_action_iface()
        names = [interface.get_action_name(i) for i in range(interface.get_n_actions())]
        index = unique([i for i, name in enumerate(names) if name == action], "observed named action index")
        require(interface.do_action(index), f"Observed {action} action was rejected")
        self.record("actions", label, action=action, target=self.describe(node))

    def capture(self, label, window=None):
        self.bound()
        window = window or self.window
        identity = self.app if window == self.window else self.portal
        require(self.x11.property(window, "_NET_WM_PID") == [identity["pid"]], "Screenshot window PID mismatch")
        path = self.args.evidence / f"behavior-{self.args.phase}-{label}.png"
        value = self.x11.screenshot(window, path)
        value["content_review"] = "required: inspect recorded ordinary UI state"
        self.report["screenshots"][label] = {"path": str(path), "utc": timestamp(), **value}

    def keyboard(self, key, modifiers=(), window=None, identity=None, may_close=False):
        self.bound()
        self.x11.chord(window or self.window, identity or self.app, key, modifiers, may_close=may_close)
        self.record("actions", "native keyboard", key=key, modifiers=list(modifiers), window_xid=window or self.window,
                    expected_window_close=may_close)

    def nav(self, index):
        self.keyboard(str(index + 1), ("Control_L",))
        destination = DESTINATIONS[index]
        node = self.wait(lambda: selected_destination(self.tree(), destination), f"Ctrl+{index+1} selected {destination}")
        self.record("observations", "selected destination", destination=destination, target=self.describe(node))

    def skip_onboarding(self):
        self.wait(lambda: onboarding_target(self.tree()), "ordinary first-launch onboarding", 25)
        for attempt in range(MAX_ONBOARDING_REVEALS + 1):
            target, action = onboarding_target(self.tree())
            # Select again from act's fresh owned-PID tree, then revalidate native
            # identity, state and named action before invoking the capability.
            def still_selected(node, nodes):
                current, current_action = onboarding_target(nodes)
                return current_action == action and node["path"] == current["path"]
            if action == "Tap":
                self.capture("onboarding")
                self.act("Skip setup", predicate=still_selected)
                return
            require(attempt < MAX_ONBOARDING_REVEALS, "Onboarding reveal budget exhausted before actionable Skip setup")
            label = "onboarding Skip setup reveal" if action == "ShowOnScreen" else "onboarding list scroll"
            self.act(label, action, predicate=still_selected)
            time.sleep(0.4)

    def density(self, initial):
        self.nav(5)
        # ShowOnScreen is a real observed accessibility action. If the lazy list
        # has not exposed this row, scroll only its observed Options list.
        for _ in range(4):
            nodes = self.tree()
            controls = [n for n in nodes if actionable(n, "Tap") and name_line(n["name"], "Compact" if not initial else "Comfortable")]
            if controls:
                unique(controls, "desktop density dropdown")
                break
            labels = [n for n in nodes if "Desktop density" in n["name"]]
            show = [n for n in labels if "ShowOnScreen" in n["actions"]]
            if show:
                self.act("Desktop density", "ShowOnScreen", predicate=lambda n, ns:
                         "Desktop density" in n["name"] and n["path"] == unique(show, "density ShowOnScreen")["path"])
            else:
                self.act("Options list scroll", FORWARD_LIST_ACTION, predicate=lambda n, ns: any(
                    descendant(child, n) and name_line(child["name"], "Options") for child in ns))
            time.sleep(0.4)
        if initial:
            self.act("Comfortable")
            self.wait(lambda: self.find("Compact"), "Compact dropdown menu choice")
            self.act("Compact")
        node = self.wait(lambda: self.find("Compact"), "Compact desktop density ordinary setting")
        self.record("observations", "Compact desktop density", target=self.describe(node), restored=not initial)
        self.capture("compact")

    def import_media(self):
        require(file_hash(self.args.media) == self.args.media_sha256, "Owned media changed before ordinary import")
        self.nav(1)
        self.act("Import local audio")
        chooser = self.wait(lambda: unique(self.windows(self.portal, "flutter picker"), "owned real GTK chooser window"),
                            "owned real GTK chooser", 25)
        def dialog_present():
            nodes = self.tree(self.portal)
            return unique([n for n in nodes if available(n) and n["name"] == "flutter picker"
                           and n["role"] in ("file chooser", "dialog")], "real GTK chooser semantics")
        self.wait(dialog_present, "real GTK chooser semantics")
        self.capture("real-chooser", chooser)
        self.keyboard("l", ("Control_L",), chooser, self.portal)
        def location_entry():
            return unique([n for n in self.tree(self.portal) if available(n) and
                           {"FOCUSED", "EDITABLE"} <= set(n["states"]) and n["role"] == "text"],
                          "focused editable real chooser location entry")
        entry = self.wait(location_entry, "focused real GTK location entry")
        self.bound()
        self.x11.assert_focus(chooser, self.portal)
        editable = entry["accessible"].get_editable_text_iface()
        require(editable is not None and editable.set_text_contents(str(self.args.media)), "Real chooser path entry rejected")
        fresh = location_entry()
        text = fresh["accessible"].get_text_iface()
        require(text is not None and text.get_text(0, -1) == str(self.args.media), "Real chooser path entry differs from owned media")
        self.record("actions", "real chooser path entry", target=self.describe(fresh), media_sha256=self.args.media_sha256)
        self.capture("chooser-owned-path", chooser)
        self.keyboard("Return", (), chooser, self.portal, may_close=True)
        self.wait(lambda: not self.windows(self.portal, "flutter picker"), "real chooser closed after ordinary selection")
        self.wait(lambda: self.find("owned imported track", predicate=lambda n, ns:
                                   self.args.media.stem in n["name"] and not n["name"].startswith("Open now playing for ")),
                  "ordinary imported track", 25)
        self.capture("imported-library")

    def elapsed(self):
        node = unique([n for n in self.tree() if available(n) and n["name"].startswith("Elapsed time ")], "elapsed label")
        value = elapsed_seconds(node["name"])
        self.record("observations", "fresh UI elapsed label", seconds=value, target=self.describe(node))
        return value

    def playback(self, initial):
        self.nav(1)
        self.wait(lambda: self.find("owned imported track", predicate=lambda n, ns:
                                   self.args.media.stem in n["name"] and not n["name"].startswith("Open now playing for ")),
                  "owned track present after ordinary reopen" if not initial else "owned imported track present")
        if initial:
            self.act("owned imported track", predicate=lambda n, ns: self.args.media.stem in n["name"]
                     and not n["name"].startswith("Open now playing for "))
        open_player = lambda n, ns: n["name"].startswith("Open now playing for ") and self.args.media.stem in n["name"]
        self.wait(lambda: self.find("current owned track", predicate=open_player), "current owned track metadata")
        self.act("current owned track", predicate=open_player)
        self.wait(self.elapsed, "full now playing elapsed label")
        if not initial:
            self.act("Play")
        self.wait(lambda: self.find("Pause"), "native playback Pause control")
        before = self.elapsed()
        progressed = self.wait(lambda: self.elapsed() if self.elapsed() >= before + 2 else False,
                               "ordinary UI elapsed progresses by two seconds", 12)
        self.record("observations", "UI playback progression", before=before, after=progressed)
        self.capture("playing")
        self.act("Pause")
        self.wait(lambda: self.find("Play"), "ordinary UI paused Play control")
        paused = self.elapsed()
        pause_start = time.monotonic()
        samples = []
        while time.monotonic() - pause_start < 2.25:
            samples.append(self.elapsed())
            self.find("Play")
            time.sleep(0.25)
        pause_duration = time.monotonic()-pause_start
        valid_pause_samples(paused, samples, pause_duration)
        self.record("observations", "UI pause stability", elapsed=paused, samples=samples, duration_seconds=pause_duration)
        self.capture("paused")
        if initial:
            self.act("observed seek slider", "Increase", predicate=lambda n, ns: n["path"] == seek_slider(ns)["path"])
            after = self.wait(lambda: self.elapsed() if self.elapsed() >= paused + 5 else False,
                              "actual seek action advances UI elapsed", 10)
            self.record("observations", "UI seek", before=paused, after=after)
            self.capture("seeked")
            self.act("Play")
            self.wait(lambda: self.find("Pause"), "playback resumes after seek")
            self.wait(lambda: self.elapsed() >= after + 2, "elapsed progresses after seek", 12)
            self.act("Pause")
            self.wait(lambda: self.find("Play"), "playback paused for independent coordinator audit")
            self.capture("after-seek-paused")

    def run(self):
        self.checkpoint("before ordinary app window discovery")
        self.window = self.wait(lambda: unique(self.windows(self.app, "aethertune"), "ordinary app window"),
                                "ordinary app window", 25)
        self.report["window_xid"] = self.window
        require(self.x11.attributes(self.window).width >= 900, "Ordinary app window is too narrow for desktop shortcuts")
        self.checkpoint("before first semantic tree/native calls")
        initial = self.args.phase == "initial"
        if initial:
            self.skip_onboarding()
            self.wait(lambda: selected_destination(self.tree(), "Home"), "ordinary onboarding finished at Home")
            for index in (1, 2, 3, 4, 5, 0):
                self.nav(index)
                self.capture(f"ctrl-{index+1}-{DESTINATIONS[index].lower()}")
            for key, destination in (("Left", "Options"), ("Right", "Home")):
                self.keyboard(key, ("Alt_L",))
                self.wait(lambda: selected_destination(self.tree(), destination), f"Alt+{key} wraps to {destination}")
                self.capture(f"alt-{key.lower()}")
        else:
            self.wait(lambda: self.find("Import local audio"), "ordinary reopened home shell", 25)
            require(not any(available(n) and name_line(n["name"], "Skip setup") for n in self.tree()),
                    "Onboarding reappeared on ordinary same-profile reopen")
            self.capture("reopened-shell")
        self.density(initial)
        if initial:
            self.import_media()
        self.playback(initial)
        self.bound()
        require(file_hash(self.args.media) == self.args.media_sha256, "Owned media changed during ordinary acceptance")
        self.tree()
        write_json(self.args.evidence / f"behavior-{self.args.phase}-final-tree.json", self.last_tree)

    def close(self):
        self.x11.lib.XCloseDisplay(self.x11.display)
        self.atspi.exit()


def validate_inputs(args):
    require(args.phase in ("initial", "reopen"), "Unsupported observer phase")
    for value in (args.identity, args.portal_identity):
        identity = json.loads(value)
        require(set(identity) == {"pid", "start_ticks", "exe"} and type(identity["pid"]) is int and identity["pid"] > 1
                and type(identity["start_ticks"]) is int and identity["start_ticks"] > 0
                and isinstance(identity["exe"], str) and identity["exe"].startswith("/"), "Malformed owned process identity")
    require(json.loads(args.identity)["pid"] == args.pid and args.pid != json.loads(args.portal_identity)["pid"],
            "Observer app/portal PID binding mismatch")
    require(re.fullmatch(r"[0-9a-f]{64}", args.media_sha256) is not None, "Invalid media digest")
    require(args.media.is_absolute() and not args.media.is_symlink() and args.media.is_file(), "Owned media must be an absolute regular file")
    require(file_hash(args.media) == args.media_sha256, "Owned media digest changed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("initial", "reopen"), required=True)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--portal-identity", required=True)
    parser.add_argument("--media", type=Path, required=True)
    parser.add_argument("--media-sha256", required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    report = {"schema_version": 1, "result": "FAIL", "phase": args.phase, "started_utc": timestamp(),
              "app_identity": None, "portal_identity": None,
              "observations": [], "actions": [], "screenshots": {},
              "scope": "ordinary release; native Linux keyboard/GTK picker; synthetic PCM; same-profile reopen",
              "excluded": ["physical audio", "screen-reader usability", "production trust", "versioned upgrade"],
              "screenshot_review": "required"}
    observer, diagnostics_started = None, False
    try:
        require(sys.platform == "linux" and os.environ.get("GITHUB_ACTIONS") == "true", "Hosted Linux execution required")
        fixture = Path(os.environ["HOME"])
        require(fixture.parent == Path("/tmp") and fixture.name.startswith("aethertune-release-fixture-")
                and not fixture.is_symlink() and (fixture / ".owned-release-fixture").read_text() == "aethertune-linux-release-v1\n",
                "Observer requires coordinator-owned private fixture")
        for key in ("DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS", "AT_SPI_BUS_ADDRESS"):
            require(os.environ.get(key), f"Private desktop prerequisite missing: {key}")
        require(re.fullmatch(r":\d+(?:\.\d+)?", os.environ["DISPLAY"]) is not None, "Private local X11 display required")
        authority = Path(os.environ["XAUTHORITY"])
        require(authority.is_absolute() and authority.resolve().is_relative_to(fixture.resolve()), "Xauthority outside owned fixture")
        for key in ("DBUS_SESSION_BUS_ADDRESS", "AT_SPI_BUS_ADDRESS"):
            private_bus_address(os.environ[key], fixture)
        require(args.media.resolve().is_relative_to(fixture.resolve()), "Media is outside the owned private fixture")
        require(args.evidence.is_absolute() and args.evidence.is_dir() and not args.evidence.is_symlink(), "Invalid evidence directory")
        validate_inputs(args)
        report.update(app_identity=json.loads(args.identity), portal_identity=json.loads(args.portal_identity))
        report["media"] = {"path": str(args.media), "sha256": args.media_sha256, "size": args.media.stat().st_size}
        checkpoint(args, report, "before native diagnostics")
        # Only stack frames go to the current owned stderr. No locals are dumped;
        # repeat lifetime is bounded by this phase and the coordinator's child wait.
        faulthandler.dump_traceback_later(TRACEBACK_SECONDS, repeat=True, file=sys.stderr, exit=False)
        diagnostics_started = True
        observer = Observer(args, report)
        observer.run()
        report["result"] = "PASS"
    except Exception as error:
        report["error"] = str(error)
        if observer is not None:
            write_json(args.evidence / f"behavior-{args.phase}-failure-tree.json", observer.last_tree)
            try:
                observer.capture("failure")
            except Exception as capture_error:
                report["failure_capture_error"] = str(capture_error)
    finally:
        try:
            if observer is not None:
                observer.checkpoint("before native observer close")
                observer.close()
        finally:
            if diagnostics_started:
                faulthandler.cancel_dump_traceback_later()
            report["finished_utc"] = timestamp()
            write_json(args.evidence / f"behavior-{args.phase}.json", report)
    print(json.dumps({"result": report["result"], "phase": args.phase, "error": report.get("error")}))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
