import 'dart:io';

import 'package:aethertune/src/data/android_system_downloads_exporter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports verified cache metadata through the Android Downloads channel',
      () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(androidSystemDownloadsChannel, (
      call,
    ) async {
      calls.add(call);
      return 'content://media/external/downloads/42';
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        androidSystemDownloadsChannel,
        null,
      ),
    );
    final exporter = AndroidSystemDownloadsExporter(isSupported: true);

    final result = await exporter.exportVerifiedFile(
      file: File('/private/cache/track.ogg'),
      displayName: 'Artist - Track.ogg',
      byteCount: 123,
      checksum: 'a1b2c3d4',
    );

    expect(result, Uri.parse('content://media/external/downloads/42'));
    expect(calls, hasLength(1));
    expect(calls.single.method, 'exportVerifiedFile');
    expect(calls.single.arguments, <String, Object>{
      'sourcePath': '/private/cache/track.ogg',
      'displayName': 'Artist - Track.ogg',
      'byteCount': 123,
      'checksum': 'a1b2c3d4',
    });
  });

  test('leaves unsupported platforms untouched', () async {
    final exporter = AndroidSystemDownloadsExporter(isSupported: false);

    expect(
      await exporter.exportVerifiedFile(
        file: File('/private/cache/track.ogg'),
        displayName: 'Track.ogg',
        byteCount: 1,
        checksum: '00000000',
      ),
      isNull,
    );
  });
}
