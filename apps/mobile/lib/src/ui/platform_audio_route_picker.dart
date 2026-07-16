import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _audioRoutePickerChannel = MethodChannel('dev.aethertune/audio_routes');

bool supportsPlatformAudioRoutePicker(TargetPlatform platform) {
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}

Future<bool> showPlatformAudioRoutePicker({TargetPlatform? platform}) async {
  if (kIsWeb || !supportsPlatformAudioRoutePicker(platform ?? defaultTargetPlatform)) {
    return false;
  }

  try {
    return await _audioRoutePickerChannel.invokeMethod<bool>(
          'showAudioRoutePicker',
        ) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
