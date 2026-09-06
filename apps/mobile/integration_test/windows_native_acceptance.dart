import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aethertune/main.dart' as app;
import 'package:aethertune/src/data/library_storage.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/local_diagnostic_log.dart';
import 'package:aethertune/src/data/local_folder_scanner.dart';
import 'package:aethertune/src/domain/playlist.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_queue.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/player/player_state_store.dart';
import 'package:aethertune/src/ui/home_screen.dart';
import 'package:aethertune/src/ui/video_playback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:media_kit/media_kit.dart' as media;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secretKey = 'aethertune.windows.native.fixture.secret';
const _secret = 'synthetic-credential-not-a-real-account';
const _sentinelKey = 'aethertune.windows.native.fixture.unrelated';
const _evidence = r'C:\Evidence';
const _input = r'C:\Input';

// Build only for the Sandbox driver. The native runner registers a URL scheme
// before Dart starts, so this binary must never be launched on the host.
Future<void> main() async {
  if (!Platform.isWindows ||
      Platform.environment['USERNAME'] != 'WDAGUtilityAccount' ||
      Platform.environment['USERPROFILE'] != r'C:\Users\WDAGUtilityAccount' ||
      await File(p.join(_input, 'acceptance-fixture-v1')).readAsString() !=
          'aethertune-windows-native-acceptance-v1\n') {
    exit(2);
  }
  WidgetsFlutterBinding.ensureInitialized();
  final phase = Platform.environment['AETHERTUNE_ACCEPTANCE_PHASE'];
  final checks = <String>[];
  final frameworkErrors = <String>[];
  final report = <String, Object?>{
    'phase': phase,
    'pid': pid,
    'startedAt': DateTime.now().toUtc().toIso8601String(),
    'checks': checks,
    'scope':
        'Sandbox native migration, credentials, WAV transport, H264/VP9 rendering and video error UI; not physical audio, all codecs or signed installation',
  };
  var stage = 'guard';
  var code = 1;
  PlayerController? player;
  try {
    _require(phase == 'exercise' || phase == 'reopen', 'Unknown fixture phase');
    final support = await getApplicationSupportDirectory();
    _require(
      p.isWithin(r'C:\Users\WDAGUtilityAccount', support.path),
      'Profile escaped guest',
    );
    report['supportDirectory'] = support.path;
    final prefs = await SharedPreferences.getInstance();
    const vault = FlutterSecureStorage();
    if (phase == 'exercise') {
      stage = 'seed';
      _require(prefs.getKeys().isEmpty, 'Guest preferences were not empty');
      _require(
        await createLibraryStorage().read() == null,
        'Guest library was not empty',
      );
      final track = Track(
        id: 'native-windows-legacy',
        title: 'Native Legacy Track',
        artist: 'Acceptance Fixture',
        localPath: p.join(_input, 'media', 'Original.wav'),
        duration: const Duration(seconds: 10),
      );
      _require(
        await prefs.setString(
          'aethertune.tracks.v1',
          jsonEncode([track.toJson()]),
        ),
        'Legacy track save failed',
      );
      _require(
        await prefs.setString(
          'aethertune.playlists.v1',
          jsonEncode([
            Playlist(
              id: 'native-windows-playlist',
              name: 'Native Fixture',
              trackIds: [track.id],
            ).toJson(),
          ]),
        ),
        'Legacy playlist save failed',
      );
      _require(
        await prefs.setBool('aethertune.onboarding_completed.v1', true),
        'Onboarding seed failed',
      );
      _require(
        await prefs.setBool('aethertune.offline_mode.v1', true),
        'Offline seed failed',
      );
      _require(
        await prefs.setString(
          PlayerStateStore.queueKey,
          jsonEncode(
            TrackQueueSnapshot(
              tracks: [track],
              currentTrackId: track.id,
              currentIndex: 0,
            ).toJson(),
          ),
        ),
        'Legacy player queue seed failed',
      );
      _require(
        await prefs.setString(PlayerStateStore.settingsKey, '{"volume":0.05}'),
        'Legacy player settings seed failed',
      );
      _require(
        await prefs.setString(_sentinelKey, 'preserve-me'),
        'Sentinel seed failed',
      );
      _require(
        await prefs.setString(
          LocalDiagnosticLog.legacyStorageKey,
          jsonEncode([
            {'message': 'access_token=$_secret'},
          ]),
        ),
        'Diagnostic seed failed',
      );
      await vault.write(key: _secretKey, value: _secret);
      checks.add('real-preferences-and-vault-seeded');
    }
    _require(
      await vault.read(key: _secretKey) == _secret,
      'Credential round trip failed',
    );
    _require(
      prefs.getString(_sentinelKey) == 'preserve-me',
      'Unrelated preference lost',
    );
    checks.add(
      phase == 'reopen'
          ? 'credential-survived-process-restart'
          : 'credential-round-trip',
    );

    stage = 'production-startup';
    await app.main();
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      frameworkErrors.add(details.exceptionAsString());
      previousErrorHandler?.call(details);
    };
    await _until(() => _element<HomeScreen>() != null, stage);
    final home = _element<HomeScreen>()!;
    final library = home.read<LibraryStore>();
    player = home.read<PlayerController>();
    await player.loadPersistedQueue();
    await player.loadPersistedPlaybackSettings();
    _require(player.persistenceError == null, 'Player persistence failed');
    _require(
      playerStorageFactory() is FileLibraryStorage,
      'Player is not using file storage',
    );
    _require(
      await File(p.join(support.path, 'player', 'library.json')).exists(),
      'Missing native player snapshot',
    );
    final diagnostics = home.read<LocalDiagnosticLog>();
    _require(
      library.loaded && library.loadError == null,
      'Library failed to load',
    );
    _require(
      createLibraryStorage() is FileLibraryStorage,
      'Not using the native file backend',
    );
    _require(
      await createLibraryStorage().read() != null,
      'No native library snapshot',
    );
    _require(library.offlineModeEnabled, 'Fixture must remain offline');
    await prefs.reload();
    _require(
      !prefs.containsKey(LocalDiagnosticLog.legacyStorageKey),
      'Legacy diagnostics survived',
    );
    _require(
      !diagnostics.exportJson().contains(_secret),
      'Synthetic credential leaked into diagnostics',
    );
    checks.addAll([
      'production-plugin-startup',
      'native-library-migration',
      'legacy-diagnostic-cleanup',
    ]);
    final legacy = library.tracks.singleWhere(
      (track) => track.id == 'native-windows-legacy',
    );
    if (phase == 'exercise') {
      stage = 'import-and-save';
      _require(
        player.queue.length == 1 && player.current?.id == legacy.id,
        'Legacy player queue migration failed',
      );
      _require(
        (player.volume - 0.05).abs() < 0.001 && !player.isPlaying,
        'Legacy settings migration or no-autoplay failed',
      );
      checks.add('native-player-queue-and-settings-migration');
      _require(library.tracks.length == 1, 'Unexpected initial library');
      final scanned = await scanLocalFilesInBackground([
        p.join(_input, 'media', 'Imported.wav'),
      ]);
      _require(scanned.tracks.length == 1, 'Native file scanner failed');
      await library.addTracks(scanned.tracks);
      await library.toggleFavorite(legacy.id);
      await library.setTrackRating(legacy.id, 4);
      await library.addTrackToPlaylist(
        'native-windows-playlist',
        scanned.tracks.single.id,
      );
      _require(library.saveError == null, 'Library mutation save failed');
      _require(
        await player.createSavedQueue('Native alternate') != null,
        'Named queue save failed',
      );
      checks.add('native-scan-and-library-mutations');

      stage = 'audio-decode';
      final queue = [legacy, scanned.tracks.single];
      await player.setVolume(0.05);
      await player.playTrack(queue.first, queue: queue, queueIndex: 0);
      await _until(
        () => player!.isPlaying && player.position.inMilliseconds >= 700,
        stage,
      );
      _require(
        (player.duration.inMilliseconds - 10000).abs() < 500,
        'Incorrect WAV duration',
      );
      checks.add('wav-native-decode-and-position-progress');
      stage = 'native-media-pause';
      await _key('pause', 0xb3);
      await _until(() => !player!.isPlaying, stage);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final paused = player.position;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _require(
        (player.position - paused).inMilliseconds.abs() < 200,
        'Paused position kept moving',
      );
      await player.seek(const Duration(seconds: 3));
      await _until(
        () => (player!.position.inMilliseconds - 3000).abs() < 500,
        'audio-seek',
      );
      stage = 'native-media-resume';
      await _key('resume', 0xb3);
      await _until(
        () => player!.isPlaying && player.position.inMilliseconds > 3500,
        stage,
      );
      stage = 'native-media-next';
      await _key('next', 0xb0);
      await _until(
        () => player!.current?.id == queue.last.id && player.isPlaying,
        stage,
      );
      await _until(
        () => player!.position.inMilliseconds > 500,
        'second-track-decode',
      );
      stage = 'native-media-previous';
      await _key('previous', 0xb1);
      await _until(
        () => player!.current?.id == legacy.id && player.isPlaying,
        stage,
      );
      checks.add('os-media-keys-pause-resume-next-previous-and-seek');
      await player.stop();

      stage = 'video';
      await _exerciseVideo(checks);
    } else {
      stage = 'reopen';
      _require(library.tracks.length == 2, 'Imported track lost after restart');
      _require(
        legacy.isFavorite && legacy.rating == 4,
        'Favorite or rating lost after restart',
      );
      _require(
        library.playlists.single.trackIds.length == 2,
        'Playlist mutation lost after restart',
      );
      _require(!player.isPlaying, 'Unexpected autoplay after restart');
      checks.add('native-library-and-playlist-survived-process-restart');
      _require(player.queue.length == 2, 'Player queue lost after restart');
      _require(
        player.savedQueues.any((queue) => queue.name == 'Native alternate'),
        'Named queue lost after restart',
      );
      _require(
        (player.volume - 0.05).abs() < 0.001,
        'Player settings lost after restart',
      );
      _require(
        prefs.getString(PlayerStateStore.settingsKey) == '{"volume":0.05}',
        'Legacy player settings were modified',
      );
      checks.add('native-player-queues-and-settings-survived-process-restart');
    }
    await player.stop();
    runApp(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(seconds: 1));
    _require(frameworkErrors.isEmpty, 'Framework errors: $frameworkErrors');
    checks.add('no-framework-errors');
    report['status'] = 'passed';
    code = 0;
  } on Object catch (error, stack) {
    report['status'] = 'failed';
    report['stage'] = stage;
    report['error'] = error.toString();
    report['stack'] = stack.toString();
    report['frameworkErrors'] = frameworkErrors;
    await _json('failure-capture-request.json', {'pid': pid, 'phase': phase});
    final captureDeadline = Stopwatch()..start();
    while (!File(p.join(_evidence, '$phase-failure-captured')).existsSync() &&
        captureDeadline.elapsed.inSeconds < 5) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } finally {
    report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    await _json('$phase.json', report);
  }
  exit(code);
}

Future<void> _exerciseVideo(List<String> checks) async {
  for (final fixture in [('Colors.mp4', 'h264'), ('Colors.webm', 'vp9')]) {
    final opened = await _openVideo(fixture.$1);
    final controller = opened.controller;
    _require(
      controller != null,
      '${fixture.$2}: video failed before attachment',
    );
    final diagnostics = _VideoDiagnostics(controller!, fixture.$2);
    try {
      await _verifyVideo(checks, opened.boundary, controller, fixture.$2);
    } on Object {
      await diagnostics.save();
      rethrow;
    } finally {
      await diagnostics.dispose();
    }
    await _closeVideo();
  }

  final retryFile = File(
    p.join(Directory.systemTemp.path, 'aethertune-native-retry.mp4'),
  );
  _require(
    p.isWithin(r'C:\Users\WDAGUtilityAccount', retryFile.path),
    'Retry fixture escaped the guest profile',
  );
  await File(p.join(_input, 'media', 'Invalid.mp4')).copy(retryFile.path);
  final invalid = await _openVideo('Invalid.mp4', source: retryFile.uri);
  await _until(_hasVideoError, 'invalid-video-visible-error');
  _verifyVideoErrorUi();
  await _captureVideoDesktop('invalid');
  final retry =
      _element<IconButton>(
            where: (button) => button.tooltip == 'Retry video',
            within: _element<VideoPlaybackScreen>(),
          )!.widget
          as IconButton;
  await File(p.join(_input, 'media', 'Colors.mp4')).copy(retryFile.path);
  retry.onPressed!();
  await _until(() => _element<Video>() != null, 'repaired-video-retry');
  final retried = (_element<Video>()!.widget as Video).controller;
  await _verifyVideo(checks, invalid.boundary, retried, 'retry');
  _require(!_hasVideoError(), 'Video error remained after successful retry');
  checks.add('native-invalid-video-visible-error-and-repaired-source-retry');
  await _json('video-invalid.json', {
    'status': 'visible-error-then-repaired-source-retry-decoded-and-rendered',
  });
  await _closeVideo();

  // APNG is a diagnostic image-format control, not a replacement for MP4/WebM.
  final apng = await _openVideo('Colors.apng');
  await _until(
    () => _hasVideoError() || (apng.controller?.rect.value?.width ?? 0) > 0,
    'apng-decoded-or-visible-error',
  );
  if (_hasVideoError()) {
    _verifyVideoErrorUi();
    await _captureVideoDesktop('apng');
    await _json('video-apng.json', {
      'status': 'unsupported-with-visible-error',
    });
    checks.add('apng-unsupported-format-visible-error');
  } else {
    await _verifyVideo(checks, apng.boundary, apng.controller!, 'apng');
  }
  await _closeVideo();

  await _exerciseStalledVideo(checks, extendBackendTimeout: false);
  await _exerciseStalledVideo(checks, extendBackendTimeout: true);
}

Future<void> _exerciseStalledVideo(
  List<String> checks, {
  required bool extendBackendTimeout,
}) async {
  final name = extendBackendTimeout ? 'deadline' : 'network';
  final bytes = await File(p.join(_input, 'media', 'Colors.mp4')).readAsBytes();
  final data = ByteData.sublistView(bytes);
  var offset = 0;
  while (offset + 8 < bytes.length) {
    final length = data.getUint32(offset);
    _require(
      length >= 8 && offset + length <= bytes.length,
      'Invalid MP4 atom',
    );
    if (String.fromCharCodes(bytes.sublist(offset + 4, offset + 8)) == 'mdat') {
      offset += 8;
      break;
    }
    offset += length;
  }
  _require(offset > 8 && offset + 256 < bytes.length, 'Missing MP4 media data');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var stalled = true;
  var shuttingDown = false;
  var requests = 0;
  var trickledBytes = 0;
  final pending = <Future<void>>[];
  Future<void> serve(HttpRequest request) async {
    requests++;
    final response = request.response;
    response.headers.contentType = ContentType('video', 'mp4');
    response.contentLength = bytes.length;
    try {
      if (stalled) {
        response.add(bytes.sublist(0, offset));
        await response.flush();
        // Keep making network progress without enough payload for a frame.
        for (
          var index = offset;
          !shuttingDown && index < bytes.length;
          index++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          response.add([bytes[index]]);
          await response.flush();
          trickledBytes++;
        }
      } else {
        response.add(bytes);
      }
      await response.close();
    } on Exception {
      // Stop/disposal closes the incomplete response before Content-Length.
    } on StateError {
      // A closed response may reject the next trickled byte.
    }
  }

  final subscription = server.listen((request) {
    pending.add(serve(request));
  });
  final elapsed = Stopwatch()..start();
  _VideoDiagnostics? diagnostics;
  try {
    final opened = await _openVideo(
      'Trickling.mp4',
      source: Uri.parse('http://127.0.0.1:${server.port}/fixture.mp4'),
      playbackFactory: extendBackendTimeout ? _slowNetworkPlayback : null,
    );
    _require(opened.controller != null, 'Missing network video controller');
    diagnostics = _VideoDiagnostics(opened.controller!, name);
    await _until(
      _hasVideoError,
      'trickling-video-startup-deadline',
      timeout: const Duration(seconds: 40),
    );
    _verifyVideoErrorUi();
    final timeoutMilliseconds = elapsed.elapsedMilliseconds;
    await _json('video-$name-timeout.json', {
      'status': 'observed-error',
      'timeoutMilliseconds': timeoutMilliseconds,
      'requests': requests,
      'trickledBytes': trickledBytes,
      'backendNetworkTimeoutSeconds': extendBackendTimeout ? 60 : 5,
      'scope':
          'Guest loopback native HTTP; extended timeout is test-only fault injection',
    });
    _require(requests > 0 && trickledBytes >= 20, 'No real trickling request');
    _require(
      timeoutMilliseconds < 40000 &&
          (!extendBackendTimeout || timeoutMilliseconds >= 28000),
      'Did not observe the expected bounded startup failure',
    );
    if (extendBackendTimeout) {
      _require(
        diagnostics.errors.isEmpty,
        'Backend failed before the app deadline',
      );
    }
    await diagnostics.save();
    await diagnostics.dispose();
    diagnostics = null;
    await _captureVideoDesktop('$name-timeout');
    checks.add('native-trickling-http-$name-bounded-error');
    final initialRequests = requests;
    stalled = false;
    final retry =
        _element<IconButton>(
              where: (button) => button.tooltip == 'Retry video',
              within: _element<VideoPlaybackScreen>(),
            )!.widget
            as IconButton;
    retry.onPressed!();
    await _until(() => _element<Video>() != null, 'trickling-video-retry');
    final retried = (_element<Video>()!.widget as Video).controller;
    await _verifyVideo(checks, opened.boundary, retried, '$name-retry');
    _require(
      requests > initialRequests,
      'Retry did not reopen the HTTP source',
    );
    _require(!_hasVideoError(), 'Error remained after native network retry');
    checks.add('native-trickling-http-$name-retry-decoded-and-rendered');
    await _json('video-$name-timeout.json', {
      'status': 'passed',
      'timeoutMilliseconds': timeoutMilliseconds,
      'requests': requests,
      'trickledBytes': trickledBytes,
      'backendNetworkTimeoutSeconds': extendBackendTimeout ? 60 : 5,
      'scope':
          'Guest loopback native HTTP; extended timeout is test-only fault injection',
    });
    await _closeVideo();
  } on Object {
    await diagnostics?.save();
    rethrow;
  } finally {
    await diagnostics?.dispose();
    shuttingDown = true;
    await server.close(force: true);
    await subscription.cancel();
    await Future.wait(pending).timeout(const Duration(seconds: 5));
  }
}

VideoPlayback _slowNetworkPlayback() {
  final player = media.Player(platformPlayer: _SlowNetworkPlayer());
  final controller = VideoController(player);
  return (
    player: player,
    video: Video(controller: controller),
    firstFrame: controller.waitUntilFirstFrameRendered,
  );
}

// Test-only native fault injection: exercise the UI's deadline independently of
// mpv's shorter socket deadline. No production/native package source is modified.
class _SlowNetworkPlayer extends media.NativePlayer {
  _SlowNetworkPlayer()
    : super(configuration: const media.PlayerConfiguration());

  @override
  Future<void> open(
    media.Playable playable, {
    bool play = true,
    bool synchronized = true,
  }) async {
    await setProperty('network-timeout', '60');
    await super.open(playable, play: play, synchronized: synchronized);
  }
}

Future<({GlobalKey boundary, VideoController? controller})> _openVideo(
  String fileName, {
  Uri? source,
  VideoPlaybackFactory? playbackFactory,
}) async {
  final home = _element<HomeScreen>()!;
  final boundaryKey = GlobalKey();
  unawaited(
    Navigator.of(home).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RepaintBoundary(
          key: boundaryKey,
          child: VideoPlaybackScreen(
            source: source ?? File(p.join(_input, 'media', fileName)).uri,
            title: 'Native Video Fixture',
            playbackFactory: playbackFactory,
          ),
        ),
      ),
    ),
  );
  await _until(
    () => _element<Video>() != null || _hasVideoError(),
    'video-widget-or-error',
  );
  return (
    boundary: boundaryKey,
    controller: (_element<Video>()?.widget as Video?)?.controller,
  );
}

bool _hasVideoError() =>
    _element<Text>(
      where: (text) => text.data == 'Could not open this video.',
      within: _element<VideoPlaybackScreen>(),
    ) !=
    null;

void _verifyVideoErrorUi() {
  final screen = _element<VideoPlaybackScreen>()!;
  _require(_hasVideoError(), 'Missing visible video error');
  _require(
    _element<CircularProgressIndicator>(within: screen) == null,
    'Spinner remained after a native video error',
  );
  _require(
    _element<Video>(within: screen) == null,
    'Failed video surface remained mounted',
  );
  final retry = _element<IconButton>(
    where: (button) => button.tooltip == 'Retry video',
    within: screen,
  );
  _require(
    retry != null && (retry.widget as IconButton).onPressed != null,
    'Video retry was unavailable',
  );
}

Future<void> _closeVideo() async {
  Navigator.of(_element<VideoPlaybackScreen>()!).pop();
  await _until(
    () => _element<VideoPlaybackScreen>() == null,
    'video-route-disposed',
  );
}

Future<void> _captureVideoDesktop(String name) async {
  await _json('video-capture-request.json', {'pid': pid, 'name': name});
  await _until(
    () => File(p.join(_evidence, 'video-$name-desktop-captured')).existsSync(),
    'guest-video-desktop-capture-$name',
  );
}

Future<void> _verifyVideo(
  List<String> checks,
  GlobalKey boundaryKey,
  VideoController controller,
  String name,
) async {
  await controller.waitUntilFirstFrameRendered.timeout(
    const Duration(seconds: 30),
  );
  _require(controller.id.value != null, 'No native video texture');
  final decoderColors = <String>{};
  final renderedColors = <String>{};
  final timer = Stopwatch()..start();
  while ((decoderColors.length < 2 || renderedColors.length < 2) &&
      timer.elapsed.inSeconds < 12) {
    final decoded = await controller.player.screenshot(format: 'image/png');
    if (decoded != null) {
      final color = await _frameColor(decoded);
      if (color != null && decoderColors.add(color)) {
        await File(
          p.join(_evidence, '$name-decoded-$color.png'),
        ).writeAsBytes(decoded, flush: true);
      }
    }
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    _require(data != null, 'No rendered video capture');
    final bytes = data!.buffer.asUint8List();
    final color = await _frameColor(bytes);
    if (color != null && renderedColors.add(color)) {
      await File(
        p.join(_evidence, '$name-rendered-$color.png'),
      ).writeAsBytes(bytes, flush: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  _require(
    decoderColors.length == 2,
    '$name decoder did not produce both colors',
  );
  _require(
    renderedColors.length == 2,
    'Native Flutter video texture did not render both colors',
  );
  _require(
    controller.player.state.position > Duration.zero,
    'Video position did not advance',
  );
  await controller.player.pause();
  _require(!controller.player.state.playing, 'Video did not pause');
  final paused = controller.player.state.position;
  await Future<void>.delayed(const Duration(milliseconds: 350));
  _require(
    (controller.player.state.position - paused).inMilliseconds.abs() < 150,
    'Video position advanced while paused',
  );
  await controller.player.seek(const Duration(seconds: 2));
  await _until(
    () => (controller.player.state.position.inMilliseconds - 2000).abs() < 400,
    '$name-video-seek',
  );
  final resumedAt = controller.player.state.position;
  await controller.player.play();
  await _until(
    () =>
        controller.player.state.position >
        resumedAt + const Duration(milliseconds: 250),
    '$name-video-resume',
  );
  await controller.player.pause();
  checks.addAll([
    '$name-native-decode',
    '$name-moving-native-video-texture-pixel-check',
    '$name-video-pause-seek-resume',
  ]);
  await _json('video-$name.json', {
    'decodedColors': decoderColors.toList(),
    'renderedColors': renderedColors.toList(),
    'textureId': controller.id.value,
    'positionMs': controller.player.state.position.inMilliseconds,
  });
  await _captureVideoDesktop(name);
}

// Raw native diagnostics are confined to this guarded synthetic guest fixture.
// They are not enabled in production or sent to the app's diagnostic store.
class _VideoDiagnostics {
  _VideoDiagnostics(this.controller, this.name) {
    _errors = controller.player.stream.error.listen((error) {
      if (errors.length < 100) errors.add(_bounded(error));
    });
    _logs = controller.player.stream.log.listen((log) {
      if (logs.length < 100) logs.add(_bounded(log.toString()));
    });
    _sample();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _sample(),
    );
  }

  final VideoController controller;
  final String name;
  final samples = <Map<String, Object?>>[];
  final errors = <String>[];
  final logs = <String>[];
  late final Timer _timer;
  late final StreamSubscription<String> _errors;
  late final StreamSubscription<media.PlayerLog> _logs;

  static String _bounded(String value) =>
      value.length <= 4096 ? value : value.substring(0, 4096);

  void _sample() {
    if (samples.length >= 120) return;
    final state = controller.player.state;
    samples.add({
      'time': DateTime.now().toUtc().toIso8601String(),
      'textureId': controller.id.value,
      'rect': {
        'width': controller.rect.value?.width,
        'height': controller.rect.value?.height,
      },
      'playing': state.playing,
      'completed': state.completed,
      'buffering': state.buffering,
      'positionMs': state.position.inMilliseconds,
      'durationMs': state.duration.inMilliseconds,
      'width': state.width,
      'height': state.height,
      'videoParams': _bounded(state.videoParams.toString()),
      'tracks': _bounded(state.tracks.toString()),
    });
  }

  Future<void> save() async {
    _sample();
    final properties = <String, String>{};
    final platform = controller.player.platform;
    if (platform is media.NativePlayer) {
      for (final property in [
        'path',
        'file-format',
        'video-format',
        'video-codec',
        'vid',
        'vo',
        'hwdec-current',
        'idle-active',
        'pause',
        'playlist-count',
        'playlist-pos',
      ]) {
        try {
          properties[property] = _bounded(
            await platform
                .getProperty(property)
                .timeout(const Duration(seconds: 1)),
          );
        } on Object catch (error) {
          properties[property] = _bounded(error.toString());
        }
      }
    }
    final report = <String, Object?>{
      'samples': samples,
      'errors': errors,
      'logs': logs,
      'properties': properties,
    };
    try {
      final image = await controller.player
          .screenshot(format: 'image/png')
          .timeout(const Duration(seconds: 2));
      report['decodedScreenshotBytes'] = image?.length ?? 0;
      if (image != null) {
        await File(
          p.join(_evidence, '$name-video-failure-decoded.png'),
        ).writeAsBytes(image, flush: true);
      }
    } on Object catch (error) {
      report['decodedScreenshotError'] = _bounded(error.toString());
    }
    await _json('$name-video-diagnostics.json', report);
  }

  Future<void> dispose() async {
    _timer.cancel();
    await _errors.cancel();
    await _logs.cancel();
  }
}

Future<String?> _frameColor(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      final pixels = await frame.image.toByteData();
      if (pixels == null) {
        return null;
      }
      var redSamples = 0;
      var greenSamples = 0;
      for (var row = 0; row < 5; row++) {
        for (var column = 0; column < 5; column++) {
          final x = (frame.image.width * (0.4 + column * 0.05)).floor();
          final y = (frame.image.height * (0.4 + row * 0.05)).floor();
          final index = (y * frame.image.width + x) * 4;
          final red = pixels.getUint8(index);
          final green = pixels.getUint8(index + 1);
          final blue = pixels.getUint8(index + 2);
          if (red > 170 && green < 80 && blue < 100) {
            redSamples++;
          }
          if (red < 80 && green > 130 && blue > 60 && blue < 150) {
            greenSamples++;
          }
        }
      }
      if (redSamples >= 20) {
        return 'red';
      }
      if (greenSamples >= 20) {
        return 'green';
      }
      return null;
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Element? _element<T extends Widget>({
  bool Function(T)? where,
  Element? within,
}) {
  Element? result;
  void visit(Element element) {
    if (result != null) {
      return;
    }
    if (element.widget is T && (where == null || where(element.widget as T))) {
      result = element;
    } else {
      element.visitChildren(visit);
    }
  }

  final root = within ?? WidgetsBinding.instance.rootElement;
  if (root != null) {
    visit(root);
  }
  return result;
}

Future<void> _until(
  bool Function() predicate,
  String operation, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final timer = Stopwatch()..start();
  while (!predicate()) {
    if (timer.elapsed >= timeout) {
      throw StateError('Timed out: $operation');
    }
    await Future<void>.delayed(const Duration(milliseconds: 75));
  }
}

Future<void> _key(String name, int virtualKey) => _json(
  'key-$name-request.json',
  {'pid': pid, 'name': name, 'virtualKey': virtualKey},
);

Future<void> _json(String name, Map<String, Object?> value) => File(
  p.join(_evidence, name),
).writeAsString(const JsonEncoder.withIndent('  ').convert(value), flush: true);

void _require(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
