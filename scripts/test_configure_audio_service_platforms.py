#!/usr/bin/env python3
"""Regression checks for generated Android media-session wrapper files."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
CONFIGURE_SCRIPT = ROOT_DIR / "scripts/configure_audio_service_platforms.py"
SPEC = importlib.util.spec_from_file_location("platform_config", CONFIGURE_SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load {CONFIGURE_SCRIPT}")
platform_config = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(platform_config)


class AndroidPlaybackWidgetTest(unittest.TestCase):
    def test_configures_and_verifies_media_button_widget(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            app_dir = Path(temporary_directory) / "mobile"
            manifest_path = app_dir / "android/app/src/main/AndroidManifest.xml"
            gradle_path = app_dir / "android/app/build.gradle.kts"
            manifest_path.parent.mkdir(parents=True)
            gradle_path.parent.mkdir(parents=True, exist_ok=True)
            manifest_path.write_text(
                """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">
    <application>
        <activity android:name=\".MainActivity\" />
    </application>
</manifest>
""",
                encoding="utf-8",
            )
            gradle_path.write_text(
                "android { defaultConfig { minSdk = flutter.minSdkVersion } }\n",
                encoding="utf-8",
            )

            platform_config.configure_android(manifest_path, gradle_path)
            platform_config.verify_android(manifest_path, gradle_path)
            platform_config.configure_android(manifest_path, gradle_path)

            root = ET.parse(manifest_path).getroot()
            application = root.find("application")
            self.assertIsNotNone(application)
            widget = platform_config._find_named(
                application,
                "receiver",
                platform_config.WIDGET_PROVIDER_NAME,
            )
            self.assertIsNotNone(widget)
            activity = application.find("activity")
            self.assertIsNotNone(activity)
            self.assertEqual(
                activity.get(f"{platform_config.ANDROID}name"),
                platform_config.ACTIVITY_NAME,
            )
            widget_source = (
                app_dir
                / "android/app/src/main/kotlin/dev/aethertune/aethertune"
                / "AetherTunePlaybackWidget.kt"
            )
            self.assertIn("KEYCODE_MEDIA_PLAY_PAUSE", widget_source.read_text())
            widget_text = widget_source.read_text(encoding="utf-8")
            self.assertIn("statePositionMillis", widget_text)
            self.assertIn("stateDurationMillis", widget_text)
            self.assertIn("setProgressBar", widget_text)
            self.assertIn("stateArtworkPath", widget_text)
            self.assertIn("BitmapFactory.decodeFile", widget_text)
            self.assertIn("setImageViewBitmap", widget_text)
            activity_source = widget_source.with_name("MainActivity.kt")
            self.assertIn(
                "updatePlaybackWidgets",
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                "minSdk = maxOf(flutter.minSdkVersion, 23)",
                gradle_path.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'call.argument<Number>("positionMillis")',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'call.argument<String>("artworkPath")',
                activity_source.read_text(encoding="utf-8"),
            )
            widget_layout = (
                widget_source.parents[4]
                / "res/layout/aethertune_playback_widget.xml"
            )
            self.assertIn(
                "aethertune_widget_progress",
                widget_layout.read_text(encoding="utf-8"),
            )
            self.assertIn(
                "aethertune_widget_artwork",
                widget_layout.read_text(encoding="utf-8"),
            )
            shortcuts = (
                app_dir
                / "android/app/src/main/res/xml/aethertune_launcher_shortcuts.xml"
            )
            shortcut_root = ET.parse(shortcuts).getroot()
            shortcut_ids = {
                shortcut.get(f"{platform_config.ANDROID}shortcutId")
                for shortcut in shortcut_root.findall("shortcut")
            }
            self.assertEqual(shortcut_ids, {"previous", "play_pause", "next"})


if __name__ == "__main__":
    unittest.main()
