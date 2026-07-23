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
    "android.permission.RECORD_AUDIO",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.READ_MEDIA_AUDIO",
    "android.permission.RECEIVE_BOOT_COMPLETED",
)
ACTIVITY_NAME = "dev.aethertune.aethertune.MainActivity"
SERVICE_NAME = "com.ryanheise.audioservice.AudioService"
RECEIVER_NAME = "com.ryanheise.audioservice.MediaButtonReceiver"
WIDGET_PROVIDER_NAME = "dev.aethertune.aethertune.AetherTunePlaybackWidget"
OFFLINE_CACHE_JOB_SERVICE_NAME = (
    "dev.aethertune.aethertune.AetherTuneOfflineCacheJobService"
)
IOS_DEPLOYMENT_TARGET = "14.0"
ANDROID_MIN_SDK = 23
KEYCHAIN_ACCESS_GROUPS = "keychain-access-groups"
DEEP_LINK_SCHEME = "aethertune"
DEEP_LINK_URL_NAME = "dev.aethertune.aethertune"

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

    <ImageView
        android:id=\"@+id/aethertune_widget_artwork\"
        android:layout_width=\"40dp\"
        android:layout_height=\"40dp\"
        android:layout_marginEnd=\"8dp\"
        android:contentDescription=\"Album artwork\"
        android:scaleType=\"centerCrop\"
        android:visibility=\"gone\" />

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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import java.io.File

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
        private const val stateArtworkPath = "artworkPath"
        private const val maximumArtworkEdgePixels = 192
        private const val actionPrevious =
            "dev.aethertune.aethertune.widget.PREVIOUS"
        private const val actionPlayPause =
            "dev.aethertune.aethertune.widget.PLAY_PAUSE"
        private const val actionNext = "dev.aethertune.aethertune.widget.NEXT"
        private var cachedArtworkPath: String? = null
        private var cachedArtwork: Bitmap? = null

        fun updatePlaybackWidgets(
            context: Context,
            title: String,
            artist: String,
            isPlaying: Boolean,
            positionMillis: Long,
            durationMillis: Long,
            artworkPath: String?,
        ) {
            context.getSharedPreferences(statePreferences, Context.MODE_PRIVATE)
                .edit()
                .putString(stateTitle, title)
                .putString(stateArtist, artist)
                .putBoolean(stateIsPlaying, isPlaying)
                .putLong(statePositionMillis, positionMillis.coerceAtLeast(0L))
                .putLong(stateDurationMillis, durationMillis.coerceAtLeast(0L))
                .putString(stateArtworkPath, artworkPath)
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
            val artwork = artworkBitmap(state.getString(stateArtworkPath, null))
            views.setTextViewText(R.id.aethertune_widget_title, title)
            views.setTextViewText(R.id.aethertune_widget_artist, artist)
            if (artwork != null) {
                views.setViewVisibility(R.id.aethertune_widget_artwork, View.VISIBLE)
                views.setImageViewBitmap(R.id.aethertune_widget_artwork, artwork)
            } else {
                views.setViewVisibility(R.id.aethertune_widget_artwork, View.GONE)
            }
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

        private fun artworkBitmap(path: String?): Bitmap? {
            if (path == cachedArtworkPath) {
                return cachedArtwork
            }
            cachedArtworkPath = path
            cachedArtwork = path?.let(::decodeArtwork)
            return cachedArtwork
        }

        private fun decodeArtwork(path: String): Bitmap? {
            val file = File(path)
            if (!file.isFile) {
                return null
            }
            val bounds = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                return null
            }
            var sampleSize = 1
            while (
                bounds.outWidth / sampleSize > maximumArtworkEdgePixels ||
                    bounds.outHeight / sampleSize > maximumArtworkEdgePixels
            ) {
                sampleSize *= 2
            }
            return BitmapFactory.decodeFile(
                path,
                BitmapFactory.Options().apply {
                    inSampleSize = sampleSize
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                },
            )
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

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ContentValues
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.media.audiofx.Virtualizer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import kotlin.math.ln
import kotlin.math.sqrt

class MainActivity : AudioServiceActivity() {
    private val audioVisualizer = AetherTuneAudioVisualizer()
    private val audioVirtualizer = AetherTuneAudioVirtualizer()
    private var pendingVisualizerResult: MethodChannel.Result? = null
    private var pendingVisualizerSessionId: Int? = null
    private var pendingAudioLibraryAccessResult: MethodChannel.Result? = null
    private var pendingSafTreeResult: MethodChannel.Result? = null
    private var pendingSafMaterializationResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dispatchLauncherShortcut(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        dispatchLauncherShortcut(intent)
    }

    override fun onResume() {
        super.onResume()
        AetherTuneOfflineCacheJobService.cancel(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/audio_visualizer/bands",
        ).setStreamHandler(audioVisualizer)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/audio_visualizer",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val sessionId = call.argument<Number>("audioSessionId")?.toInt()
                    if (sessionId == null || sessionId <= 0) {
                        result.success(false)
                    } else {
                        startVisualizer(sessionId, result)
                    }
                }
                "stop" -> {
                    audioVisualizer.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/audio_virtualizer",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "attach" -> {
                    val sessionId = call.argument<Number>("audioSessionId")?.toInt()
                    val slot = call.argument<String>("slot")
                    result.success(
                        sessionId != null &&
                            sessionId > 0 &&
                            slot != null &&
                            audioVirtualizer.attach(slot, sessionId),
                    )
                }
                "setEnabled" -> {
                    result.success(
                        audioVirtualizer.setEnabled(call.argument<Boolean>("enabled") ?: false),
                    )
                }
                "setStrength" -> {
                    val strength = call.argument<Number>("strength")?.toInt()
                    result.success(
                        strength != null && audioVirtualizer.setStrength(strength),
                    )
                }
                "release" -> {
                    audioVirtualizer.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
                call.argument<String>("artworkPath"),
            )
            result.success(null)
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/pinned_shortcuts",
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestPin") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            result.success(requestPinnedShortcut(call.argument<String>("shortcut")))
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/audio_routes",
        ).setMethodCallHandler { call, result ->
            if (call.method != "showAudioRoutePicker") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                startActivity(Intent(Settings.ACTION_SOUND_SETTINGS))
                result.success(true)
            } catch (_: Exception) {
                result.success(false)
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/video_picture_in_picture",
        ).setMethodCallHandler { call, result ->
            if (call.method != "enter") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            result.success(enterVideoPictureInPicture())
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/storage_access",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAudioLibraryAccess" -> requestAudioLibraryAccess(result)
                "openAudioLibrarySettings" -> result.success(openAudioLibrarySettings())
                "selectAudioTree" -> selectPersistedAudioTree(result)
                "materializeAudioTree" -> {
                    val treeUri = call.argument<String>("treeUri")
                    if (treeUri == null) {
                        result.error("invalid_arguments", "A tree URI is required.", null)
                    } else {
                        materializeAudioTree(treeUri, result)
                    }
                }
                "discardAudioTreeMaterialization" -> {
                    discardAudioTreeMaterialization(
                        call.argument<String>("stagingRootPath"),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/offline_cache_background",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> result.success(
                    AetherTuneOfflineCacheJobService.schedule(
                        applicationContext,
                        call.argument<Number>("minimumLatencyMilliseconds")?.toLong(),
                    ),
                )
                "cancel" -> {
                    AetherTuneOfflineCacheJobService.cancel(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/system_downloads",
        ).setMethodCallHandler { call, result ->
            if (call.method != "exportVerifiedFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val sourcePath = call.argument<String>("sourcePath")
            val displayName = call.argument<String>("displayName")
            val byteCount = call.argument<Number>("byteCount")?.toLong()
            val checksum = call.argument<String>("checksum")
            if (sourcePath == null || displayName == null || byteCount == null || checksum == null) {
                result.error("invalid_arguments", "Verified cache export arguments are required.", null)
                return@setMethodCallHandler
            }
            try {
                result.success(
                    exportVerifiedFileToDownloads(
                        sourcePath,
                        displayName,
                        byteCount,
                        checksum,
                    ),
                )
            } catch (error: Exception) {
                result.error("export_failed", error.message, null)
            }
        }
    }

    private fun exportVerifiedFileToDownloads(
        sourcePath: String,
        requestedDisplayName: String,
        expectedByteCount: Long,
        expectedChecksum: String,
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return null
        }
        if (expectedByteCount < 0 || !expectedChecksum.matches(Regex("[a-f0-9]{8}"))) {
            throw IllegalArgumentException("Verified cache metadata is invalid.")
        }
        val source = File(sourcePath)
        if (!source.isFile) {
            throw IOException("Verified cache file is missing.")
        }
        val displayName = requestedDisplayName
            .replace(Regex("[\\\\/:*?\\\"<>|\\\\p{Cntrl}]"), " ")
            .replace(Regex("\\\\s+"), " ")
            .trim()
            .ifEmpty { "aethertune-media" }
            .take(100)
        val extension = displayName.substringAfterLast('.', "")
        val mimeType = if (extension.isEmpty()) {
            "application/octet-stream"
        } else {
            android.webkit.MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(extension.lowercase())
                ?: "application/octet-stream"
        }
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(
            MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            values,
        ) ?: throw IOException("Could not create a Downloads entry.")
        try {
            var written = 0L
            var checksum = 0x811c9dc5L
            source.inputStream().use { input ->
                resolver.openOutputStream(uri, "w")?.use { output ->
                    val buffer = ByteArray(32 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count <= 0) {
                            break
                        }
                        output.write(buffer, 0, count)
                        written += count.toLong()
                        for (index in 0 until count) {
                            checksum = ((checksum xor (buffer[index].toInt() and 0xff).toLong()) *
                                0x01000193L) and 0xffffffffL
                        }
                    }
                } ?: throw IOException("Could not open the Downloads entry.")
            }
            val actualChecksum = checksum.toString(16).padStart(8, '0')
            if (written != expectedByteCount || actualChecksum != expectedChecksum) {
                throw IOException("Verified cache changed before export completed.")
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri.toString()
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun enterVideoPictureInPicture(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        ) {
            return false
        }
        return try {
            enterPictureInPictureMode(PictureInPictureParams.Builder().build())
        } catch (_: Exception) {
            false
        }
    }

    private fun requestPinnedShortcut(shortcut: String?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        val shortcutManager = getSystemService(ShortcutManager::class.java)
            ?: return false
        if (!shortcutManager.isRequestPinShortcutSupported) {
            return false
        }
        val definition = when (shortcut) {
            "previous" -> Triple(
                "pinned_previous",
                getString(R.string.aethertune_shortcut_previous),
                R.drawable.aethertune_shortcut_previous,
            )
            "playPause" -> Triple(
                "pinned_play_pause",
                getString(R.string.aethertune_shortcut_play_pause),
                R.drawable.aethertune_shortcut_play_pause,
            )
            "next" -> Triple(
                "pinned_next",
                getString(R.string.aethertune_shortcut_next),
                R.drawable.aethertune_shortcut_next,
            )
            else -> return false
        }
        val action = when (shortcut) {
            "previous" -> "dev.aethertune.aethertune.shortcut.PREVIOUS"
            "playPause" -> "dev.aethertune.aethertune.shortcut.PLAY_PAUSE"
            "next" -> "dev.aethertune.aethertune.shortcut.NEXT"
            else -> return false
        }
        val shortcutInfo = ShortcutInfo.Builder(this, definition.first)
            .setShortLabel(definition.second)
            .setIcon(Icon.createWithResource(this, definition.third))
            .setIntent(Intent(this, MainActivity::class.java).setAction(action))
            .build()
        return shortcutManager.requestPinShortcut(shortcutInfo, null)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == audioLibraryPermissionRequestCode) {
            val result = pendingAudioLibraryAccessResult
            pendingAudioLibraryAccessResult = null
            result?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            return
        }
        if (requestCode != visualizerPermissionRequestCode) {
            return
        }
        val result = pendingVisualizerResult
        val sessionId = pendingVisualizerSessionId
        pendingVisualizerResult = null
        pendingVisualizerSessionId = null
        if (result == null) {
            return
        }
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        result.success(granted && sessionId != null && audioVisualizer.start(sessionId))
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != safTreeRequestCode) {
            return
        }
        val result = pendingSafTreeResult
        pendingSafTreeResult = null
        val returnedData = data
        val treeUri = returnedData?.data
        if (result == null || resultCode != RESULT_OK || treeUri == null) {
            result?.success(null)
            return
        }
        val grantedFlags = returnedData.flags and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        if (grantedFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION == 0) {
            result.error("read-access-denied", "The selected folder was not readable.", null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(treeUri, grantedFlags)
            result.success(treeUri.toString())
        } catch (_: SecurityException) {
            result.error("persist-access-denied", "Android could not retain folder access.", null)
        }
    }

    override fun onDestroy() {
        audioVisualizer.stop()
        audioVirtualizer.release()
        super.onDestroy()
    }

    private fun startVisualizer(sessionId: Int, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingVisualizerResult != null ||
                pendingAudioLibraryAccessResult != null
            ) {
                result.error("permission-request-active", "A visualizer permission request is active.", null)
                return
            }
            pendingVisualizerResult = result
            pendingVisualizerSessionId = sessionId
            requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                visualizerPermissionRequestCode,
            )
            return
        }
        result.success(audioVisualizer.start(sessionId))
    }

    private fun requestAudioLibraryAccess(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingVisualizerResult != null ||
            pendingAudioLibraryAccessResult != null
        ) {
            result.error(
                "permission-request-active",
                "A platform permission request is already active.",
                null,
            )
            return
        }
        pendingAudioLibraryAccessResult = result
        requestPermissions(arrayOf(permission), audioLibraryPermissionRequestCode)
    }

    private fun openAudioLibrarySettings(): Boolean {
        return try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = android.net.Uri.fromParts("package", packageName, null)
                },
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun selectPersistedAudioTree(result: MethodChannel.Result) {
        if (pendingSafTreeResult != null || pendingSafMaterializationResult != null) {
            result.error("saf-request-active", "Android folder access is already active.", null)
            return
        }
        pendingSafTreeResult = result
        startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                .addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                .addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION),
            safTreeRequestCode,
        )
    }

    private fun materializeAudioTree(treeUriText: String, result: MethodChannel.Result) {
        if (pendingSafTreeResult != null || pendingSafMaterializationResult != null) {
            result.error("saf-request-active", "Android folder access is already active.", null)
            return
        }
        val treeUri = try {
            Uri.parse(treeUriText)
        } catch (_: Exception) {
            null
        }
        if (treeUri == null || treeUri.scheme != "content" || treeUri.authority.isNullOrBlank()) {
            result.error("invalid_tree_uri", "A persisted content tree URI is required.", null)
            return
        }
        if (contentResolver.persistedUriPermissions.none {
                it.uri == treeUri && it.isReadPermission
            }
        ) {
            result.error("tree-access-revoked", "Android folder access is no longer available.", null)
            return
        }
        pendingSafMaterializationResult = result
        Thread {
            try {
                val materialization = materializePersistedAudioTree(treeUri)
                runOnUiThread {
                    pendingSafMaterializationResult = null
                    result.success(materialization)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    pendingSafMaterializationResult = null
                    result.error("tree-materialization-failed", error.message, null)
                }
            }
        }.start()
    }

    private fun materializePersistedAudioTree(treeUri: Uri): Map<String, Any> {
        val stagingParent = File(cacheDir, safMaterializationDirectoryName)
        if (!stagingParent.exists() && !stagingParent.mkdirs()) {
            throw IllegalStateException("Could not prepare Android folder scan cache.")
        }
        val stagingRoot = File(
            stagingParent,
            "${System.currentTimeMillis()}-${Integer.toHexString(treeUri.toString().hashCode())}",
        )
        if (!stagingRoot.mkdirs()) {
            throw IllegalStateException("Could not create Android folder scan cache.")
        }
        val budget = SafMaterializationBudget()
        val audioFiles = ArrayList<Map<String, String>>()
        try {
            materializeSafDirectory(
                treeUri,
                DocumentsContract.getTreeDocumentId(treeUri),
                stagingRoot,
                stagingRoot,
                budget,
                audioFiles,
            )
            return mapOf(
                "stagingRootPath" to stagingRoot.absolutePath,
                "audioFiles" to audioFiles,
                "inaccessibleDirectoryCount" to budget.inaccessibleCount,
            )
        } catch (error: Exception) {
            stagingRoot.deleteRecursively()
            throw error
        }
    }

    private fun materializeSafDirectory(
        treeUri: Uri,
        documentId: String,
        stagingRoot: File,
        destination: File,
        budget: SafMaterializationBudget,
        audioFiles: MutableList<Map<String, String>>,
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            documentId,
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        val cursor = try {
            contentResolver.query(
                childrenUri,
                projection,
                null,
                null,
                "${DocumentsContract.Document.COLUMN_DISPLAY_NAME} COLLATE NOCASE ASC",
            )
        } catch (_: SecurityException) {
            budget.inaccessibleCount += 1
            return
        }
        cursor?.use {
            val idIndex = it.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = it.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeTypeIndex = it.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (it.moveToNext()) {
                if (idIndex < 0 || nameIndex < 0 || mimeTypeIndex < 0) {
                    budget.inaccessibleCount += 1
                    return@use
                }
                val childDocumentId = it.getString(idIndex) ?: continue
                val displayName = it.getString(nameIndex) ?: continue
                val mimeType = it.getString(mimeTypeIndex)
                val childUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    childDocumentId,
                )
                val childDestination = File(destination, safFileName(displayName))
                if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    if (!childDestination.exists() && !childDestination.mkdirs()) {
                        budget.inaccessibleCount += 1
                        continue
                    }
                    materializeSafDirectory(
                        treeUri,
                        childDocumentId,
                        stagingRoot,
                        childDestination,
                        budget,
                        audioFiles,
                    )
                    continue
                }
                if (!isSafScanCandidate(displayName)) {
                    continue
                }
                if (budget.fileCount >= maximumSafMaterializedFiles) {
                    throw IllegalStateException("The selected folder has too many supported files.")
                }
                try {
                    copySafDocument(childUri, childDestination, budget)
                    budget.fileCount += 1
                    if (isSafAudioFile(displayName)) {
                        audioFiles.add(
                            mapOf(
                                "relativePath" to childDestination
                                    .relativeTo(stagingRoot)
                                    .invariantSeparatorsPath,
                                "sourceUri" to childUri.toString(),
                            ),
                        )
                    }
                } catch (_: SecurityException) {
                    childDestination.delete()
                    budget.inaccessibleCount += 1
                } catch (_: IOException) {
                    childDestination.delete()
                    budget.inaccessibleCount += 1
                }
            }
        } ?: run {
            budget.inaccessibleCount += 1
        }
    }

    private fun copySafDocument(sourceUri: Uri, destination: File, budget: SafMaterializationBudget) {
        val input = contentResolver.openInputStream(sourceUri)
            ?: throw IOException("Android could not read a selected document.")
        input.use { source ->
            FileOutputStream(destination).use { output ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = source.read(buffer)
                    if (read <= 0) {
                        break
                    }
                    budget.byteCount += read.toLong()
                    if (budget.byteCount > maximumSafMaterializedBytes) {
                        throw IllegalStateException("The selected folder is too large to scan safely.")
                    }
                    output.write(buffer, 0, read)
                }
            }
        }
    }

    private fun discardAudioTreeMaterialization(stagingRootPath: String?) {
        if (stagingRootPath.isNullOrBlank()) {
            return
        }
        val stagingParent = File(cacheDir, safMaterializationDirectoryName).canonicalFile
        val candidate = try {
            File(stagingRootPath).canonicalFile
        } catch (_: IOException) {
            return
        }
        if (candidate.parentFile == stagingParent) {
            candidate.deleteRecursively()
        }
    }

    private fun isSafScanCandidate(name: String): Boolean {
        val extension = name.substringAfterLast('.', "").lowercase()
        return extension in safAudioExtensions || extension in safSidecarExtensions
    }

    private fun isSafAudioFile(name: String): Boolean {
        return name.substringAfterLast('.', "").lowercase() in safAudioExtensions
    }

    private fun safFileName(value: String): String {
        val sanitized = value.trim().replace('/', '_').replace('\\\\', '_')
        return if (sanitized.isEmpty() || sanitized == "." || sanitized == "..") {
            "document"
        } else {
            sanitized
        }
    }

    private companion object {
        const val visualizerPermissionRequestCode = 7318
        const val audioLibraryPermissionRequestCode = 7319
        const val safTreeRequestCode = 7320
        const val safMaterializationDirectoryName = "aethertune_saf_imports"
        const val maximumSafMaterializedFiles = 5000
        const val maximumSafMaterializedBytes = 2L * 1024L * 1024L * 1024L
        val safAudioExtensions = setOf(
            "aac", "aif", "aifc", "aiff", "alac", "flac", "m4a", "m4b",
            "m4r", "mp3", "oga", "ogg", "opus", "wav", "wave", "wma",
        )
        val safSidecarExtensions = setOf("cue", "lrc", "srt", "ttml", "txt", "vtt")
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

private class SafMaterializationBudget {
    var fileCount = 0
    var byteCount = 0L
    var inaccessibleCount = 0
}

private class AetherTuneAudioVisualizer : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var visualizer: Visualizer? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun start(audioSessionId: Int): Boolean {
        stop()
        return try {
            val effect = Visualizer(audioSessionId)
            val captureRange = Visualizer.getCaptureSizeRange()
            val captureSize = captureRange.last().coerceAtMost(1024)
            effect.captureSize = captureSize
            val status = effect.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer,
                        waveform: ByteArray,
                        samplingRate: Int,
                    ) = Unit

                    override fun onFftDataCapture(
                        visualizer: Visualizer,
                        fft: ByteArray,
                        samplingRate: Int,
                    ) {
                        publishBands(fft)
                    }
                },
                Visualizer.getMaxCaptureRate() / 2,
                false,
                true,
            )
            if (status != Visualizer.SUCCESS) {
                effect.release()
                false
            } else {
                effect.enabled = true
                visualizer = effect
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    fun stop() {
        visualizer?.let { effect ->
            effect.enabled = false
            effect.release()
        }
        visualizer = null
    }

    private fun publishBands(fft: ByteArray) {
        if (fft.size < 4) {
            return
        }
        val bands = DoubleArray(16)
        val counts = IntArray(16)
        val pairCount = fft.size / 2
        for (index in 1 until pairCount) {
            val real = fft[index * 2].toInt().toDouble()
            val imaginary = fft[index * 2 + 1].toInt().toDouble()
            val magnitude = sqrt(real * real + imaginary * imaginary)
            val band = ((index - 1) * bands.size / (pairCount - 1))
                .coerceIn(0, bands.lastIndex)
            bands[band] += magnitude
            counts[band] += 1
        }
        val normalized = bands.indices.map { index ->
            val average = if (counts[index] == 0) 0.0 else bands[index] / counts[index]
            (ln(average + 1.0) / 5.0).coerceIn(0.0, 1.0)
        }
        mainHandler.post { eventSink?.success(normalized) }
    }
}

private class AetherTuneAudioVirtualizer {
    private var primary: Virtualizer? = null
    private var crossfade: Virtualizer? = null
    private var enabled = false
    private var strength: Short = 500

    fun attach(slot: String, audioSessionId: Int): Boolean {
        val effect = try {
            Virtualizer(0, audioSessionId)
        } catch (_: Exception) {
            return false
        }
        if (!apply(effect)) {
            effect.release()
            return false
        }
        when (slot) {
            "primary" -> {
                releasePrimary()
                primary = effect
            }
            "crossfade" -> {
                releaseCrossfade()
                crossfade = effect
            }
            else -> {
                effect.release()
                return false
            }
        }
        return true
    }

    fun setEnabled(enabled: Boolean): Boolean {
        this.enabled = enabled
        return applyToActiveEffects()
    }

    fun setStrength(strength: Int): Boolean {
        this.strength = strength.coerceIn(0, 1000).toShort()
        return applyToActiveEffects()
    }

    fun release() {
        releasePrimary()
        releaseCrossfade()
    }

    private fun applyToActiveEffects(): Boolean {
        var success = true
        primary?.let { success = apply(it) && success }
        crossfade?.let { success = apply(it) && success }
        return success
    }

    private fun apply(effect: Virtualizer): Boolean {
        return try {
            if (effect.strengthSupported) {
                effect.setStrength(strength)
            }
            effect.enabled = enabled
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun releasePrimary() {
        primary?.let { effect ->
            effect.enabled = false
            effect.release()
        }
        primary = null
    }

    private fun releaseCrossfade() {
        crossfade?.let { effect ->
            effect.enabled = false
            effect.release()
        }
        crossfade = null
    }
}
"""

_OFFLINE_CACHE_JOB_KOTLIN = """package dev.aethertune.aethertune

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class AetherTuneOfflineCacheJobService : JobService() {
    private var activeEngine: FlutterEngine? = null
    private var activeParameters: JobParameters? = null

    override fun onStartJob(parameters: JobParameters): Boolean {
        if (activeEngine != null) {
            return false
        }
        activeParameters = parameters
        val engine = FlutterEngine(applicationContext)
        activeEngine = engine
        GeneratedPluginRegistrant.registerWith(engine)
        MethodChannel(
            engine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "complete") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val hasPendingWork = call.argument<Boolean>("hasPendingWork") ?: true
            val nextRunDelayMillis =
                call.argument<Number>("nextRunDelayMilliseconds")?.toLong()
            result.success(null)
            finish(hasPendingWork, nextRunDelayMillis)
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                dartEntrypoint,
            ),
        )
        return true
    }

    override fun onStopJob(parameters: JobParameters): Boolean {
        disposeEngine()
        return true
    }

    private fun finish(hasPendingWork: Boolean, nextRunDelayMillis: Long?) {
        val parameters = activeParameters ?: return
        activeParameters = null
        disposeEngine()
        jobFinished(parameters, hasPendingWork)
        if (!hasPendingWork && nextRunDelayMillis != null) {
            schedule(applicationContext, nextRunDelayMillis)
        }
    }

    private fun disposeEngine() {
        activeEngine?.destroy()
        activeEngine = null
    }

    companion object {
        private const val jobId = 18472
        private const val channelName = "dev.aethertune/offline_cache_background"
        private const val dartEntrypoint = "offlineCacheBackgroundEntrypoint"

        fun schedule(
            context: Context,
            requestedMinimumLatencyMillis: Long? = null,
        ): Boolean {
            val scheduler = context.getSystemService(JobScheduler::class.java)
                ?: return false
            val minimumLatencyMillis = (requestedMinimumLatencyMillis
                ?: defaultMinimumLatencyMillis).coerceIn(
                defaultMinimumLatencyMillis,
                maximumMinimumLatencyMillis,
            )
            val job = JobInfo.Builder(
                jobId,
                ComponentName(context, AetherTuneOfflineCacheJobService::class.java),
            )
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setMinimumLatency(minimumLatencyMillis)
                .setPersisted(true)
                .setBackoffCriteria(30_000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                .build()
            return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
        }

        fun cancel(context: Context) {
            context.getSystemService(JobScheduler::class.java)?.cancel(jobId)
        }

        private const val defaultMinimumLatencyMillis = 30_000L
        private const val maximumMinimumLatencyMillis = 7 * 24 * 60 * 60 * 1_000L
    }
}
"""

_APP_DELEGATE_SWIFT = """import AVKit
import BackgroundTasks
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private static let offlineCacheTaskIdentifier = "dev.aethertune.aethertune.offline-cache"
    private var audioRoutePickerController: UIViewController?
    private var activeOfflineCacheTask: BGProcessingTask?
    private var activeOfflineCacheEngine: FlutterEngine?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        registerOfflineCacheTask()
        if let flutterController = window?.rootViewController as? FlutterViewController {
            let channel = FlutterMethodChannel(
                name: "dev.aethertune/audio_routes",
                binaryMessenger: flutterController.binaryMessenger
            )
            channel.setMethodCallHandler { [weak self, weak flutterController] call, result in
                guard call.method == "showAudioRoutePicker" else {
                    result(FlutterMethodNotImplemented)
                    return
                }
                guard let appDelegate = self, let controller = flutterController else {
                    result(false)
                    return
                }
                result(appDelegate.showAudioRoutePicker(from: controller))
            }
            configureOfflineCacheChannel(
                messenger: flutterController.binaryMessenger
            )
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func registerOfflineCacheTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.offlineCacheTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            guard let self else {
                processingTask.setTaskCompleted(success: false)
                return
            }
            self.runOfflineCacheTask(processingTask)
        }
    }

    private func configureOfflineCacheChannel(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "dev.aethertune/offline_cache_background",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "schedule":
                let arguments = call.arguments as? [String: Any]
                let delay = (arguments?["minimumLatencyMilliseconds"] as? NSNumber)?.doubleValue
                result(self?.scheduleOfflineCacheTask(afterMilliseconds: delay) ?? false)
            case "cancel":
                BGTaskScheduler.shared.cancel(
                    taskRequestWithIdentifier: Self.offlineCacheTaskIdentifier
                )
                result(nil)
            case "complete":
                let arguments = call.arguments as? [String: Any]
                let hasPendingWork = (arguments?["hasPendingWork"] as? Bool) ?? true
                let nextDelay = (arguments?["nextRunDelayMilliseconds"] as? NSNumber)?.doubleValue
                self?.completeOfflineCacheTask(
                    hasPendingWork: hasPendingWork,
                    nextRunDelayMilliseconds: nextDelay
                )
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func scheduleOfflineCacheTask(afterMilliseconds delay: Double?) -> Bool {
        let request = BGProcessingTaskRequest(
            identifier: Self.offlineCacheTaskIdentifier
        )
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        let milliseconds = max(30_000, delay ?? 30_000)
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: milliseconds / 1_000
        )
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            return false
        }
    }

    private func runOfflineCacheTask(_ task: BGProcessingTask) {
        guard activeOfflineCacheTask == nil else {
            task.setTaskCompleted(success: false)
            return
        }
        let engine = FlutterEngine(name: "aethertune-offline-cache")
        activeOfflineCacheTask = task
        activeOfflineCacheEngine = engine
        task.expirationHandler = { [weak self] in
            self?.finishOfflineCacheTask(success: false)
        }
        GeneratedPluginRegistrant.register(with: engine)
        configureOfflineCacheChannel(messenger: engine.binaryMessenger)
        if !engine.run(withEntrypoint: "offlineCacheBackgroundEntrypoint") {
            finishOfflineCacheTask(success: false)
        }
    }

    private func completeOfflineCacheTask(
        hasPendingWork: Bool,
        nextRunDelayMilliseconds: Double?
    ) {
        if hasPendingWork {
            _ = scheduleOfflineCacheTask(afterMilliseconds: 30_000)
        } else if let nextRunDelayMilliseconds {
            _ = scheduleOfflineCacheTask(afterMilliseconds: nextRunDelayMilliseconds)
        }
        finishOfflineCacheTask(success: true)
    }

    private func finishOfflineCacheTask(success: Bool) {
        let task = activeOfflineCacheTask
        activeOfflineCacheTask = nil
        activeOfflineCacheEngine?.destroyContext()
        activeOfflineCacheEngine = nil
        task?.setTaskCompleted(success: success)
    }

    private func showAudioRoutePicker(from controller: UIViewController) -> Bool {
        let pickerController = UIViewController()
        pickerController.title = "Audio output"
        pickerController.view.backgroundColor = .systemBackground

        let picker = AVRoutePickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        pickerController.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: pickerController.view.centerXAnchor),
            picker.centerYAnchor.constraint(equalTo: pickerController.view.centerYAnchor),
            picker.widthAnchor.constraint(equalToConstant: 88),
            picker.heightAnchor.constraint(equalToConstant: 56),
        ])
        pickerController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissAudioRoutePicker)
        )

        let navigationController = UINavigationController(rootViewController: pickerController)
        navigationController.modalPresentationStyle = .formSheet
        audioRoutePickerController = navigationController
        controller.present(navigationController, animated: true)
        return true
    }

    @objc private func dismissAudioRoutePicker() {
        audioRoutePickerController?.dismiss(animated: true)
        audioRoutePickerController = nil
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


def _ensure_metadata_value(parent: ET.Element, name: str, value: str) -> None:
    for metadata in parent.findall("meta-data"):
        if metadata.get(f"{ANDROID}name") == name:
            metadata.attrib.pop(f"{ANDROID}resource", None)
            metadata.set(f"{ANDROID}value", value)
            return
    ET.SubElement(
        parent,
        "meta-data",
        {
            f"{ANDROID}name": name,
            f"{ANDROID}value": value,
        },
    )


def _ensure_deep_link_intent_filter(activity: ET.Element) -> None:
    intent_filter = next(
        (
            candidate
            for candidate in activity.findall("intent-filter")
            if any(
                action.get(f"{ANDROID}name") == "android.intent.action.VIEW"
                for action in candidate.findall("action")
            )
            and any(
                data.get(f"{ANDROID}scheme") == DEEP_LINK_SCHEME
                for data in candidate.findall("data")
            )
        ),
        None,
    )
    if intent_filter is None:
        intent_filter = ET.SubElement(activity, "intent-filter")
    for category in (
        "android.intent.category.DEFAULT",
        "android.intent.category.BROWSABLE",
    ):
        if not any(
            item.get(f"{ANDROID}name") == category
            for item in intent_filter.findall("category")
        ):
            ET.SubElement(
                intent_filter,
                "category",
                {f"{ANDROID}name": category},
            )
    if not any(
        action.get(f"{ANDROID}name") == "android.intent.action.VIEW"
        for action in intent_filter.findall("action")
    ):
        ET.SubElement(
            intent_filter,
            "action",
            {f"{ANDROID}name": "android.intent.action.VIEW"},
        )
    if not any(
        data.get(f"{ANDROID}scheme") == DEEP_LINK_SCHEME
        for data in intent_filter.findall("data")
    ):
        ET.SubElement(
            intent_filter,
            "data",
            {f"{ANDROID}scheme": DEEP_LINK_SCHEME},
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


def _offline_cache_job_path(manifest_path: Path) -> Path:
    return (
        manifest_path.parents[2]
        / "src/main/kotlin/dev/aethertune/aethertune"
        / "AetherTuneOfflineCacheJobService.kt"
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
    background_job_source = _offline_cache_job_path(manifest_path)
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
        (background_job_source, _OFFLINE_CACHE_JOB_KOTLIN),
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
    activity.set(f"{ANDROID}exported", "true")
    activity.set(f"{ANDROID}supportsPictureInPicture", "true")
    _ensure_metadata_value(activity, "flutter_deeplinking_enabled", "false")
    _ensure_deep_link_intent_filter(activity)
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

    offline_cache_job = _find_named(
        application,
        "service",
        OFFLINE_CACHE_JOB_SERVICE_NAME,
    )
    if offline_cache_job is None:
        offline_cache_job = ET.SubElement(application, "service")
    offline_cache_job.attrib.update(
        {
            f"{ANDROID}name": OFFLINE_CACHE_JOB_SERVICE_NAME,
            f"{ANDROID}exported": "true",
            f"{ANDROID}permission": "android.permission.BIND_JOB_SERVICE",
        }
    )

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
        f"minSdk = maxOf(flutter.minSdkVersion, {ANDROID_MIN_SDK})",
        gradle,
    )
    if replacements == 0:
        gradle, replacements = re.subn(
            r"minSdkVersion\s+flutter\.minSdkVersion",
            f"minSdkVersion Math.max(flutter.minSdkVersion, {ANDROID_MIN_SDK})",
            gradle,
        )
    if replacements == 0 and not _has_android_min_sdk_floor(gradle):
        raise RuntimeError(f"No Android minimum SDK declaration in {gradle_path}")
    gradle_path.write_text(gradle, encoding="utf-8")


def _has_android_min_sdk_floor(gradle: str) -> bool:
    minimum = ANDROID_MIN_SDK
    patterns = (
        rf"(?:minSdk\s*=|minSdkVersion)\s*{minimum}\b",
        rf"minSdk\s*=\s*maxOf\(\s*flutter\.minSdkVersion\s*,\s*{minimum}\s*\)",
        rf"minSdkVersion\s+Math\.max\(\s*flutter\.minSdkVersion\s*,\s*{minimum}\s*\)",
    )
    return any(re.search(pattern, gradle) for pattern in patterns)


def configure_ios(info_plist_path: Path, app_delegate_path: Path) -> None:
    with info_plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    modes = list(info.get("UIBackgroundModes", []))
    if "audio" not in modes:
        modes.append("audio")
    if "processing" not in modes:
        modes.append("processing")
    info["UIBackgroundModes"] = modes
    info["BGTaskSchedulerPermittedIdentifiers"] = [
        "dev.aethertune.aethertune.offline-cache"
    ]
    info["FlutterDeepLinkingEnabled"] = False
    _configure_apple_url_scheme(info)
    with info_plist_path.open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)
    app_delegate_path.parent.mkdir(parents=True, exist_ok=True)
    app_delegate_path.write_text(_APP_DELEGATE_SWIFT, encoding="utf-8")


def configure_macos(info_plist_path: Path) -> None:
    with info_plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    _configure_apple_url_scheme(info)
    with info_plist_path.open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)


def configure_linux_deep_links(source_path: Path) -> None:
    source = source_path.read_text(encoding="utf-8")
    if "gtk_application_get_windows" not in source:
        marker = "  MyApplication* self = MY_APPLICATION(application);\n"
        replacement = marker + """
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }
"""
        if marker not in source:
            raise RuntimeError("Linux application activation hook is missing")
        source = source.replace(marker, replacement, 1)
    if "G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN" not in source:
        source, replacements = re.subn(
            r'("flags",\s*)G_APPLICATION_NON_UNIQUE,',
            r"\1G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN,",
            source,
        )
        if replacements == 0:
            raise RuntimeError("Linux application flags are not configurable")
    if "return FALSE;" not in source:
        source, replacements = re.subn(
            r"(\*exit_status = 0;\s*)return TRUE;",
            r"\1return FALSE;",
            source,
            count=1,
        )
        if replacements == 0:
            raise RuntimeError("Linux command-line handler is not configurable")
    source_path.write_text(source, encoding="utf-8")


def configure_windows_deep_links(source_path: Path, cmake_path: Path) -> None:
    source = source_path.read_text(encoding="utf-8")
    if "app_links/app_links_plugin_c_api.h" not in source:
        marker = "#include <windows.h>\n"
        if marker not in source:
            raise RuntimeError("Windows platform include is missing")
        source = source.replace(
            marker,
            marker + '#include "app_links/app_links_plugin_c_api.h"\n#include <string>\n',
            1,
        )
    if "RegisterAetherTuneUrlScheme" not in source:
        marker = "int APIENTRY wWinMain("
        if marker not in source:
            raise RuntimeError("Windows entrypoint is missing")
        registration = r'''void RegisterAetherTuneUrlScheme() {
  wchar_t executable_path[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) {
    return;
  }

  HKEY protocol_key = nullptr;
  if (RegCreateKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Classes\\aethertune",
          0,
          nullptr,
          0,
          KEY_SET_VALUE | KEY_CREATE_SUB_KEY,
          nullptr,
          &protocol_key,
          nullptr) != ERROR_SUCCESS) {
    return;
  }
  const wchar_t description[] = L"URL:AetherTune Protocol";
  RegSetValueExW(
      protocol_key,
      nullptr,
      0,
      REG_SZ,
      reinterpret_cast<const BYTE*>(description),
      sizeof(description));
  const wchar_t protocol[] = L"";
  RegSetValueExW(
      protocol_key,
      L"URL Protocol",
      0,
      REG_SZ,
      reinterpret_cast<const BYTE*>(protocol),
      sizeof(protocol));

  HKEY command_key = nullptr;
  if (RegCreateKeyExW(
          protocol_key,
          L"shell\\open\\command",
          0,
          nullptr,
          0,
          KEY_SET_VALUE,
          nullptr,
          &command_key,
          nullptr) == ERROR_SUCCESS) {
    const std::wstring command =
        L"\"" + std::wstring(executable_path) + L"\" \"%1\"";
    RegSetValueExW(
        command_key,
        nullptr,
        0,
        REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.length() + 1) * sizeof(wchar_t)));
    RegCloseKey(command_key);
  }
  RegCloseKey(protocol_key);
}

'''
        source = source.replace(marker, registration + marker, 1)
    if "SendAppLinkToInstance()" not in source:
        pattern = re.compile(r"(int APIENTRY wWinMain\([\s\S]*?\) \{\n)")
        source, replacements = pattern.subn(
            r"\1  RegisterAetherTuneUrlScheme();\n"
            "  if (SendAppLinkToInstance()) {\n"
            "    return EXIT_SUCCESS;\n"
            "  }\n",
            source,
            count=1,
        )
        if replacements == 0:
            raise RuntimeError("Windows entrypoint is not configurable")
    source_path.write_text(source, encoding="utf-8")

    cmake = cmake_path.read_text(encoding="utf-8")
    if "advapi32" not in cmake:
        pattern = re.compile(
            r"(target_link_libraries\(\$\{BINARY_NAME\} PRIVATE [^\n]+)\)"
        )
        cmake, replacements = pattern.subn(r"\1 advapi32)", cmake, count=1)
        if replacements == 0:
            raise RuntimeError("Windows runner libraries are not configurable")
    cmake_path.write_text(cmake, encoding="utf-8")


def _configure_apple_url_scheme(info: dict[str, object]) -> None:
    types = list(info.get("CFBundleURLTypes", []))
    target = next(
        (
            item
            for item in types
            if isinstance(item, dict)
            and DEEP_LINK_SCHEME in item.get("CFBundleURLSchemes", [])
        ),
        None,
    )
    if target is None:
        target = {}
        types.append(target)
    target["CFBundleURLName"] = DEEP_LINK_URL_NAME
    target["CFBundleURLSchemes"] = [DEEP_LINK_SCHEME]
    info["CFBundleURLTypes"] = types


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
    if activity.get(f"{ANDROID}exported") != "true":
        raise RuntimeError("Android activity is not exported for deep links")
    if activity.get(f"{ANDROID}supportsPictureInPicture") != "true":
        raise RuntimeError("Android Picture-in-Picture is not enabled")
    deep_link_metadata = next(
        (
            metadata
            for metadata in activity.findall("meta-data")
            if metadata.get(f"{ANDROID}name") == "flutter_deeplinking_enabled"
        ),
        None,
    )
    if (
        deep_link_metadata is None
        or deep_link_metadata.get(f"{ANDROID}value") != "false"
    ):
        raise RuntimeError("Android app_links ownership is not configured")
    has_deep_link_filter = any(
        any(
            action.get(f"{ANDROID}name") == "android.intent.action.VIEW"
            for action in intent_filter.findall("action")
        )
        and any(
            data.get(f"{ANDROID}scheme") == DEEP_LINK_SCHEME
            for data in intent_filter.findall("data")
        )
        and {
            category.get(f"{ANDROID}name")
            for category in intent_filter.findall("category")
        }.issuperset(
            {
                "android.intent.category.DEFAULT",
                "android.intent.category.BROWSABLE",
            }
        )
        for intent_filter in activity.findall("intent-filter")
    )
    if not has_deep_link_filter:
        raise RuntimeError("Android AetherTune deep-link intent filter is missing")
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
    offline_cache_job = _find_named(
        application,
        "service",
        OFFLINE_CACHE_JOB_SERVICE_NAME,
    )
    if offline_cache_job is None:
        raise RuntimeError("Android offline-cache job service is missing")
    if offline_cache_job.get(f"{ANDROID}exported") != "true":
        raise RuntimeError("Android offline-cache job service must be scheduler-visible")
    if (
        offline_cache_job.get(f"{ANDROID}permission")
        != "android.permission.BIND_JOB_SERVICE"
    ):
        raise RuntimeError("Android offline-cache job service is not protected")
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
    background_job_source = _offline_cache_job_path(manifest_path)
    if not all(
        path.is_file()
        for path in (
            widget_info,
            widget_layout,
            widget_source,
            activity_source,
            background_job_source,
        )
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
        "dev.aethertune/pinned_shortcuts",
        "ShortcutManager",
        "requestPinShortcut",
        "dev.aethertune/audio_routes",
        "Settings.ACTION_SOUND_SETTINGS",
        "dev.aethertune/video_picture_in_picture",
        "PictureInPictureParams.Builder",
        "FEATURE_PICTURE_IN_PICTURE",
        "dev.aethertune/storage_access",
        "requestAudioLibraryAccess",
        "READ_MEDIA_AUDIO",
        "READ_EXTERNAL_STORAGE",
        "updatePlaybackWidgets",
        "dev.aethertune/audio_visualizer",
        "AetherTuneAudioVisualizer",
        "Visualizer.getMaxCaptureRate",
        "dev.aethertune/audio_virtualizer",
        "AetherTuneAudioVirtualizer",
        "Virtualizer(0, audioSessionId)",
        "dev.aethertune/offline_cache_background",
        "AetherTuneOfflineCacheJobService.schedule",
        "AetherTuneOfflineCacheJobService.cancel(applicationContext)",
        "dev.aethertune/system_downloads",
        "exportVerifiedFileToDownloads",
        "MediaStore.Downloads.getContentUri",
        "IS_PENDING",
        "Verified cache changed before export completed.",
    )
    if not all(snippet in activity_source_text for snippet in required_activity_snippets):
        raise RuntimeError("Android playback widget state bridge is missing")
    background_job_text = background_job_source.read_text(encoding="utf-8")
    required_background_job_snippets = (
        "JobScheduler",
        "setPersisted(true)",
        "setMinimumLatency(minimumLatencyMillis)",
        "setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)",
        "GeneratedPluginRegistrant.registerWith",
        "offlineCacheBackgroundEntrypoint",
        "hasPendingWork",
        "nextRunDelayMillis",
        "maximumMinimumLatencyMillis",
        "jobFinished(parameters, hasPendingWork)",
    )
    if not all(snippet in background_job_text for snippet in required_background_job_snippets):
        raise RuntimeError("Android offline-cache job source is incomplete")
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
    if not _has_android_min_sdk_floor(gradle):
        raise RuntimeError("Android minimum SDK floor is not 23")


def verify_ios(info_plist_path: Path, app_delegate_path: Path) -> None:
    with info_plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    if "audio" not in info.get("UIBackgroundModes", []):
        raise RuntimeError("iOS audio background mode is missing")
    if "processing" not in info.get("UIBackgroundModes", []):
        raise RuntimeError("iOS background processing mode is missing")
    if info.get("BGTaskSchedulerPermittedIdentifiers") != [
        "dev.aethertune.aethertune.offline-cache"
    ]:
        raise RuntimeError("iOS offline-cache task identifier is missing")
    if info.get("FlutterDeepLinkingEnabled") is not False:
        raise RuntimeError("iOS app_links ownership is not configured")
    _verify_apple_url_scheme(info, "iOS")
    app_delegate_source = app_delegate_path.read_text(encoding="utf-8")
    required_route_picker_snippets = (
        "AVRoutePickerView",
        "dev.aethertune/audio_routes",
        "showAudioRoutePicker",
        "BGProcessingTaskRequest",
        "dev.aethertune/offline_cache_background",
        "offlineCacheBackgroundEntrypoint",
        "requiresNetworkConnectivity = true",
        "expirationHandler",
        "setTaskCompleted",
    )
    if not all(snippet in app_delegate_source for snippet in required_route_picker_snippets):
        raise RuntimeError("iOS audio route picker is not configured")


def verify_macos(info_plist_path: Path) -> None:
    with info_plist_path.open("rb") as stream:
        info = plistlib.load(stream)
    _verify_apple_url_scheme(info, "macOS")


def verify_linux_deep_links(source_path: Path) -> None:
    source = source_path.read_text(encoding="utf-8")
    required = (
        "gtk_application_get_windows",
        "gtk_window_present",
        "return FALSE;",
        "G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN",
    )
    if not all(snippet in source for snippet in required):
        raise RuntimeError("Linux deep-link lifecycle is not configured")


def verify_windows_deep_links(source_path: Path, cmake_path: Path) -> None:
    source = source_path.read_text(encoding="utf-8")
    required = (
        "app_links/app_links_plugin_c_api.h",
        "RegisterAetherTuneUrlScheme",
        "Software\\\\Classes\\\\aethertune",
        "SendAppLinkToInstance()",
    )
    if not all(snippet in source for snippet in required):
        raise RuntimeError("Windows deep-link routing is not configured")
    if "advapi32" not in cmake_path.read_text(encoding="utf-8"):
        raise RuntimeError("Windows deep-link registry library is not linked")


def _verify_apple_url_scheme(info: dict[str, object], platform: str) -> None:
    for item in info.get("CFBundleURLTypes", []):
        if not isinstance(item, dict):
            continue
        if (
            item.get("CFBundleURLName") == DEEP_LINK_URL_NAME
            and item.get("CFBundleURLSchemes") == [DEEP_LINK_SCHEME]
        ):
            return
    raise RuntimeError(f"{platform} AetherTune URL scheme is missing")


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
    ios_app_delegate = app_dir / "ios/Runner/AppDelegate.swift"
    ios_project = app_dir / "ios/Runner.xcodeproj/project.pbxproj"
    ios_framework_info = app_dir / "ios/Flutter/AppFrameworkInfo.plist"
    ios_debug_entitlements = app_dir / "ios/Runner/DebugProfile.entitlements"
    ios_release_entitlements = app_dir / "ios/Runner/Release.entitlements"
    macos_info = app_dir / "macos/Runner/Info.plist"
    macos_debug_entitlements = app_dir / "macos/Runner/DebugProfile.entitlements"
    macos_release_entitlements = app_dir / "macos/Runner/Release.entitlements"
    linux_application = app_dir / "linux/runner/my_application.cc"
    windows_main = app_dir / "windows/runner/main.cpp"
    windows_cmake = app_dir / "windows/runner/CMakeLists.txt"
    for path in (
        android_manifest,
        android_gradle,
        ios_info,
        ios_app_delegate,
        ios_project,
        ios_framework_info,
        macos_info,
        macos_debug_entitlements,
        macos_release_entitlements,
        linux_application,
        windows_main,
        windows_cmake,
    ):
        if not path.is_file():
            raise FileNotFoundError(path)

    configure_android(android_manifest, android_gradle)
    configure_ios(ios_info, ios_app_delegate)
    configure_macos(macos_info)
    configure_linux_deep_links(linux_application)
    configure_windows_deep_links(windows_main, windows_cmake)
    configure_ios_deployment_target(ios_project, ios_framework_info)
    configure_keychain_entitlements(ios_debug_entitlements)
    configure_keychain_entitlements(ios_release_entitlements)
    configure_keychain_entitlements(macos_debug_entitlements)
    configure_keychain_entitlements(macos_release_entitlements)
    configure_ios_code_sign_entitlements(ios_project)
    verify_android(android_manifest, android_gradle)
    verify_ios(ios_info, ios_app_delegate)
    verify_macos(macos_info)
    verify_linux_deep_links(linux_application)
    verify_windows_deep_links(windows_main, windows_cmake)
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
