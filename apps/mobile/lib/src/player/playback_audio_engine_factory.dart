import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import 'playback_audio_engine.dart';
import 'system_media_playback_engine.dart';

bool supportsSystemMediaSession(TargetPlatform platform) {
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.iOS ||
      platform == TargetPlatform.macOS;
}

bool supportsAndroidAudioEffects(TargetPlatform platform) {
  return platform == TargetPlatform.android;
}

bool supportsPitchControl(TargetPlatform platform) {
  return platform == TargetPlatform.android ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.windows;
}

bool supportsSkipSilence(TargetPlatform platform) {
  return platform == TargetPlatform.android;
}

Future<PlaybackAudioEngine> createPlaybackAudioEngine() async {
  final engine = JustAudioPlaybackEngine(
    enableAndroidAudioEffects:
        !kIsWeb && supportsAndroidAudioEffects(defaultTargetPlatform),
    enableAndroidVisualizer:
        !kIsWeb && supportsAndroidAudioEffects(defaultTargetPlatform),
    enableAndroidVirtualizer:
        !kIsWeb && supportsAndroidAudioEffects(defaultTargetPlatform),
    enableSkipSilence: !kIsWeb && supportsSkipSilence(defaultTargetPlatform),
    enablePitch: !kIsWeb && supportsPitchControl(defaultTargetPlatform),
  );
  if (kIsWeb || !supportsSystemMediaSession(defaultTargetPlatform)) {
    return engine;
  }

  late SystemMediaPlaybackEngine systemEngine;
  await AudioService.init(
    builder: () {
      systemEngine = SystemMediaPlaybackEngine(engine);
      return systemEngine;
    },
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.aethertune.playback',
      androidNotificationChannelName: 'AetherTune playback',
      androidNotificationChannelDescription:
          'Playback controls for the current AetherTune queue.',
      androidNotificationOngoing: false,
    ),
  );

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  return systemEngine;
}
