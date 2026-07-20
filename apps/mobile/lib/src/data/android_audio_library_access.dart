import 'package:flutter/services.dart';

/// Requests Android's user-approved audio-library permission for explicit
/// recursive folder imports. Callers must provide their own user disclosure.
abstract final class AndroidAudioLibraryAccess {
  static const MethodChannel _channel = MethodChannel(
    'dev.aethertune/storage_access',
  );

  static Future<bool> request() async {
    try {
      return await _channel.invokeMethod<bool>('requestAudioLibraryAccess') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
