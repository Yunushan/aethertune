import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const androidSystemDownloadsChannel = MethodChannel(
  'dev.aethertune/system_downloads',
);

/// Exports an already-verified private cache file to Android's public
/// Downloads collection. It never receives a provider URL or credentials.
final class AndroidSystemDownloadsExporter {
  AndroidSystemDownloadsExporter({
    MethodChannel? channel,
    bool? isSupported,
  }) : _channel = channel ?? androidSystemDownloadsChannel,
       _isSupported = isSupported ?? (!kIsWeb && Platform.isAndroid);

  final MethodChannel _channel;
  final bool _isSupported;

  bool get isSupported => _isSupported;

  Future<Uri?> exportVerifiedFile({
    required File file,
    required String displayName,
    required int byteCount,
    required String checksum,
  }) async {
    if (!_isSupported) {
      return null;
    }

    final rawUri = await _channel.invokeMethod<String>(
      'exportVerifiedFile',
      <String, Object>{
        'sourcePath': file.path,
        'displayName': displayName,
        'byteCount': byteCount,
        'checksum': checksum,
      },
    );
    return rawUri == null ? null : Uri.tryParse(rawUri);
  }
}
