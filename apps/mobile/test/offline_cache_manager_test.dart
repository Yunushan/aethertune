import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/offline_cache_manager.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/offline_cache_entry.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  late Directory cacheRoot;

  setUp(() async {
    cacheRoot = await Directory.systemTemp.createTemp('aethertune-cache-test-');
  });

  tearDown(() async {
    if (await cacheRoot.exists()) {
      await cacheRoot.delete(recursive: true);
    }
  });

  test('materializes a stream URL into a local offline file', () async {
    final entry = OfflineCacheEntry(
      id: 'entry-one',
      track: Track(
        id: 'track-one',
        title: 'Archive One',
        artist: 'Archive',
        sourceId: 'internet-archive',
        streamUrl: 'https://archive.org/download/item/audio.ogg',
      ),
      action: OfflineMediaAction.cache,
      createdAt: DateTime.utc(2026, 1, 17),
    );
    final manager = OfflineCacheManager(
      cacheRoot: cacheRoot,
      downloader: (uri) async {
        expect(uri.host, 'archive.org');
        return <int>[1, 2, 3, 4];
      },
    );

    final materialization = await manager.materialize(entry);

    expect(materialization.byteCount, 4);
    expect(materialization.track.localPath, isNotNull);
    expect(materialization.track.hasLocalSource, isTrue);
    expect(materialization.track.streamUrl, entry.track.streamUrl);
    expect(materialization.track.localPath, endsWith('.ogg'));
    expect(
      (await File(materialization.track.localPath!).readAsBytes()).toList(),
      <int>[1, 2, 3, 4],
    );
  });

  test('rejects entries without downloadable http URLs', () async {
    final entry = OfflineCacheEntry(
      id: 'entry-two',
      track: Track(
        id: 'track-two',
        title: 'Metadata Only',
        sourceId: 'internet-archive',
      ),
      action: OfflineMediaAction.download,
      createdAt: DateTime.utc(2026, 1, 17),
    );
    final manager = OfflineCacheManager(
      cacheRoot: cacheRoot,
      downloader: (_) async => <int>[1],
    );

    expect(manager.materialize(entry), throwsA(isA<StateError>()));
  });
}
