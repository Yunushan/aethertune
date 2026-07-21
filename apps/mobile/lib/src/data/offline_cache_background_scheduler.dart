import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const offlineCacheBackgroundChannel = MethodChannel(
  'dev.aethertune/offline_cache_background',
);

/// Schedules persisted offline-cache work when Android can run it without the
/// foreground Flutter activity. Other platforms deliberately remain no-ops
/// until they gain an equivalent system scheduler.
final class OfflineCacheBackgroundScheduler {
  OfflineCacheBackgroundScheduler({
    MethodChannel? channel,
    bool? isSupported,
  }) : _channel = channel ?? offlineCacheBackgroundChannel,
       _isSupported = isSupported ?? (!kIsWeb && Platform.isAndroid);

  final MethodChannel _channel;
  final bool _isSupported;

  bool get isSupported => _isSupported;

  Future<bool> schedule() async {
    if (!_isSupported) {
      return false;
    }

    return await _channel.invokeMethod<bool>('schedule') ?? false;
  }

  Future<void> cancel() async {
    if (!_isSupported) {
      return;
    }

    await _channel.invokeMethod<void>('cancel');
  }

  Future<void> complete({required bool hasPendingWork}) async {
    if (!_isSupported) {
      return;
    }

    await _channel.invokeMethod<void>(
      'complete',
      <String, Object>{'hasPendingWork': hasPendingWork},
    );
  }
}
