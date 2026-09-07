import 'dart:async';

import 'package:flutter/services.dart';

import 'offline_cache_background_scheduler.dart';

/// One headless engine pass. A stop reply means all work and cleanup finished.
final class OfflineCacheBackgroundSession {
  OfflineCacheBackgroundSession({MethodChannel? channel})
    : _channel = channel ?? offlineCacheBackgroundChannel;

  final MethodChannel _channel;
  final Completer<void> _drained = Completer<void>();
  bool _started = false;
  bool _stopRequested = false;
  void Function()? _cancelCurrent;

  bool get shouldContinue => !_stopRequested;

  void cancelCurrentWith(void Function()? cancel) {
    _cancelCurrent = cancel;
    if (_stopRequested) cancel?.call();
  }

  void _requestStop() {
    if (_stopRequested) return;
    _stopRequested = true;
    _cancelCurrent?.call();
  }

  Future<void> run(
    Future<void> Function(OfflineCacheBackgroundSession session) work,
  ) async {
    if (_started) throw StateError('A background session runs only once.');
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'stop') throw MissingPluginException();
      _requestStop();
      await _drained.future;
      return true;
    });
    try {
      if (await _channel.invokeMethod<bool>('ready') != true) _requestStop();
      if (shouldContinue) await work(this);
    } finally {
      _cancelCurrent = null;
      _drained.complete();
      // Keep the handler until engine destruction: a late stop still needs an
      // acknowledgment, including when it races the outgoing complete call.
    }
  }
}
