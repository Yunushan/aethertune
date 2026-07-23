package dev.aethertune.aethertune

import android.Manifest
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
import android.provider.DocumentsContract
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/audio_visualizer/bands",
        ).setStreamHandler(audioVisualizer)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.aethertune/screenshot_protection",
        ).setMethodCallHandler { call, result ->
            if (call.method != "setEnabled") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (call.argument<Boolean>("enabled") == true) {
                window.setFlags(
                    WindowManager.LayoutParams.FLAG_SECURE,
                    WindowManager.LayoutParams.FLAG_SECURE,
                )
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            result.success(null)
        }
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
                } catch (_: java.io.IOException) {
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
            ?: throw java.io.IOException("Android could not read a selected document.")
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
        } catch (_: java.io.IOException) {
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
        val sanitized = value.trim().replace('/', '_').replace('\\', '_')
        return if (sanitized.isEmpty || sanitized == "." || sanitized == "..") {
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
