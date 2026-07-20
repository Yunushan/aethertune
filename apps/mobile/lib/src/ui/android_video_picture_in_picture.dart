import 'dart:io';

import 'package:flutter/services.dart';

/// Enters Android's system-managed Picture-in-Picture mode for direct video.
class AndroidVideoPictureInPictureBridge {
  AndroidVideoPictureInPictureBridge({
    MethodChannel? channel,
    bool Function()? isAndroid,
  }) : _channel = channel ?? _defaultChannel,
       _isAndroid = isAndroid ?? _defaultIsAndroid;

  static const MethodChannel _defaultChannel = MethodChannel(
    'dev.aethertune/video_picture_in_picture',
  );

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  static bool _defaultIsAndroid() => Platform.isAndroid;

  bool get isSupportedPlatform => _isAndroid();

  Future<bool> enter() async {
    if (!_isAndroid()) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
