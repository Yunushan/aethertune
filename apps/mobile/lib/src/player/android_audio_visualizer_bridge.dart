import 'package:flutter/services.dart';

/// Android-only bridge for FFT bands from the active just_audio session.
///
/// Android protects its visualizer API with the record-audio permission even
/// when an app observes only its own playback session. Native code asks only
/// after the user explicitly enables this feature in Now Playing.
class AndroidAudioVisualizerBridge {
  static const MethodChannel _methods = MethodChannel(
    'dev.aethertune/audio_visualizer',
  );
  static const EventChannel _events = EventChannel(
    'dev.aethertune/audio_visualizer/bands',
  );

  Stream<List<double>> get bands => _events
      .receiveBroadcastStream()
      .map(normalizeAudioVisualizerBands)
      .where((value) => value.isNotEmpty);

  Future<bool> start(int audioSessionId) async {
    if (audioSessionId <= 0) {
      return false;
    }
    return await _methods.invokeMethod<bool>(
          'start',
          <String, Object>{'audioSessionId': audioSessionId},
        ) ??
        false;
  }

  Future<void> stop() => _methods.invokeMethod<void>('stop');
}

/// Converts a platform event into finite, normalized visualizer band values.
List<double> normalizeAudioVisualizerBands(Object? value) {
  if (value is! List) {
    return const <double>[];
  }
  return value
      .take(16)
      .map((item) {
        final numeric = item is num ? item.toDouble() : 0.0;
        if (!numeric.isFinite) {
          return 0.0;
        }
        return numeric.clamp(0.0, 1.0).toDouble();
      })
      .toList(growable: false);
}
