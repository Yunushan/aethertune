import 'dart:io';

import 'package:flutter/services.dart';

enum AndroidPinnedShortcut { previous, playPause, next }

extension AndroidPinnedShortcutLabel on AndroidPinnedShortcut {
  String get label => switch (this) {
    AndroidPinnedShortcut.previous => 'Previous track',
    AndroidPinnedShortcut.playPause => 'Play or pause',
    AndroidPinnedShortcut.next => 'Next track',
  };
}

/// Requests a launcher-pinned transport shortcut on supported Android hosts.
class AndroidPinnedShortcutBridge {
  AndroidPinnedShortcutBridge({
    MethodChannel? channel,
    bool Function()? isAndroid,
  }) : _channel = channel ?? _defaultChannel,
       _isAndroid = isAndroid ?? _defaultIsAndroid;

  static const MethodChannel _defaultChannel = MethodChannel(
    'dev.aethertune/pinned_shortcuts',
  );

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  static bool _defaultIsAndroid() => Platform.isAndroid;

  Future<bool> requestPin(AndroidPinnedShortcut shortcut) async {
    if (!_isAndroid()) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('requestPin', <String, Object?>{
            'shortcut': shortcut.name,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
