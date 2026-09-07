import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const offlineCacheBackgroundChannel = MethodChannel(
  'dev.aethertune/offline_cache_background',
);

/// Schedules persisted offline-cache work when Android or iOS can run it
/// without the foreground Flutter activity. Other platforms deliberately
/// remain no-ops until they gain an equivalent system scheduler.
final class OfflineCacheBackgroundScheduler {
  OfflineCacheBackgroundScheduler({
    MethodChannel? channel,
    bool? isSupported,
    this.cancellationTimeout = const Duration(seconds: 12),
  }) : _channel = channel ?? offlineCacheBackgroundChannel,
       _isSupported =
           isSupported ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  final MethodChannel _channel;
  final bool _isSupported;
  final Duration cancellationTimeout;

  bool get isSupported => _isSupported;

  Future<bool> schedule({Duration? minimumLatency}) async {
    if (!_isSupported) {
      return false;
    }

    return await _channel.invokeMethod<bool>(
          'schedule',
          minimumLatency == null
              ? null
              : <String, Object>{
                  'minimumLatencyMilliseconds': minimumLatency.inMilliseconds,
                },
        ) ??
        false;
  }

  Future<void> cancel() async {
    if (!_isSupported) {
      return;
    }

    final stopped = await _channel
        .invokeMethod<bool>('cancel')
        .timeout(cancellationTimeout);
    if (stopped != true) {
      throw StateError('Background work did not acknowledge shutdown.');
    }
  }

  Future<void> complete({
    required bool hasPendingWork,
    Duration? nextRunDelay,
  }) async {
    if (!_isSupported) {
      return;
    }

    await _channel.invokeMethod<void>('complete', <String, Object>{
      'hasPendingWork': hasPendingWork,
      if (nextRunDelay != null)
        'nextRunDelayMilliseconds': nextRunDelay.inMilliseconds,
    });
  }
}
