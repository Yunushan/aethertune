import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/track.dart';

abstract interface class PlaybackWidgetBridge {
  Future<void> update({
    Track? track,
    required bool isPlaying,
    required Duration position,
    Duration? duration,
  });
}

class AndroidPlaybackWidgetBridge implements PlaybackWidgetBridge {
  const AndroidPlaybackWidgetBridge({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'dev.aethertune/playback_widget',
  );

  final MethodChannel _channel;

  @override
  Future<void> update({
    Track? track,
    required bool isPlaying,
    required Duration position,
    Duration? duration,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('update', <String, Object?>{
        'title': track?.title ?? 'AetherTune',
        'artist': track?.artist ?? '',
        'isPlaying': isPlaying,
        'positionMillis': position.inMilliseconds.clamp(0, 2147483647),
        'durationMillis': duration?.inMilliseconds.clamp(0, 2147483647) ?? 0,
      });
    } on MissingPluginException {
      // Platform wrappers are generated at build time; non-generated dev runs
      // still retain normal playback without a launcher widget refresh.
    } on PlatformException {
      // Widget updates must never interrupt playback or system media controls.
    }
  }
}
