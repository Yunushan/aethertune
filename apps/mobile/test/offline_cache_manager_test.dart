import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  test('measures and evicts only private cached media', () async {
    final manager = OfflineCacheManager(cacheRoot: cacheRoot);
    await manager.mediaDirectory.create(recursive: true);
    final oldFile = File(p.join(manager.mediaDirectory.path, 'old.mp3'));
    final middleFile = File(p.join(manager.mediaDirectory.path, 'middle.mp3'));
    final newestFile = File(p.join(manager.mediaDirectory.path, 'newest.mp3'));
    final externalFile = File(p.join(cacheRoot.path, 'user-import.mp3'));
    await oldFile.writeAsBytes(<int>[1, 2, 3, 4]);
    await middleFile.writeAsBytes(<int>[1, 2, 3]);
    await newestFile.writeAsBytes(<int>[1, 2, 3, 4, 5]);
    await externalFile.writeAsBytes(<int>[1, 2, 3, 4, 5, 6]);
    final entries = <OfflineCacheEntry>[
      _cachedEntry(
        'old',
        'Old cache',
        oldFile.path,
        updatedAt: DateTime.utc(2026, 1, 17),
      ),
      _cachedEntry(
        'middle',
        'Middle cache',
        middleFile.path,
        updatedAt: DateTime.utc(2026, 1, 18),
      ),
      _cachedEntry(
        'newest',
        'Newest cache',
        newestFile.path,
        updatedAt: DateTime.utc(2026, 1, 19),
      ),
      _cachedEntry(
        'external',
        'User import',
        externalFile.path,
        updatedAt: DateTime.utc(2026, 1, 16),
      ),
      OfflineCacheEntry(
        id: 'queued',
        track: Track(
          id: 'queued-track',
          title: 'Queued cache',
          sourceId: 'internet-archive',
          localPath: oldFile.path,
        ),
        action: OfflineMediaAction.cache,
        createdAt: DateTime.utc(2026, 1, 17),
      ),
    ];

    final usage = await manager.usage(entries);

    expect(usage.byteCount, 12);
    expect(usage.cachedEntryCount, 3);

    final result = await manager.evictToSize(
      entries: entries,
      maxBytes: 5,
    );

    expect(result.bytesBefore, 12);
    expect(result.bytesAfter, 5);
    expect(result.evictedBytes, 7);
    expect(result.evictedEntryIds, <String>['old', 'middle']);
    expect(await oldFile.exists(), isFalse);
    expect(await middleFile.exists(), isFalse);
    expect(await newestFile.exists(), isTrue);
    expect(await externalFile.exists(), isTrue);
    expect((await manager.usage(entries)).byteCount, 5);
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

OfflineCacheEntry _cachedEntry(
  String id,
  String title,
  String localPath, {
  required DateTime updatedAt,
}) {
  return OfflineCacheEntry(
    id: id,
    track: Track(
      id: '$id-track',
      title: title,
      sourceId: 'internet-archive',
      streamUrl: 'https://archive.org/download/$id/audio.mp3',
      localPath: localPath,
    ),
    action: OfflineMediaAction.cache,
    status: OfflineCacheEntryStatus.cached,
    createdAt: DateTime.utc(2026, 1, 17),
    updatedAt: updatedAt,
  );
}
