import 'dart:io';

import 'package:aethertune/src/data/saf_tree_scanner.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  const channel = MethodChannel('dev.aethertune/storage_access');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory stagingRoot;

  setUp(() async {
    stagingRoot = await Directory.systemTemp.createTemp('aethertune-saf-test-');
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    if (await stagingRoot.exists()) {
      await stagingRoot.delete(recursive: true);
    }
  });

  test('rebinds staged scans to persisted content URIs and cleans up',
      () async {
    final audioPath = path.join(stagingRoot.path, 'Album', '01 Signal.mp3');
    await File(audioPath).parent.create(recursive: true);
    await File(audioPath).writeAsBytes(<int>[1, 2, 3]);
    await File(path.setExtension(audioPath, '.lrc')).writeAsString(
      '[00:01.00]Signal lyric',
    );
    const treeUri =
        'content://com.android.providers.media.documents/tree/primary%3AMusic';
    const sourceUri =
        'content://com.android.providers.media.documents/tree/primary%3AMusic/document/primary%3AMusic%2FAlbum%2F01%20Signal.mp3';
    var discarded = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        switch (call.method) {
          case 'materializeAudioTree':
            expect(call.arguments, <String, Object?>{'treeUri': treeUri});
            return <String, Object?>{
              'stagingRootPath': stagingRoot.path,
              'audioFiles': <Map<String, String>>[
                <String, String>{
                  'relativePath': path.join('Album', '01 Signal.mp3'),
                  'sourceUri': sourceUri,
                },
              ],
              'inaccessibleDirectoryCount': 0,
            };
          case 'discardAudioTreeMaterialization':
            discarded = true;
            expect(
              call.arguments,
              <String, Object?>{'stagingRootPath': stagingRoot.path},
            );
            return null;
        }
        throw PlatformException(code: 'unexpected-method');
      },
    );

    final result = await scanPersistedAndroidSafTreeInBackground(treeUri);

    expect(result.tracks, hasLength(1));
    expect(result.tracks.single.localPath, sourceUri);
    expect(result.tracks.single.id, Track.stableLocalId(sourceUri));
    expect(
      result.sidecarLyricsByTrackId[Track.stableLocalId(sourceUri)],
      '[00:01.00]Signal lyric',
    );
    expect(discarded, isTrue);
  });
}
