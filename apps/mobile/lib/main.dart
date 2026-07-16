import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'src/player/playback_audio_engine_factory.dart';
import 'src/ui/aethertune_app.dart';
import 'src/ui/widgets/desktop_tray_controls.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appLinks = AppLinks();
  if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform)) {
    await windowManager.ensureInitialized();
  }
  JustAudioMediaKit.title = 'AetherTune';
  JustAudioMediaKit.prefetchPlaylist = true;
  JustAudioMediaKit.ensureInitialized();
  final audioEngine = await createPlaybackAudioEngine();
  runApp(
    AetherTuneApp(
      audioEngine: audioEngine,
      incomingUriStream: appLinks.uriLinkStream,
    ),
  );
}
