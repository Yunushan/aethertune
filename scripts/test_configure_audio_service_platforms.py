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
            offline_cache_job = platform_config._find_named(
                application,
                "service",
                platform_config.OFFLINE_CACHE_JOB_SERVICE_NAME,
            )
            self.assertIsNotNone(offline_cache_job)
            self.assertEqual(
                offline_cache_job.get(f"{platform_config.ANDROID}exported"),
                "true",
            )
            self.assertEqual(
                offline_cache_job.get(f"{platform_config.ANDROID}permission"),
                "android.permission.BIND_JOB_SERVICE",
            )
            activity = application.find("activity")
            self.assertIsNotNone(activity)
            self.assertEqual(
                activity.get(f"{platform_config.ANDROID}name"),
                platform_config.ACTIVITY_NAME,
            )
            self.assertEqual(
                activity.get(f"{platform_config.ANDROID}exported"),
                "true",
            )
            self.assertEqual(
                activity.get(f"{platform_config.ANDROID}supportsPictureInPicture"),
                "true",
            )
            self.assertTrue(
                any(
                    any(
                        data.get(f"{platform_config.ANDROID}scheme")
                        == platform_config.DEEP_LINK_SCHEME
                        for data in intent_filter.findall("data")
                    )
                    for intent_filter in activity.findall("intent-filter")
                )
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
            activity_text = activity_source.read_text(encoding="utf-8")
            self.assertIn("dev.aethertune/pinned_shortcuts", activity_text)
            self.assertIn("ShortcutManager", activity_text)
            self.assertIn("requestPinShortcut", activity_text)
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
            self.assertIn(
                'dev.aethertune/audio_visualizer',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'dev.aethertune/audio_routes',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'dev.aethertune/video_picture_in_picture',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'PictureInPictureParams.Builder',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'Settings.ACTION_SOUND_SETTINGS',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'Visualizer.getMaxCaptureRate()',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'dev.aethertune/audio_virtualizer',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'dev.aethertune/storage_access',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'requestAudioLibraryAccess',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'dev.aethertune/offline_cache_background',
                activity_source.read_text(encoding="utf-8"),
            )
            background_job_source = activity_source.with_name(
                "AetherTuneOfflineCacheJobService.kt",
            )
            background_job_text = background_job_source.read_text(encoding="utf-8")
            self.assertIn("JobScheduler", background_job_text)
            self.assertIn("setPersisted(true)", background_job_text)
            self.assertIn("minimumLatencyMilliseconds", activity_text)
            self.assertIn("nextRunDelayMilliseconds", background_job_text)
            self.assertIn("maximumMinimumLatencyMillis", background_job_text)
            self.assertIn(
                "offlineCacheBackgroundEntrypoint",
                background_job_text,
            )
            self.assertIn(
                'AetherTuneAudioVirtualizer',
                activity_source.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'android.permission.RECORD_AUDIO',
                manifest_path.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'android.permission.READ_MEDIA_AUDIO',
                manifest_path.read_text(encoding="utf-8"),
            )
            self.assertIn(
                'android.permission.RECEIVE_BOOT_COMPLETED',
                manifest_path.read_text(encoding="utf-8"),
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

    def test_configures_ios_and_macos_url_schemes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            info_path = Path(temporary_directory) / "Info.plist"
            app_delegate_path = Path(temporary_directory) / "Runner/AppDelegate.swift"
            with info_path.open("wb") as stream:
                platform_config.plistlib.dump({}, stream)

            platform_config.configure_ios(info_path, app_delegate_path)
            platform_config.verify_ios(info_path, app_delegate_path)
            platform_config.configure_ios(info_path, app_delegate_path)

            with info_path.open("rb") as stream:
                ios = platform_config.plistlib.load(stream)
            self.assertFalse(ios["FlutterDeepLinkingEnabled"])
            self.assertEqual(
                ios["CFBundleURLTypes"][0]["CFBundleURLSchemes"],
                [platform_config.DEEP_LINK_SCHEME],
            )
            app_delegate = app_delegate_path.read_text(encoding="utf-8")
            self.assertIn("AVRoutePickerView", app_delegate)
            self.assertIn("dev.aethertune/audio_routes", app_delegate)

            platform_config.configure_macos(info_path)
            platform_config.verify_macos(info_path)

    def test_configures_linux_and_windows_deep_link_forwarding(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            linux_source = root / "my_application.cc"
            linux_source.write_text(
                """static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
}
static gboolean my_application_local_command_line(
    GApplication* application, gchar*** arguments, int* exit_status) {
  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}
MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
      \"flags\", G_APPLICATION_NON_UNIQUE,
      nullptr));
}
""",
                encoding="utf-8",
            )
            platform_config.configure_linux_deep_links(linux_source)
            platform_config.verify_linux_deep_links(linux_source)

            windows_source = root / "main.cpp"
            windows_cmake = root / "CMakeLists.txt"
            windows_source.write_text(
                """#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include "flutter_window.h"
#include "utils.h"
int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE prev,
    wchar_t *command_line, int show_command) {
  return 0;
}
""",
                encoding="utf-8",
            )
            windows_cmake.write_text(
                "target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)\n",
                encoding="utf-8",
            )
            platform_config.configure_windows_deep_links(
                windows_source,
                windows_cmake,
            )
            platform_config.verify_windows_deep_links(
                windows_source,
                windows_cmake,
            )
            self.assertIn(
                'L"\\"" + std::wstring(executable_path)',
                windows_source.read_text(encoding="utf-8"),
            )


if __name__ == "__main__":
    unittest.main()
