#!/usr/bin/env python3
"""Apply and verify media-session and secure-storage wrapper settings."""

from __future__ import annotations

import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Optional

ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"
TOOLS_NAMESPACE = "http://schemas.android.com/tools"
ANDROID = f"{{{ANDROID_NAMESPACE}}}"
TOOLS = f"{{{TOOLS_NAMESPACE}}}"

ANDROID_PERMISSIONS = (
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
)
ACTIVITY_NAME = "dev.aethertune.aethertune.MainActivity"
SERVICE_NAME = "com.ryanheise.audioservice.AudioService"
RECEIVER_NAME = "com.ryanheise.audioservice.MediaButtonReceiver"
WIDGET_PROVIDER_NAME = "dev.aethertune.aethertune.AetherTunePlaybackWidget"
IOS_DEPLOYMENT_TARGET = "14.0"
ANDROID_MIN_SDK = 23
KEYCHAIN_ACCESS_GROUPS = "keychain-access-groups"

_WIDGET_INFO_XML = """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<appwidget-provider xmlns:android=\"http://schemas.android.com/apk/res/android\"
    android:initialLayout=\"@layout/aethertune_playback_widget\"
    android:minWidth=\"180dp\"
    android:minHeight=\"72dp\"
    android:resizeMode=\"horizontal\"
    android:updatePeriodMillis=\"0\"
    android:widgetCategory=\"home_screen\" />
"""

_WIDGET_LAYOUT_XML = """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<LinearLayout xmlns:android=\"http://schemas.android.com/apk/res/android\"
    android:id=\"@+id/aethertune_playback_widget\"
    android:layout_width=\"match_parent\"
    android:layout_height=\"match_parent\"
    android:background=\"@android:drawable/dialog_holo_dark_frame\"
    android:gravity=\"center_vertical\"
    android:orientation=\"horizontal\"
    android:padding=\"8dp\">

    <LinearLayout
        android:layout_width=\"0dp\"
        android:layout_height=\"match_parent\"
        android:layout_weight=\"1\"
        android:gravity=\"center_vertical\"
        android:orientation=\"vertical\">

        <TextView
            android:id=\"@+id/aethertune_widget_title\"
            android:layout_width=\"match_parent\"
            android:layout_height=\"wrap_content\"
            android:ellipsize=\"end\"
            android:maxLines=\"1\"
            android:text=\"AetherTune\"
            android:textColor=\"@android:color/white\"
            android:textSize=\"16sp\" />

        <TextView
            android:id=\"@+id/aethertune_widget_artist\"
            android:layout_width=\"match_parent\"
            android:layout_height=\"wrap_content\"
            android:ellipsize=\"end\"
            android:maxLines=\"1\"
            android:textColor=\"@android:color/darker_gray\"
            android:textSize=\"12sp\" />

        <ProgressBar
            android:id=\"@+id/aethertune_widget_progress\"
            style=\"?android:attr/progressBarStyleHorizontal\"
            android:layout_width=\"match_parent\"
            android:layout_height=\"4dp\"
            android:layout_marginTop=\"4dp\"
            android:indeterminate=\"false\"
            android:max=\"1\"
            android:progress=\"0\" />
    </LinearLayout>

    <ImageButton
        android:id=\"@+id/aethertune_widget_previous\"
        android:layout_width=\"48dp\"
        android:layout_height=\"48dp\"
        android:background=\"@android:color/transparent\"
        android:contentDescription=\"Previous track\"
        android:src=\"@android:drawable/ic_media_previous\" />

    <ImageButton
        android:id=\"@+id/aethertune_widget_play_pause\"
        android:layout_width=\"48dp\"
        android:layout_height=\"48dp\"
        android:background=\"@android:color/transparent\"
        android:contentDescription=\"Play or pause\"
        android:src=\"@android:drawable/ic_media_play\" />

    <ImageButton
        android:id=\"@+id/aethertune_widget_next\"
        android:layout_width=\"48dp\"
        android:layout_height=\"48dp\"
        android:background=\"@android:color/transparent\"
        android:contentDescription=\"Next track\"
        android:src=\"@android:drawable/ic_media_next\" />
</LinearLayout>
"""

_SHORTCUTS_XML = """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<shortcuts xmlns:android=\"http://schemas.android.com/apk/res/android\">
    <shortcut
        android:shortcutId=\"previous\"
        android:enabled=\"true\"
        android:icon=\"@drawable/aethertune_shortcut_previous\"
        android:shortcutShortLabel=\"@string/aethertune_shortcut_previous\">
        <intent
            android:action=\"dev.aethertune.aethertune.shortcut.PREVIOUS\"
            android:targetPackage=\"dev.aethertune.aethertune\"
            android:targetClass=\"dev.aethertune.aethertune.MainActivity\" />
    </shortcut>
    <shortcut
        android:shortcutId=\"play_pause\"
        android:enabled=\"true\"
        android:icon=\"@drawable/aethertune_shortcut_play_pause\"
        android:shortcutShortLabel=\"@string/aethertune_shortcut_play_pause\">
        <intent
            android:action=\"dev.aethertune.aethertune.shortcut.PLAY_PAUSE\"
            android:targetPackage=\"dev.aethertune.aethertune\"
            android:targetClass=\"dev.aethertune.aethertune.MainActivity\" />
    </shortcut>
    <shortcut
        android:shortcutId=\"next\"
        android:enabled=\"true\"
        android:icon=\"@drawable/aethertune_shortcut_next\"
        android:shortcutShortLabel=\"@string/aethertune_shortcut_next\">
        <intent
            android:action=\"dev.aethertune.aethertune.shortcut.NEXT\"
            android:targetPackage=\"dev.aethertune.aethertune\"
            android:targetClass=\"dev.aethertune.aethertune.MainActivity\" />
    </shortcut>
</shortcuts>
"""

_SHORTCUT_STRINGS_XML = """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<resources>
    <string name=\"aethertune_shortcut_previous\">Previous track</string>
    <string name=\"aethertune_shortcut_play_pause\">Play or pause</string>
    <string name=\"aethertune_shortcut_next\">Next track</string>
</resources>
"""

_SHORTCUT_PREVIOUS_VECTOR_XML = """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<vector xmlns:android=\"http://schemas.android.com/apk/res/android\"
    android:width=\"24dp\"
    android:height=\"24dp\"
    android:viewportWidth=\"24\"
    android:viewportHeight=\"24\">
    <path android:fillColor=\"#FFFFFFFF\" android:pathData=\"M6,6h2v12H6zM18,6v12l-8,-6z\" />
</vector>
"""

_SHORTCUT_PLAY_PAUSE_VECTOR_XML = """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<vector xmlns:android=\"http://schemas.android.com/apk/res/android\"
    android:width=\"24dp\"
    android:height=\"24dp\"
    android:viewportWidth=\"24\"
    android:viewportHeight=\"24\">
    <path android:fillColor=\"#FFFFFFFF\" android:pathData=\"M8,5v14l11,-7z\" />
</vector>
"""

_SHORTCUT_NEXT_VECTOR_XML = """<?xml version=\"1.0\" encoding=\"utf-8\"?>
<vector xmlns:android=\"http://schemas.android.com/apk/res/android\"
    android:width=\"24dp\"
    android:height=\"24dp\"
    android:viewportWidth=\"24\"
    android:viewportHeight=\"24\">
    <path android:fillColor=\"#FFFFFFFF\" android:pathData=\"M16,6h2v12h-2zM6,6v12l8,-6z\" />
</vector>
"""

_WIDGET_KOTLIN = """package dev.aethertune.aethertune

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews

class AetherTunePlaybackWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            actionPrevious -> sendMediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            actionPlayPause -> sendMediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
            actionNext -> sendMediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT)
        }
        super.onReceive(context, intent)
    }

    companion object {
        private const val statePreferences = "aethertune_playback_widget"
        private const val stateTitle = "title"
        private const val stateArtist = "artist"
        private const val stateIsPlaying = "isPlaying"
        private const val statePositionMillis = "positionMillis"
        private const val stateDurationMillis = "durationMillis"
        private const val actionPrevious =
            "dev.aethertune.aethertune.widget.PREVIOUS"
        private const val actionPlayPause =
            "dev.aethertune.aethertune.widget.PLAY_PAUSE"
        private const val actionNext = "dev.aethertune.aethertune.widget.NEXT"

        fun updatePlaybackWidgets(
            context: Context,
            title: String,
            artist: String,
            isPlaying: Boolean,
            positionMillis: Long,
            durationMillis: Long,
        ) {
            context.getSharedPreferences(statePreferences, Context.MODE_PRIVATE)
                .edit()
                .putString(stateTitle, title)
                .putString(stateArtist, artist)
                .putBoolean(stateIsPlaying, isPlaying)
                .putLong(statePositionMillis, positionMillis.coerceAtLeast(0L))
                .putLong(stateDurationMillis, durationMillis.coerceAtLeast(0L))
                .apply()
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, AetherTunePlaybackWidget::class.java)
            appWidgetManager.getAppWidgetIds(componentName).forEach { appWidgetId ->
                updateWidget(context, appWidgetManager, appWidgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val views = RemoteViews(context.packageName, R.layout.aethertune_playback_widget)
            val state = context.getSharedPreferences(
                statePreferences,
                Context.MODE_PRIVATE,
            )
            val title = state.getString(stateTitle, "AetherTune") ?: "AetherTune"
            val artist = state.getString(stateArtist, "") ?: ""
            val isPlaying = state.getBoolean(stateIsPlaying, false)
            val durationMillis = state.getLong(stateDurationMillis, 0L)
                .coerceAtLeast(0L)
            val positionMillis = state.getLong(statePositionMillis, 0L)
                .coerceIn(0L, durationMillis)
            views.setTextViewText(R.id.aethertune_widget_title, title)
            views.setTextViewText(R.id.aethertune_widget_artist, artist)
            views.setImageViewResource(
                R.id.aethertune_widget_play_pause,
                if (isPlaying) android.R.drawable.ic_media_pause
                else android.R.drawable.ic_media_play,
            )
            views.setContentDescription(
                R.id.aethertune_widget_play_pause,
                if (isPlaying) "Pause" else "Play",
            )
            if (durationMillis > 0L) {
                val max = durationMillis.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                val progress = positionMillis.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                views.setViewVisibility(R.id.aethertune_widget_progress, View.VISIBLE)
                views.setProgressBar(
                    R.id.aethertune_widget_progress,
                    max,
                    progress,
                    false,
                )
            } else {
                views.setViewVisibility(R.id.aethertune_widget_progress, View.GONE)
            }
            views.setOnClickPendingIntent(
                R.id.aethertune_widget_previous,
                actionIntent(context, actionPrevious, 1),
            )
            views.setOnClickPendingIntent(
                R.id.aethertune_widget_play_pause,
                actionIntent(context, actionPlayPause, 2),
            )
            views.setOnClickPendingIntent(
                R.id.aethertune_widget_next,
                actionIntent(context, actionNext, 3),
            )
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                views.setOnClickPendingIntent(
                    R.id.aethertune_widget_title,
                    PendingIntent.getActivity(
                        context,
                        4,
                        it,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun actionIntent(
            context: Context,
            action: String,
            requestCode: Int,
        ): PendingIntent = PendingIntent.getBroadcast(
            context,
            requestCode,
            Intent(context, AetherTunePlaybackWidget::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        fun sendMediaButton(context: Context, keyCode: Int) {
            val receiverIntent = Intent(Intent.ACTION_MEDIA_BUTTON)
                .setClassName(
                    context.packageName,
                    "com.ryanheise.audioservice.MediaButtonReceiver",
                )
            context.sendBroadcast(
                receiverIntent.putExtra(
                    Intent.EXTRA_KEY_EVENT,
                    KeyEvent(KeyEvent.ACTION_DOWN, keyCode),
                ),
            )
            context.sendBroadcast(
                receiverIntent.putExtra(
                    Intent.EXTRA_KEY_EVENT,
                    KeyEvent(KeyEvent.ACTION_UP, keyCode),
                ),
            )
        }
    }
}
"""

_MAIN_ACTIVITY_KOTLIN = """package dev.aethertune.aethertune

import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dispatchLauncherShortcut(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        dispatchLauncherShortcut(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/playback_widget",
        ).setMethodCallHandler { call, result ->
            if (call.method != "update") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            AetherTunePlaybackWidget.updatePlaybackWidgets(
                applicationContext,
                call.argument<String>("title") ?: "AetherTune",
                call.argument<String>("artist") ?: "",
                call.argument<Boolean>("isPlaying") ?: false,
                call.argument<Number>("positionMillis")?.toLong() ?: 0L,
                call.argument<Number>("durationMillis")?.toLong() ?: 0L,
            )
            result.success(null)
        }
    }

    private fun dispatchLauncherShortcut(intent: Intent) {
        when (intent.action) {
            "dev.aethertune.aethertune.shortcut.PREVIOUS" ->
                AetherTunePlaybackWidget.sendMediaButton(
                    applicationContext,
                    KeyEvent.KEYCODE_MEDIA_PREVIOUS,
                )
            "dev.aethertune.aethertune.shortcut.PLAY_PAUSE" ->
                AetherTunePlaybackWidget.sendMediaButton(
                    applicationContext,
                    KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                )
            "dev.aethertune.aethertune.shortcut.NEXT" ->
                AetherTunePlaybackWidget.sendMediaButton(
                    applicationContext,
                    KeyEvent.KEYCODE_MEDIA_NEXT,
                )
        }
    }
}
"""


def _find_named(
    parent: ET.Element, tag: str, name: str
) -> Optional[ET.Element]:
    for element in parent.findall(tag):
        if element.get(f"{ANDROID}name") == name:
            return element
    return None


def _ensure_action(parent: ET.Element, action_name: str) -> None:
    intent_filter = parent.find("intent-filter")
    if intent_filter is None:
        intent_filter = ET.SubElement(parent, "intent-filter")
    for action in intent_filter.findall("action"):
        if action.get(f"{ANDROID}name") == action_name:
            return
    ET.SubElement(intent_filter, "action", {f"{ANDROID}name": action_name})


def _ensure_metadata(parent: ET.Element, name: str, resource: str) -> None:
    for metadata in parent.findall("meta-data"):
        if metadata.get(f"{ANDROID}name") == name:
            metadata.set(f"{ANDROID}resource", resource)
            return
    ET.SubElement(
        parent,
        "meta-data",
        {
            f"{ANDROID}name": name,
            f"{ANDROID}resource": resource,
        },
    )


def _widget_paths(manifest_path: Path) -> tuple[Path, Path, Path, Path]:
    app_dir = manifest_path.parents[2]
    resources = app_dir / "src/main/res"
    kotlin_dir = app_dir / "src/main/kotlin/dev/aethertune/aethertune"
    return (
        resources / "xml/aethertune_playback_widget_info.xml",
        resources / "layout/aethertune_playback_widget.xml",
        kotlin_dir / "AetherTunePlaybackWidget.kt",
        kotlin_dir / "MainActivity.kt",
    )


def _shortcut_paths(manifest_path: Path) -> tuple[Path, Path, Path, Path, Path]:
    resources = manifest_path.parents[2] / "src/main/res"
    return (
        resources / "xml/aethertune_launcher_shortcuts.xml",
        resources / "values/aethertune_shortcuts.xml",
        resources / "drawable/aethertune_shortcut_previous.xml",
        resources / "drawable/aethertune_shortcut_play_pause.xml",
        resources / "drawable/aethertune_shortcut_next.xml",
    )


def _write_android_playback_widget(manifest_path: Path) -> None:
    widget_info, widget_layout, widget_source, activity_source = _widget_paths(
        manifest_path
    )
    (
        shortcuts_xml,
        shortcut_strings,
        shortcut_previous,
        shortcut_play_pause,
        shortcut_next,
    ) = _shortcut_paths(manifest_path)
    for path, content in (
        (widget_info, _WIDGET_INFO_XML),
        (widget_layout, _WIDGET_LAYOUT_XML),
        (widget_source, _WIDGET_KOTLIN),
        (activity_source, _MAIN_ACTIVITY_KOTLIN),
        (shortcuts_xml, _SHORTCUTS_XML),
        (shortcut_strings, _SHORTCUT_STRINGS_XML),
        (shortcut_previous, _SHORTCUT_PREVIOUS_VECTOR_XML),
        (shortcut_play_pause, _SHORTCUT_PLAY_PAUSE_VECTOR_XML),
        (shortcut_next, _SHORTCUT_NEXT_VECTOR_XML),
    ):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def configure_android(manifest_path: Path, gradle_path: Path) -> None:
    ET.register_namespace("android", ANDROID_NAMESPACE)
    ET.register_namespace("tools", TOOLS_NAMESPACE)
    tree = ET.parse(manifest_path)
    root = tree.getroot()

    existing_permissions = {
        item.get(f"{ANDROID}name") for item in root.findall("uses-permission")
    }
    application = root.find("application")
    if application is None:
        raise RuntimeError(f"No <application> in {manifest_path}")
    application.set(f"{ANDROID}allowBackup", "false")
    insert_at = list(root).index(application)
    for permission in ANDROID_PERMISSIONS:
        if permission not in existing_permissions:
            root.insert(
                insert_at,
                ET.Element("uses-permission", {f"{ANDROID}name": permission}),
            )
            insert_at += 1

    activity = application.find("activity")
    if activity is None:
        raise RuntimeError(f"No <activity> in {manifest_path}")
    activity.set(f"{ANDROID}name", ACTIVITY_NAME)
    _ensure_metadata(
        activity,
        "android.app.shortcuts",
        "@xml/aethertune_launcher_shortcuts",
    )

    service = _find_named(application, "service", SERVICE_NAME)
    if service is None:
        service = ET.SubElement(application, "service")
    service.attrib.update(
        {
            f"{ANDROID}name": SERVICE_NAME,
            f"{ANDROID}foregroundServiceType": "mediaPlayback",
            f"{ANDROID}exported": "true",
            f"{TOOLS}ignore": "Instantiatable",
        }
    )
    _ensure_action(service, "android.media.browse.MediaBrowserService")

    receiver = _find_named(application, "receiver", RECEIVER_NAME)
    if receiver is None:
        receiver = ET.SubElement(application, "receiver")
    receiver.attrib.update(
        {
            f"{ANDROID}name": RECEIVER_NAME,
            f"{ANDROID}exported": "true",
            f"{TOOLS}ignore": "Instantiatable",
        }
    )
    _ensure_action(receiver, "android.intent.action.MEDIA_BUTTON")

    widget = _find_named(application, "receiver", WIDGET_PROVIDER_NAME)
    if widget is None:
        widget = ET.SubElement(application, "receiver")
    widget.attrib.update(
        {
            f"{ANDROID}name": WIDGET_PROVIDER_NAME,
            f"{ANDROID}exported": "true",
        }
    )
    _ensure_action(widget, "android.appwidget.action.APPWIDGET_UPDATE")
    widget_metadata = widget.find("meta-data")
    if widget_metadata is None:
        widget_metadata = ET.SubElement(widget, "meta-data")
    widget_metadata.attrib.update(
        {
            f"{ANDROID}name": "android.appwidget.provider",
            f"{ANDROID}resource": "@xml/aethertune_playback_widget_info",
        }
    )
    _write_android_playback_widget(manifest_path)

    ET.indent(tree, space="    ")
    tree.write(manifest_path, encoding="utf-8", xml_declaration=True)

    gradle = gradle_path.read_text(encoding="utf-8")
    gradle, replacements = re.subn(
        r"minSdk\s*=\s*flutter\.minSdkVersion",
        f"minSdk = {ANDROID_MIN_SDK}",
        gradle,
    )
    if replacements == 0:
        gradle, replacements = re.subn(
            r"minSdkVersion\s+flutter\.minSdkVersion",
            f"minSdkVersion {ANDROID_MIN_SDK}",
            gradle,
        )
    if replacements == 0 and not re.search(
        rf"(?:minSdk\s*=|minSdkVersion)\s*{ANDROID_MIN_SDK}\b", gradle
    ):
        raise RuntimeError(f"No Android minimum SDK declaration in {gradle_path}")
    gradle_path.write_text(gradle, encoding="utf-8")


def configure_ios(info_plist_path: Path) -> None:
    with info_plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    modes = list(info.get("UIBackgroundModes", []))
    if "audio" not in modes:
        modes.append("audio")
    info["UIBackgroundModes"] = modes
    with info_plist_path.open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)


def configure_ios_deployment_target(
    project_path: Path,
    framework_info_path: Path,
) -> None:
    project = project_path.read_text(encoding="utf-8")
    project, replacements = re.subn(
        r"IPHONEOS_DEPLOYMENT_TARGET = [^;]+;",
        f"IPHONEOS_DEPLOYMENT_TARGET = {IOS_DEPLOYMENT_TARGET};",
        project,
    )
    if replacements == 0:
        raise RuntimeError(f"No iOS deployment target in {project_path}")
    project_path.write_text(project, encoding="utf-8")

    with framework_info_path.open("rb") as stream:
        framework_info = plistlib.load(stream)
    framework_info["MinimumOSVersion"] = IOS_DEPLOYMENT_TARGET
    with framework_info_path.open("wb") as stream:
        plistlib.dump(framework_info, stream, sort_keys=False)


def configure_keychain_entitlements(entitlements_path: Path) -> None:
    if entitlements_path.is_file():
        with entitlements_path.open("rb") as stream:
            entitlements = plistlib.load(stream)
    else:
        entitlements = {}
        entitlements_path.parent.mkdir(parents=True, exist_ok=True)
    entitlements[KEYCHAIN_ACCESS_GROUPS] = list(
        entitlements.get(KEYCHAIN_ACCESS_GROUPS, [])
    )
    with entitlements_path.open("wb") as stream:
        plistlib.dump(entitlements, stream, sort_keys=False)


def configure_ios_code_sign_entitlements(project_path: Path) -> None:
    project = project_path.read_text(encoding="utf-8")
    pattern = re.compile(
        r"(buildSettings = \{)(.*?)(\n\s*\};\n\s*name = (Debug|Profile|Release);)",
        re.DOTALL,
    )
    configured = 0

    def update(match: re.Match[str]) -> str:
        nonlocal configured
        body = match.group(2)
        configuration = match.group(4)
        if (
            "PRODUCT_BUNDLE_IDENTIFIER =" not in body
            or ".RunnerTests" in body
        ):
            return match.group(0)
        entitlement_name = (
            "Release.entitlements"
            if configuration == "Release"
            else "DebugProfile.entitlements"
        )
        declaration = f"CODE_SIGN_ENTITLEMENTS = Runner/{entitlement_name};"
        if "CODE_SIGN_ENTITLEMENTS =" in body:
            body = re.sub(
                r"CODE_SIGN_ENTITLEMENTS = [^;]+;",
                declaration,
                body,
            )
        else:
            body = f"{body}\n\t\t\t\t{declaration}"
        configured += 1
        return f"{match.group(1)}{body}{match.group(3)}"

    project = pattern.sub(update, project)
    if configured == 0:
        raise RuntimeError(f"No iOS Runner build settings in {project_path}")
    project_path.write_text(project, encoding="utf-8")


def verify_android(manifest_path: Path, gradle_path: Path) -> None:
    root = ET.parse(manifest_path).getroot()
    permissions = {
        item.get(f"{ANDROID}name") for item in root.findall("uses-permission")
    }
    missing = set(ANDROID_PERMISSIONS) - permissions
    if missing:
        raise RuntimeError(f"Missing Android audio permissions: {sorted(missing)}")
    application = root.find("application")
    if application is None:
        raise RuntimeError("Missing Android application element")
    if application.get(f"{ANDROID}allowBackup") != "false":
        raise RuntimeError("Android backup must be disabled for secure storage")
    activity = application.find("activity")
    if activity is None or activity.get(f"{ANDROID}name") != ACTIVITY_NAME:
        raise RuntimeError("Android activity is not connected to audio_service")
    shortcut_metadata = next(
        (
            metadata
            for metadata in activity.findall("meta-data")
            if metadata.get(f"{ANDROID}name") == "android.app.shortcuts"
        ),
        None,
    )
    if (
        shortcut_metadata is None
        or shortcut_metadata.get(f"{ANDROID}resource")
        != "@xml/aethertune_launcher_shortcuts"
    ):
        raise RuntimeError("Android launcher shortcuts metadata is missing")
    if _find_named(application, "service", SERVICE_NAME) is None:
        raise RuntimeError("Android audio_service service is missing")
    if _find_named(application, "receiver", RECEIVER_NAME) is None:
        raise RuntimeError("Android media-button receiver is missing")
    widget = _find_named(application, "receiver", WIDGET_PROVIDER_NAME)
    if widget is None:
        raise RuntimeError("Android playback widget receiver is missing")
    if widget.get(f"{ANDROID}exported") != "true":
        raise RuntimeError("Android playback widget receiver is not exported")
    metadata = widget.find("meta-data")
    if (
        metadata is None
        or metadata.get(f"{ANDROID}name") != "android.appwidget.provider"
        or metadata.get(f"{ANDROID}resource")
        != "@xml/aethertune_playback_widget_info"
    ):
        raise RuntimeError("Android playback widget metadata is missing")
    widget_info, widget_layout, widget_source, activity_source = _widget_paths(
        manifest_path
    )
    if not all(
        path.is_file()
        for path in (widget_info, widget_layout, widget_source, activity_source)
    ):
        raise RuntimeError("Android playback widget resources are missing")
    widget_info_root = ET.parse(widget_info).getroot()
    if widget_info_root.get(f"{ANDROID}initialLayout") != "@layout/aethertune_playback_widget":
        raise RuntimeError("Android playback widget layout is not configured")
    layout = widget_layout.read_text(encoding="utf-8")
    required_layout_ids = (
        "aethertune_widget_previous",
        "aethertune_widget_play_pause",
        "aethertune_widget_next",
        "aethertune_widget_artist",
    )
    if not all(identifier in layout for identifier in required_layout_ids):
        raise RuntimeError("Android playback widget controls are missing")
    source = widget_source.read_text(encoding="utf-8")
    required_source_snippets = (
        "KEYCODE_MEDIA_PREVIOUS",
        "KEYCODE_MEDIA_PLAY_PAUSE",
        "KEYCODE_MEDIA_NEXT",
        "MediaButtonReceiver",
        "updatePlaybackWidgets",
        "setImageViewResource",
    )
    if not all(snippet in source for snippet in required_source_snippets):
        raise RuntimeError("Android playback widget media actions are missing")
    activity_source_text = activity_source.read_text(encoding="utf-8")
    required_activity_snippets = (
        "AudioServiceActivity",
        "MethodChannel",
        "dev.aethertune/playback_widget",
        "updatePlaybackWidgets",
    )
    if not all(snippet in activity_source_text for snippet in required_activity_snippets):
        raise RuntimeError("Android playback widget state bridge is missing")
    (
        shortcuts_xml,
        shortcut_strings,
        shortcut_previous,
        shortcut_play_pause,
        shortcut_next,
    ) = _shortcut_paths(manifest_path)
    if not all(
        path.is_file()
        for path in (
            shortcuts_xml,
            shortcut_strings,
            shortcut_previous,
            shortcut_play_pause,
            shortcut_next,
        )
    ):
        raise RuntimeError("Android launcher shortcut resources are missing")
    shortcuts_root = ET.parse(shortcuts_xml).getroot()
    shortcuts = shortcuts_root.findall("shortcut")
    shortcut_ids = {shortcut.get(f"{ANDROID}shortcutId") for shortcut in shortcuts}
    expected_shortcut_ids = {"previous", "play_pause", "next"}
    if shortcut_ids != expected_shortcut_ids:
        raise RuntimeError("Android launcher shortcut IDs are unexpected")
    shortcut_actions = {
        intent.get(f"{ANDROID}action")
        for shortcut in shortcuts
        if (intent := shortcut.find("intent")) is not None
    }
    expected_shortcut_actions = {
        "dev.aethertune.aethertune.shortcut.PREVIOUS",
        "dev.aethertune.aethertune.shortcut.PLAY_PAUSE",
        "dev.aethertune.aethertune.shortcut.NEXT",
    }
    if shortcut_actions != expected_shortcut_actions:
        raise RuntimeError("Android launcher shortcut actions are unexpected")
    if not all(action in activity_source_text for action in shortcut_actions):
        raise RuntimeError("Android launcher shortcuts are not routed by MainActivity")
    gradle = gradle_path.read_text(encoding="utf-8")
    if not re.search(
        rf"(?:minSdk\s*=|minSdkVersion)\s*{ANDROID_MIN_SDK}\b", gradle
    ):
        raise RuntimeError("Android minimum SDK is not 23")


def verify_ios(info_plist_path: Path) -> None:
    with info_plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    if "audio" not in info.get("UIBackgroundModes", []):
        raise RuntimeError("iOS audio background mode is missing")


def verify_ios_deployment_target(
    project_path: Path,
    framework_info_path: Path,
) -> None:
    project = project_path.read_text(encoding="utf-8")
    targets = set(re.findall(r"IPHONEOS_DEPLOYMENT_TARGET = ([^;]+);", project))
    if not targets or targets != {IOS_DEPLOYMENT_TARGET}:
        raise RuntimeError(f"Unexpected iOS deployment targets: {sorted(targets)}")
    with framework_info_path.open("rb") as stream:
        framework_info = plistlib.load(stream)
    if framework_info.get("MinimumOSVersion") != IOS_DEPLOYMENT_TARGET:
        raise RuntimeError("Flutter framework iOS minimum version is not 14.0")


def verify_keychain_entitlements(entitlements_path: Path) -> None:
    with entitlements_path.open("rb") as stream:
        entitlements = plistlib.load(stream)
    if KEYCHAIN_ACCESS_GROUPS not in entitlements:
        raise RuntimeError(
            f"Keychain access groups missing from {entitlements_path}"
        )


def verify_ios_code_sign_entitlements(project_path: Path) -> None:
    project = project_path.read_text(encoding="utf-8")
    declarations = set(
        re.findall(r"CODE_SIGN_ENTITLEMENTS = Runner/([^;]+);", project)
    )
    expected = {"DebugProfile.entitlements", "Release.entitlements"}
    if declarations != expected:
        raise RuntimeError(
            f"Unexpected iOS code-sign entitlements: {sorted(declarations)}"
        )


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: configure_audio_service_platforms.py <flutter-app-dir>")
        return 2
    app_dir = Path(sys.argv[1]).resolve()
    android_manifest = app_dir / "android/app/src/main/AndroidManifest.xml"
    android_gradle = app_dir / "android/app/build.gradle.kts"
    ios_info = app_dir / "ios/Runner/Info.plist"
    ios_project = app_dir / "ios/Runner.xcodeproj/project.pbxproj"
    ios_framework_info = app_dir / "ios/Flutter/AppFrameworkInfo.plist"
    ios_debug_entitlements = app_dir / "ios/Runner/DebugProfile.entitlements"
    ios_release_entitlements = app_dir / "ios/Runner/Release.entitlements"
    macos_debug_entitlements = app_dir / "macos/Runner/DebugProfile.entitlements"
    macos_release_entitlements = app_dir / "macos/Runner/Release.entitlements"
    for path in (
        android_manifest,
        android_gradle,
        ios_info,
        ios_project,
        ios_framework_info,
        macos_debug_entitlements,
        macos_release_entitlements,
    ):
        if not path.is_file():
            raise FileNotFoundError(path)

    configure_android(android_manifest, android_gradle)
    configure_ios(ios_info)
    configure_ios_deployment_target(ios_project, ios_framework_info)
    configure_keychain_entitlements(ios_debug_entitlements)
    configure_keychain_entitlements(ios_release_entitlements)
    configure_keychain_entitlements(macos_debug_entitlements)
    configure_keychain_entitlements(macos_release_entitlements)
    configure_ios_code_sign_entitlements(ios_project)
    verify_android(android_manifest, android_gradle)
    verify_ios(ios_info)
    verify_ios_deployment_target(ios_project, ios_framework_info)
    verify_keychain_entitlements(ios_debug_entitlements)
    verify_keychain_entitlements(ios_release_entitlements)
    verify_keychain_entitlements(macos_debug_entitlements)
    verify_keychain_entitlements(macos_release_entitlements)
    verify_ios_code_sign_entitlements(ios_project)
    print("Configured media controls and cross-platform secure storage.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
