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

  /// Opens this app's system settings page after a user declines a folder
  /// import permission request. Individual-file imports never need this.
  static Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAudioLibrarySettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
