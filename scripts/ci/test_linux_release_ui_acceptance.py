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


# Exact 14-node ordinary density popup, run37139369194/artifact11279933109.
# Raw SHA256 fd1918dc9efeb40382f28c8d21793a5b03c0b7c417c300bdd8da0dc7448ff7c8.
# This captured failed wait does not establish a native Compact action result.
ACTUAL_DENSITY_POPUP_SHA256 = '8684763d7739a2fa183682f2165c572b14f0739d5447c10d5f59b304c3683feb'
ACTUAL_DENSITY_POPUP_JSON = r'''[
{"actions": [], "name": "dev.aethertune.aethertune", "path": [], "role": "application", "states": []},
{"actions": [], "name": "aethertune", "path": [0], "role": "frame", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE", "FOCUSED"]},
{"actions": [], "name": "", "path": [0, 0, 0], "role": "filler", "states": []},
{"actions": [], "name": "", "path": [0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "Popup menu", "path": [0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Comfortable", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "FOCUSED"]},
{"actions": ["Tap", "Focus"], "name": "Compact", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], "role": "push button", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 1], "role": "panel", "states": ["VISIBLE", "SHOWING"]}
]'''
ACTUAL_DENSITY_OPENING_JSON = r'''{"actions": ["Tap", "Focus"], "name": "Desktop density\nChoose how much space desktop controls and lists use.\nComfortable", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 9], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]}'''


# Exact chooser/text projection from the retained 141-node GTK failure tree,
# run37141589677/artifact11280965116, raw SHA256 662bce30991a5b0850c6161e543c221d34af4bffc460a87bdbce9126a757a3da.
# It records the API failure, not a positive import or native path-read result.
ACTUAL_CHOOSER_PROJECTION_JSON = r'''[{"actions": [], "name": "flutter picker", "path": [0], "role": "file chooser", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]}, {"actions": ["activate"], "name": "", "path": [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0], "role": "text", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE", "FOCUSED", "EDITABLE"]}, {"actions": ["activate"], "name": "", "path": [0, 1, 0, 2], "role": "text", "states": ["VISIBLE", "ENABLED", "SENSITIVE", "EDITABLE"]}, {"actions": ["activate"], "name": "", "path": [0, 2, 0, 2], "role": "text", "states": ["VISIBLE", "ENABLED", "SENSITIVE", "EDITABLE"]}]'''
ACTUAL_CHOOSER_PROJECTION_SHA256 = '327222d704ba1480307ee115cec30146095ef430e1eec1f540521c962c64c6b5'
ACTUAL_CHOOSER_ERROR = 'Atspi.Accessible.get_text() takes exactly 1 argument (3 given)'
ACTUAL_IMPORT_BUTTON_JSON = r'''{"actions": ["Tap", "Focus"], "name": "Import local audio", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]}'''


# Exact 74-node ordinary imported Library failure, run37142897399/artifact11281330985.
# Raw tree SHA256 401ce78854145bba43811fdbe5ca80a88bf04b1aa7447c816d61b11564365e68.
# Real chooser closed; this retained observation does not prove track playback.
ACTUAL_IMPORTED_LIBRARY_SHA256 = '43158228eb35a23bfc55797653dda39e868abd6c7c7f463849ba2b14469ab37a'
ACTUAL_IMPORTED_LIBRARY_JSON = r'''[
{"actions": [], "name": "dev.aethertune.aethertune", "path": [], "role": "application", "states": []},
{"actions": [], "name": "aethertune", "path": [0], "role": "frame", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE", "FOCUSED"]},
{"actions": [], "name": "", "path": [0, 0, 0], "role": "filler", "states": []},
{"actions": [], "name": "", "path": [0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["ScrollLeft", "ScrollRight", "Focus"], "name": "No track playing. Import local audio to start.\nQueue\nNothing is playing.\n0 tracks\nQueue tracks appear here.", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING", "FOCUSED"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "AetherTune", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "role": "header", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Import local audio", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": ["Tap", "Focus"], "name": "Import audio folder", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": ["Tap", "Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Home\nTab 1 of 6", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Library\nTab 2 of 6", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1], "role": "panel", "states": ["VISIBLE", "SHOWING", "SELECTED"]},
{"actions": ["Tap", "Focus"], "name": "Playlists\nTab 3 of 6", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 2], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "History\nTab 4 of 6", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 3], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Sources\nTab 5 of 6", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 4], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Options\nTab 6 of 6", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 5], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2], "role": "push button", "states": ["VISIBLE", "SHOWING", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3], "role": "push button", "states": ["VISIBLE", "SHOWING", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4], "role": "push button", "states": ["VISIBLE", "SHOWING", "SENSITIVE"]},
{"actions": ["Tap", "Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "DidGainAccessibilityFocus", "DidLoseAccessibilityFocus", "Focus"], "name": "Search title, artist, album, or genre", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0], "role": "text", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE", "EDITABLE"]},
{"actions": ["Tap", "Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 1], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": ["Tap", "Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 2], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": ["Tap", "Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 3], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": ["Tap", "Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 4], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": ["Tap", "Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 5], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["ScrollLeft"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "aethertune-linux-behavior-180s", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 1], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 2], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Local Folder", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 2, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 3], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 4], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "documents", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 4, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 5], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 6], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Unknown Genre", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 6, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 7], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 8], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "local", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 8, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 9], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 10], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "/tmp/aethertune-release-fixture-_4_9nhg4/documents", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6, 0, 10, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Artists", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 1], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 2], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Albums", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 2, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 3], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 4], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Genres", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 4, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 5], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 6], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Sources", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 6, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 7], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 8], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "Folders", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 8, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 9], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": [], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0], "role": "panel", "states": ["VISIBLE", "SHOWING"]},
{"actions": ["Tap", "Focus"], "name": "aethertune-linux-behavior-180s\nLocal Folder \u00b7 documents \u00b7 Unknown Genre", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]},
{"actions": ["Tap", "Focus"], "name": "", "path": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0], "role": "push button", "states": ["VISIBLE", "SHOWING", "ENABLED", "SENSITIVE"]}
]'''


class ObserverGuards(unittest.TestCase):
    def chooser_model(self, media):
        # Model the GI overload on one Accessible object implementing Text.
        # Real import_media/find/act/keyboard run; no GTK process/input is used.
        state = {"open": False, "imported": False, "written": None, "readback": None, "events": [],
                 "generation": 0, "edit_generation": None, "missing_text": False, "missing_editable": False,
                 "edit_rejected": False, "fresh_change": None, "owned": True, "lose_owner_after_write": False,
                 "focus": True, "captures": []}
        observer = object.__new__(ui.Observer)
        observer.app, observer.portal = {"pid": 12}, {"pid": 4867, "start_ticks": 8406, "exe": "/usr/libexec/xdg-desktop-portal-gtk"}
        observer.window, observer.deadline = 99, float("inf")
        observer.args = SimpleNamespace(media=media, media_sha256=hashlib.sha256(media.read_bytes()).hexdigest())
        observer.report = {"actions": [], "observations": []}
        observer.bound = lambda: ui.require(state["owned"], "Owned portal process identity changed")
        observer.nav = lambda index: self.assertEqual(index, 1)
        observer.wait = lambda predicate, label, *args: predicate()
        observer.capture = lambda label, window=None: state["captures"].append(label)
        self_test = self
        class Text:
            @staticmethod
            def get_text(obj, start, end):
                self.assertIsInstance(obj, Accessible)
                self.assertEqual((start, end), (0, -1))
                self.assertGreater(obj.generation, state["edit_generation"], "Path verification reused the pre-write accessible")
                state["events"].append(("Text.get_text", obj.generation, start, end))
                return state["readback"] if state["readback"] is not None else state["written"]
        class Accessible(Text):
            def __init__(self, value, generation):
                self.value, self.generation = value, generation
            # Accessible's zero-offset accessor shadows Text.get_text in GI.
            # Calling obj.get_text(0,-1) therefore raises the observed arity class.
            def get_text(self):
                return self
            def get_text_iface(self):
                state["events"].append(("get_text_iface", self.generation))
                return None if state["missing_text"] else self
            def get_editable_text_iface(self):
                return None if state["missing_editable"] else self
            def set_text_contents(self, value):
                state["events"].append(("set_text_contents", self.generation, value))
                if state["edit_rejected"]:
                    return False
                state["written"], state["edit_generation"] = value, self.generation
                if state["lose_owner_after_write"]:
                    state["owned"] = False
                return True
            def clear_cache_single(self):
                state["events"].append(("clear", self.value["name"]))
            def get_process_id(self):
                return 12
            def get_name(self):
                return self.value["name"]
            def get_state_set(self):
                flags = frozenset(self.value["states"])
                return SimpleNamespace(contains=lambda name: name in flags)
            def get_action_iface(self):
                names = self.value["actions"]
                def action(index):
                    self_test.assertEqual(names[index], "Tap")
                    if self.value["name"] == "Import local audio":
                        state["open"] = True
                    else:
                        self_test.assertEqual(self.value["name"], f"{media.stem}\nLocal Folder · {media.parent.name} · Unknown Genre")
                        state["events"].append(("track Tap", self.value["name"]))
                    return True
                return SimpleNamespace(get_n_actions=lambda: len(names), get_action_name=lambda i: names[i], do_action=action)
        observer.atspi = SimpleNamespace(Text=Text, StateType=SimpleNamespace(**{name: name for name in
            ("VISIBLE", "SHOWING", "ENABLED", "SENSITIVE", "DEFUNCT")}))
        def tree(identity=None):
            observer.bound()
            state["generation"] += 1
            state["events"].append(("fresh tree", None if identity is None else identity["pid"], state["generation"]))
            if identity is None:
                values = (json.loads(state["imported_json"]) if "imported_json" in state else [
                    node((0,), "Library\nTab 2 of 6", states=("VISIBLE", "SHOWING", "SELECTED"), actions=("Tap", "Focus")),
                    node((1,), f"{media.stem}\nLocal Folder · {media.parent.name} · Unknown Genre",
                         role="push button", actions=("Tap", "Focus"))]) if state["imported"] else [json.loads(ACTUAL_IMPORT_BUTTON_JSON)]
            else:
                self.assertEqual(identity, observer.portal)
                values = json.loads(ACTUAL_CHOOSER_PROJECTION_JSON)
                if state["written"] is not None and state["fresh_change"]:
                    state["fresh_change"](values)
            for value in values:
                value["path"] = tuple(value["path"])
                value["accessible"] = Accessible(value, state["generation"])
            return values
        observer.tree = tree
        def windows(identity, title):
            observer.bound()
            self.assertEqual((identity, title), (observer.portal, "flutter picker"))
            return [4194311] if state["open"] else []
        observer.windows = windows
        def focus(window, identity):
            observer.bound()
            self.assertEqual((window, identity), (4194311, observer.portal))
            ui.require(state["focus"], "Native chooser focus changed")
        def chord(window, identity, key, modifiers=(), may_close=False):
            focus(window, identity)
            state["events"].append(("key", key))
            if key == "Return":
                self.assertTrue(may_close)
                state["open"], state["imported"] = False, True
            else:
                self.assertEqual((key, modifiers), ("l", ("Control_L",)))
        observer.x11 = SimpleNamespace(assert_focus=focus, chord=chord)
        return observer, state

    def test_actual_74_node_import_and_playback_use_unique_full_track_caption(self):
        values = json.loads(ACTUAL_IMPORTED_LIBRARY_JSON)
        canonical = json.dumps(values, sort_keys=True, separators=(",", ":")).encode()
        self.assertEqual(len(values), 74)
        self.assertEqual(hashlib.sha256(canonical).hexdigest(), ACTUAL_IMPORTED_LIBRARY_SHA256)
        with tempfile.TemporaryDirectory() as directory:
            media = Path(directory).resolve() / "documents" / "aethertune-linux-behavior-180s.wav"
            media.parent.mkdir(); media.write_bytes(b"owned portable fixture, not native media acceptance")
            observer, state = self.chooser_model(media)
            state["imported_json"] = ACTUAL_IMPORTED_LIBRARY_JSON
            observer.import_media()
            self.assertIn(("key", "Return"), state["events"])
            self.assertIn("imported-library", state["captures"])
            broad = [n for n in values if ui.actionable(n, "Tap") and media.stem in n["name"]]
            self.assertEqual(len(broad), 2)
            chosen = ui.imported_track_row(values, media)
            self.assertEqual(chosen["path"], [0,0,0,0,0,0,0,0,0,0,8,0,0])
            self.assertNotEqual(chosen["name"], media.stem)
            # Exercise real playback presence/action paths; stop before transport
            # controls rather than manufacture runtime playback acceptance.
            class MetadataBoundary(Exception):
                pass
            def wait(predicate, label, *args):
                if label == "current owned track metadata":
                    raise MetadataBoundary()
                return predicate()
            observer.wait = wait
            with self.assertRaises(MetadataBoundary):
                observer.playback(True)
            self.assertEqual([e for e in state["events"] if e[0] == "track Tap"], [("track Tap", chosen["name"])])
            state["events"].clear()
            with self.assertRaises(MetadataBoundary):
                observer.playback(False)
            self.assertFalse(any(e[0] == "track Tap" for e in state["events"]))

    def test_imported_track_row_rejects_ambiguous_hidden_disabled_or_other_library_context(self):
        media = Path("/owned/documents/aethertune-linux-behavior-180s.wav")
        def row(values):
            return ui.unique([n for n in values if "\nLocal Folder · documents · Unknown Genre" in n["name"]], "captured TrackTile")
        def alias(values, hidden=False):
            duplicate = dict(row(values), path=[0,0,0,0,0,0,0,0,0,0,8,0,1])
            if hidden:
                duplicate["states"] = ["SHOWING", "ENABLED", "SENSITIVE"]
            values.append(duplicate)
        changes = {
            "duplicate row": lambda v: alias(v), "hidden duplicate row": lambda v: alias(v, True),
            "hidden": lambda v: row(v)["states"].remove("VISIBLE"),
            "disabled": lambda v: row(v)["states"].remove("ENABLED"),
            "defunct": lambda v: row(v)["states"].append("DEFUNCT"),
            "wrong role": lambda v: row(v).update(role="panel"),
            "missing Tap": lambda v: row(v)["actions"].remove("Tap"),
            "missing Focus": lambda v: row(v)["actions"].remove("Focus"),
            "different folder": lambda v: row(v).update(name=row(v)["name"].replace("documents", "other")),
            "chip only": lambda v: v.remove(row(v)),
            "Library not selected": lambda v: ui.selected_destination(v, "Library")["states"].remove("SELECTED"),
        }
        for name, change in changes.items():
            with self.subTest(name=name):
                values = json.loads(ACTUAL_IMPORTED_LIBRARY_JSON); change(values)
                with self.assertRaises(RuntimeError):
                    ui.imported_track_row(values, media)

    def test_playback_reselects_track_and_library_context_between_presence_and_tap(self):
        def duplicate(values):
            actual = ui.unique([n for n in values if n["name"].startswith("aethertune-linux-behavior-180s\n")], "row")
            values.append(dict(actual, path=[0,0,0,0,0,0,0,0,0,0,8,0,1], states=["SHOWING", "ENABLED", "SENSITIVE"]))
        def lose_library(values):
            ui.selected_destination(values, "Library")["states"].remove("SELECTED")
        with tempfile.TemporaryDirectory() as directory:
            media = Path(directory).resolve() / "documents" / "aethertune-linux-behavior-180s.wav"
            media.parent.mkdir(); media.write_bytes(b"owned portable fixture")
            for name, change in (("new hidden row alias", duplicate), ("navigation changed", lose_library)):
                with self.subTest(name=name):
                    observer, state = self.chooser_model(media)
                    state.update(imported=True, imported_json=ACTUAL_IMPORTED_LIBRARY_JSON)
                    def wait(predicate, label, *args):
                        self.assertEqual(label, "owned imported track present")
                        result = predicate()
                        values = json.loads(state["imported_json"]);change(values)
                        state["imported_json"] = json.dumps(values)
                        return result
                    observer.wait = wait
                    with self.assertRaises(RuntimeError):
                        observer.playback(True)
                    self.assertFalse(any(e[0] == "track Tap" for e in state["events"]))

    def test_imported_track_immediate_native_revalidation_rejects_changed_pid_name_state_or_tap(self):
        with tempfile.TemporaryDirectory() as directory:
            media = Path(directory).resolve() / "documents" / "aethertune-linux-behavior-180s.wav"
            media.parent.mkdir();media.write_bytes(b"owned portable fixture")
            for kind in ("PID", "name", "disabled", "hidden", "defunct", "missing Tap"):
                with self.subTest(kind=kind):
                    observer, state = self.chooser_model(media)
                    state.update(imported=True, imported_json=ACTUAL_IMPORTED_LIBRARY_JSON)
                    original = observer.find
                    def find(*args, **kwargs):
                        chosen = original(*args, **kwargs)
                        accessible = chosen["accessible"]
                        if kind == "PID":
                            accessible.get_process_id = lambda: 999
                        elif kind == "name":
                            accessible.get_name = lambda: media.stem
                        elif kind == "missing Tap":
                            accessible.get_action_iface = lambda: SimpleNamespace(get_n_actions=lambda: 1,
                                get_action_name=lambda index: "Focus", do_action=lambda index: self.fail("stale action invoked"))
                        else:
                            flags = set(chosen["states"])
                            if kind == "disabled": flags.remove("ENABLED")
                            elif kind == "hidden": flags.remove("VISIBLE")
                            else: flags.add("DEFUNCT")
                            accessible.get_state_set = lambda: SimpleNamespace(contains=lambda name: name in flags)
                        return chosen
                    observer.find = find
                    with self.assertRaises(RuntimeError):
                        observer.act("owned imported track", predicate=lambda n, ns:
                            n["path"] == ui.imported_track_row(ns, media)["path"])
                    self.assertFalse(any(e[0] == "track Tap" for e in state["events"]))

    def test_actual_chooser_text_interface_dispatch_bypasses_accessible_accessor_collision(self):
        projected = json.loads(ACTUAL_CHOOSER_PROJECTION_JSON)
        canonical = json.dumps(projected, sort_keys=True, separators=(",", ":")).encode()
        self.assertEqual(hashlib.sha256(canonical).hexdigest(), ACTUAL_CHOOSER_PROJECTION_SHA256)
        focused = [n for n in projected if n["role"] == "text" and "FOCUSED" in n["states"]]
        self.assertEqual(len(focused), 1)
        self.assertEqual(focused[0]["actions"], ["activate"])
        self.assertEqual(ACTUAL_CHOOSER_ERROR, "Atspi.Accessible.get_text() takes exactly 1 argument (3 given)")
        with tempfile.TemporaryDirectory() as directory:
            media = Path(directory).resolve() / "owned-chooser-180s.wav"
            media.write_bytes(b"owned synthetic unit fixture")
            observer, state = self.chooser_model(media)
            observer.import_media()
            self.assertEqual(state["written"], str(media))
            reads = [event for event in state["events"] if event[0] == "Text.get_text"]
            self.assertEqual(len(reads), 1)
            self.assertEqual(reads[0][2:], (0, -1))
            self.assertGreater(reads[0][1], state["edit_generation"])
            self.assertEqual(state["captures"], ["real-chooser", "chooser-owned-path", "imported-library"])
            self.assertTrue(state["imported"])
            self.assertEqual(observer.report["actions"][-2]["label"], "real chooser path entry")

    def test_chooser_readback_rejects_missing_interfaces_rejected_edit_or_other_media_path_before_return(self):
        with tempfile.TemporaryDirectory() as directory:
            media = Path(directory).resolve() / "owned-chooser.wav"; media.write_bytes(b"owned")
            for name, key, value in (("missing Text", "missing_text", True), ("missing EditableText", "missing_editable", True),
                                     ("rejected edit", "edit_rejected", True), ("different path", "readback", str(media)+".other")):
                with self.subTest(name=name):
                    observer, state = self.chooser_model(media);state[key] = value
                    with self.assertRaises(RuntimeError):
                        observer.import_media()
                    self.assertNotIn(("key", "Return"), state["events"])
                    self.assertFalse(state["imported"])

    def test_chooser_verification_reselects_fresh_focused_owned_entry_and_preserves_native_focus_guard(self):
        def entry(values):
            return ui.unique([n for n in values if n["role"] == "text" and "FOCUSED" in n["states"]], "captured focused entry")
        changes = {
            "lost focus": lambda v: entry(v)["states"].remove("FOCUSED"),
            "hidden": lambda v: entry(v)["states"].remove("VISIBLE"),
            "duplicate": lambda v: v.append(dict(entry(v), path=[99])),
        }
        with tempfile.TemporaryDirectory() as directory:
            media = Path(directory).resolve() / "owned-chooser.wav";media.write_bytes(b"owned")
            for name, change in changes.items():
                with self.subTest(name=name):
                    observer, state = self.chooser_model(media);state["fresh_change"] = change
                    with self.assertRaises(RuntimeError):
                        observer.import_media()
                    self.assertIsNotNone(state["written"])
                    self.assertFalse(any(event[0] == "Text.get_text" for event in state["events"]))
                    self.assertNotIn(("key", "Return"), state["events"])
            for key in ("lose_owner_after_write", "focus"):
                observer, state = self.chooser_model(media);state[key] = key != "focus"
                with self.assertRaises(RuntimeError):
                    observer.import_media()
                self.assertNotIn(("key", "Return"), state["events"])

    def density_model(self):
        # Real observer density/find/act paths against captured semantics and a
        # changing native-call model. No application process/storage is involved.
        observer = object.__new__(ui.Observer)
        status = {"phase": "row", "actions": [], "captures": [], "events": [], "trees": 0,
                  "popup_change": None, "native_states": None, "native_pid": 12,
                  "native_role": "push button", "native_actions": ["Tap", "Focus"],
                  "native_name": "Compact", "keep_popup": False, "opening_change": None}
        observer.app, observer.deadline = {"pid": 12}, float("inf")
        observer.report = {"actions": [], "observations": []}
        observer.bound = lambda: None
        observer.nav = lambda index: self.assertEqual(index, 5)
        observer.wait = lambda predicate, label: predicate()
        observer.atspi = SimpleNamespace(StateType=SimpleNamespace(**{name: name for name in
            ("VISIBLE", "SHOWING", "ENABLED", "SENSITIVE", "DEFUNCT")}))
        def capture(label):
            status["captures"].append(label)
        observer.capture = capture
        def accessible(value):
            is_popup_choice = value["name"] == "Compact"
            def fresh_states():
                status["events"].append(("state", value["name"]))
                snapshot = frozenset(status["native_states"] if is_popup_choice and
                    status["native_states"] is not None else value["states"])
                return SimpleNamespace(contains=lambda name: name in snapshot)
            def interface():
                names = status["native_actions"] if is_popup_choice else value["actions"]
                def perform(index):
                    self.assertEqual(names[index], "Tap")
                    status["actions"].append(value["name"])
                    if value["name"] == "Compact":
                        status["phase"] = "popup" if status["keep_popup"] else "closed"
                    else:
                        self.assertEqual(value["name"].splitlines()[0], "Desktop density")
                        status["phase"] = "popup"
                    return True
                return SimpleNamespace(get_n_actions=lambda: len(names),
                    get_action_name=lambda index: names[index], do_action=perform)
            return SimpleNamespace(clear_cache_single=lambda: status["events"].append(("clear", value["name"])),
                get_process_id=lambda: status["native_pid"] if is_popup_choice else 12,
                get_name=lambda: status["native_name"] if is_popup_choice else value["name"],
                get_role_name=lambda: status["native_role"] if is_popup_choice else value["role"],
                get_state_set=fresh_states, get_action_iface=interface)
        def tree(identity=None):
            self.assertIsNone(identity)
            status["trees"] += 1
            if status["phase"] == "popup":
                values = json.loads(ACTUAL_DENSITY_POPUP_JSON)
                if status["popup_change"]:
                    status["popup_change"](values)
            else:
                value = json.loads(ACTUAL_DENSITY_OPENING_JSON)
                if status["phase"] == "closed":
                    value["name"] = value["name"].removesuffix("Comfortable") + "Compact"
                if status["opening_change"]:
                    status["opening_change"](value)
                values = [value]
            for value in values:
                value["path"] = tuple(value["path"])
                value["accessible"] = accessible(value)
            return values
        observer.tree = tree
        return observer, status

    def test_actual_14_node_density_popup_flow_uses_context_and_restored_strict_row(self):
        nodes = json.loads(ACTUAL_DENSITY_POPUP_JSON)
        self.assertEqual(len(nodes), 14)
        canonical = json.dumps(nodes, sort_keys=True, separators=(",", ":")).encode()
        self.assertEqual(hashlib.sha256(canonical).hexdigest(), ACTUAL_DENSITY_POPUP_SHA256)
        compact = ui.unique([n for n in nodes if n["name"] == "Compact"], "captured Compact")
        self.assertFalse(ui.actionable(compact, "Tap"), "Global Compact policy must stay strict")
        observer, status = self.density_model()
        observer.density(initial=True)
        self.assertEqual(status["actions"], [json.loads(ACTUAL_DENSITY_OPENING_JSON)["name"], "Compact"])
        self.assertEqual(status["captures"], ["density-popup", "compact"])
        self.assertFalse(observer._density_popup_opened, "One popup opening permits only one accepted choice")
        self.assertGreaterEqual(status["trees"], 5, "Action must rediscover the popup after capture")
        self.assertEqual([event for event in status["events"] if event[1] == "Compact"],
                         [("clear", "Compact"), ("state", "Compact")])
        # Reopen observes only the strict persisted row; no popup permission or Tap.
        observer.density(initial=False)
        self.assertEqual(len(status["actions"]), 2)
        self.assertTrue(observer.report["observations"][-1]["restored"])

    def test_density_popup_rejects_disabled_hidden_defunct_ambiguous_or_misscoped_choices(self):
        def change_choice(values, label, **changes):
            ui.unique([n for n in values if n["name"] == label], label).update(changes)
        variants = {
            "disabled Compact": lambda v: change_choice(v, "Compact", states=["VISIBLE", "SHOWING", "SENSITIVE"]),
            "disabled Comfortable": lambda v: change_choice(v, "Comfortable", states=["VISIBLE", "SHOWING", "SENSITIVE"]),
            "hidden": lambda v: change_choice(v, "Compact", states=["SHOWING"]),
            "not showing": lambda v: change_choice(v, "Compact", states=["VISIBLE"]),
            "defunct": lambda v: change_choice(v, "Compact", states=["VISIBLE", "SHOWING", "DEFUNCT"]),
            "wrong role": lambda v: change_choice(v, "Compact", role="panel"),
            "wrong name": lambda v: change_choice(v, "Compact", name="Compact alias"),
            "wrong path": lambda v: change_choice(v, "Compact", path=[99, 1]),
            "not siblings": lambda v: change_choice(v, "Compact", path=[0] * 11 + [1]),
            "missing Tap": lambda v: change_choice(v, "Compact", actions=["Focus"]),
            "missing Focus": lambda v: change_choice(v, "Compact", actions=["Tap"]),
            "duplicate Tap": lambda v: change_choice(v, "Compact", actions=["Tap", "Tap", "Focus"]),
            "unrelated choice": lambda v: v.append(dict(node([0] * 10 + [2], "Other", role="push button",
                actions=("Tap", "Focus")), path=[0] * 10 + [2])),
            "duplicate hidden choice": lambda v: v.append(node([0] * 10 + [2], "Compact", role="push button", states=(), actions=("Tap", "Focus"))),
            "foreign scope alias": lambda v: v.append(node([99], "Compact", role="push button", actions=("Tap", "Focus"))),
            "duplicate popup": lambda v: v.append(node([99], "Popup menu", states=())),
            "hidden popup": lambda v: change_choice(v, "Popup menu", states=["SHOWING"]),
            "defunct popup": lambda v: change_choice(v, "Popup menu", states=["VISIBLE", "SHOWING", "DEFUNCT"]),
            "wrong popup role": lambda v: change_choice(v, "Popup menu", role="dialog"),
            "missing parent": lambda v: v.pop(10),
            "defunct parent": lambda v: v[10].update(states=["VISIBLE", "SHOWING", "DEFUNCT"]),
        }
        for description, change in variants.items():
            with self.subTest(description=description):
                values = json.loads(ACTUAL_DENSITY_POPUP_JSON)
                change(values)
                with self.assertRaises(RuntimeError):
                    ui.density_popup_choice(values)

    def test_density_popup_requires_actual_row_opening_and_does_not_relax_global_tap(self):
        observer, status = self.density_model()
        status["phase"] = "popup"
        with self.assertRaisesRegex(RuntimeError, "observed 0"):
            observer.find("Compact")
        with self.assertRaisesRegex(RuntimeError, "ordinary row opening"):
            observer.act("Compact", density_popup=True)
        observer._density_popup_opened = True
        for keywords in ({"label": "Comfortable"}, {"label": "Compact", "action": "Focus"},
                         {"label": "Compact", "identity": {"pid": 13}},
                         {"label": "Compact", "predicate": lambda n, ns: True}):
            with self.subTest(keywords=keywords), self.assertRaisesRegex(RuntimeError, "ordinary row opening"):
                observer.act(**keywords, density_popup=True)
        self.assertEqual(status["actions"], [])
        observer, status = self.density_model()
        status["opening_change"] = lambda n: n.update(name="Comfortable")
        with self.assertRaises(RuntimeError), patch.object(ui.time, "sleep"):
            observer.density(initial=True)
        self.assertEqual(status["actions"], [], "An unrelated Comfortable control cannot arm popup permission")

    def test_density_popup_reselects_entire_scope_after_capture_before_mutation(self):
        for description, change in (
            ("hidden duplicate choice", lambda v: v.append(node([99], "Compact", role="push button", states=(), actions=("Tap", "Focus")))),
            ("duplicate popup", lambda v: v.append(node([99], "Popup menu", states=()))),
            ("disabled sibling", lambda v: ui.unique([n for n in v if n["name"] == "Comfortable"], "sibling").update(
                states=["VISIBLE", "SHOWING", "SENSITIVE"]))):
            with self.subTest(description=description):
                observer, status = self.density_model()
                original_capture = observer.capture
                def capture(label):
                    original_capture(label)
                    if label == "density-popup":
                        status["popup_change"] = change
                observer.capture = capture
                with self.assertRaises(RuntimeError):
                    observer.density(initial=True)
                self.assertEqual(status["actions"], [json.loads(ACTUAL_DENSITY_OPENING_JSON)["name"]])
                self.assertNotIn(("clear", "Compact"), status["events"], "Ambiguous scope reached native mutation validation")

    def test_density_popup_immediate_native_revalidation_rejects_changed_identity_state_role_or_capability(self):
        changes = {
            "disabled": ("native_states", ["VISIBLE", "SHOWING", "SENSITIVE"]),
            "hidden": ("native_states", ["SHOWING"]),
            "defunct": ("native_states", ["VISIBLE", "SHOWING", "DEFUNCT"]),
            "foreign PID": ("native_pid", 13), "changed role": ("native_role", "panel"),
            "changed label": ("native_name", "Other"), "missing Tap": ("native_actions", ["Focus"]),
            "missing Focus": ("native_actions", ["Tap"]), "duplicate Tap": ("native_actions", ["Tap", "Tap", "Focus"]),
        }
        for description, (key, value) in changes.items():
            with self.subTest(description=description):
                observer, status = self.density_model()
                # The fresh tree remains valid; only the immediate native query changes.
                status[key] = value
                with self.assertRaises(RuntimeError):
                    observer.density(initial=True)
                self.assertEqual(status["actions"], [json.loads(ACTUAL_DENSITY_OPENING_JSON)["name"]])
                self.assertIn(("clear", "Compact"), status["events"])

    def test_density_requires_popup_dismissal_before_observing_normal_compact_row(self):
        observer, status = self.density_model()
        status["keep_popup"] = True
        with self.assertRaisesRegex(RuntimeError, "popup has not dismissed"):
            observer.density(initial=True)
        self.assertEqual(len(status["actions"]), 2)
        self.assertNotIn("compact", status["captures"])
        self.assertFalse(observer._density_popup_opened)
        row = json.loads(ACTUAL_DENSITY_OPENING_JSON)
        row["name"] = row["name"].removesuffix("Comfortable") + "Compact"
        self.assertIs(ui.density_row([row], "Compact"), row)
        for changed in (dict(row, name="Compact"), dict(row, role="panel"),
                        dict(row, states=["VISIBLE", "SHOWING", "SENSITIVE"]), dict(row, actions=[])):
            with self.subTest(changed=changed), self.assertRaises(RuntimeError):
                ui.density_row([changed], "Compact")
        with self.assertRaises(RuntimeError):
            ui.density_row([row, dict(row, path=[99])], "Compact")

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
        compact = node((0, 0, 1), "Desktop density\nChoose how much space desktop controls and lists use.\nCompact",
                       role="push button", actions=("Tap",))
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
