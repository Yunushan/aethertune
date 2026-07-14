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

String? localArtworkPathForWidget(Track? track) {
  final artworkUri = track?.artworkUri;
  if (artworkUri == null || artworkUri.scheme.toLowerCase() != 'file') {
    return null;
  }
  try {
    // This value crosses the Android platform channel, so it must retain
    // Android/POSIX separators even when a host-side test runs on Windows.
    final path = artworkUri.toFilePath(windows: false);
    return path.isEmpty ? null : path;
  } on Object {
    return null;
  }
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
        'artworkPath': localArtworkPathForWidget(track),
      });
    } on MissingPluginException {
      // Platform wrappers are generated at build time; non-generated dev runs
      // still retain normal playback without a launcher widget refresh.
    } on PlatformException {
      // Widget updates must never interrupt playback or system media controls.
    }
  }
}
