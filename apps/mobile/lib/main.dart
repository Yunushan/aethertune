import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'src/player/playback_audio_engine_factory.dart';
import 'src/data/local_diagnostic_log.dart';
import 'src/ui/aethertune_app.dart';
import 'src/ui/widgets/desktop_tray_controls.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final diagnostics = LocalDiagnosticLog();
  await diagnostics.load();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      diagnostics.record(
        details.exception,
        stackTrace: details.stack,
        origin: 'flutter',
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(
      diagnostics.record(
        error,
        stackTrace: stackTrace,
        origin: 'platform-dispatcher',
      ),
    );
    return false;
  };
  final appLinks = AppLinks();
  if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform)) {
    await windowManager.ensureInitialized();
  }
  MediaKit.ensureInitialized();
  JustAudioMediaKit.title = 'AetherTune';
  JustAudioMediaKit.prefetchPlaylist = true;
  JustAudioMediaKit.ensureInitialized();
  final audioEngine = await createPlaybackAudioEngine();
  runApp(
    AetherTuneApp(
      audioEngine: audioEngine,
      diagnostics: diagnostics,
      incomingUriStream: appLinks.uriLinkStream,
    ),
  );
}
