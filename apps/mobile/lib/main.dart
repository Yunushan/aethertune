import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'src/player/playback_audio_engine_factory.dart';
import 'src/ui/aethertune_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.title = 'AetherTune';
  JustAudioMediaKit.prefetchPlaylist = true;
  JustAudioMediaKit.ensureInitialized();
  final audioEngine = await createPlaybackAudioEngine();
  runApp(AetherTuneApp(audioEngine: audioEngine));
}
