import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:aethertune/src/data/offline_cache_manager.dart';
import 'package:aethertune/src/data/offline_cache_paths.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/offline_cache_entry.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  late OfflineCacheManager manager;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aethertune-cache-budget-');
    manager = OfflineCacheManager(
      cacheRoot: root,
      downloader: (_) async => [1, 2, 3, 4],
    );
    await manager.mediaDirectory.create(recursive: true);
  });
  tearDown(() => root.delete(recursive: true));

  Future<File> media(String name, int bytes) async => File(
    p.join(manager.mediaDirectory.path, name),
  ).writeAsBytes(List.filled(bytes, 9));

  test(
    'reserves peak media space including partial and unindexed files',
    () async {
      final old = await media('old.mp3', 4);
      final unindexed = await media('unindexed.mp3', 3);
      final paused = await media('paused.mp3.part', 2);
      final evicted = <String>[];
      final result = await manager.materialize(
        _entry('new'),
        budget: OfflineCacheBudget(
          totalBytes: 12,
          entries: [_entry('old', cachedPath: old.path)],
          onEvicted: (ids) async => evicted.addAll(ids),
        ),
      );
      expect(evicted, ['old']);
      expect(result.evictedEntryIds, ['old']);
      expect(result.evictedBytes, 4);
      expect(await old.exists(), isFalse);
      expect(await unindexed.length(), 3);
      expect(await paused.length(), 2);
      expect(await _mediaBytes(manager.mediaDirectory), 9);
    },
  );

  test(
    'provider pressure evicts its own files without touching other providers',
    () async {
      final own = await media('own.mp3', 4);
      final other = await media('other.mp3', 4);
      final result = await manager.materialize(
        _entry('new'),
        budget: OfflineCacheBudget(
          totalBytes: 20,
          providerBytes: {'archive': 5},
          entries: [
            _entry('own', cachedPath: own.path),
            _entry('other', source: 'podcast', cachedPath: other.path),
          ],
        ),
      );
      expect(result.evictedEntryIds, ['own']);
      expect(await other.length(), 4);
      expect(await _mediaBytes(manager.mediaDirectory), 8);
    },
  );

  test('unknown ownership cannot bypass a provider budget', () async {
    final unindexed = await media('unindexed.mp3', 3);
    await expectLater(
      manager.materialize(
        _entry('new'),
        budget: OfflineCacheBudget(
          totalBytes: 20,
          providerBytes: {'archive': 5},
        ),
      ),
      throwsA(isA<OfflineCacheQuotaExceeded>()),
    );
    expect(await unindexed.length(), 3);
    expect(await _mediaBytes(manager.mediaDirectory), 3);
  });

  test(
    'paused and orphan files are accounted for but never silently removed',
    () async {
      await media('orphan.mp3', 5);
      await media('paused.mp3.part', 4);
      await expectLater(
        manager.materialize(
          _entry('new'),
          budget: OfflineCacheBudget(totalBytes: 10),
        ),
        throwsA(isA<OfflineCacheQuotaExceeded>()),
      );
      expect(await _mediaBytes(manager.mediaDirectory), 9);
      expect(
        await File(
          p.join(manager.mediaDirectory.path, 'new.mp3.part'),
        ).exists(),
        isFalse,
      );
    },
  );

  test('replacement peak space includes the old completed file', () async {
    final original = await media('new.mp3', 8);
    await expectLater(
      manager.materialize(
        _entry('new'),
        budget: OfflineCacheBudget(
          totalBytes: 10,
          entries: [_entry('new', cachedPath: original.path)],
        ),
      ),
      throwsA(isA<OfflineCacheQuotaExceeded>()),
    );
    expect(await original.readAsBytes(), List.filled(8, 9));
  });

  test(
    'a transfer larger than the budget does not evict useful media',
    () async {
      final old = await media('old.mp3', 2);
      await expectLater(
        manager.materialize(
          _entry('new'),
          budget: OfflineCacheBudget(
            totalBytes: 3,
            entries: [_entry('old', cachedPath: old.path)],
          ),
        ),
        throwsA(isA<OfflineCacheQuotaExceeded>()),
      );
      expect(await old.length(), 2);
    },
  );

  test('duplicate index paths count and delete each file once', () async {
    final shared = await media('shared.mp3', 4);
    final result = await manager.materialize(
      _entry('new'),
      budget: OfflineCacheBudget(
        totalBytes: 6,
        entries: [
          _entry('first', cachedPath: shared.path),
          _entry('alias', cachedPath: shared.path),
        ],
      ),
    );
    expect(result.evictedEntryIds, ['first', 'alias']);
    expect(result.evictedBytes, 4);
    expect(await _mediaBytes(manager.mediaDirectory), 4);
  });

  test(
    'same-cache writers and evictions are excluded across isolates',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final first = OfflineCacheManager(
        cacheRoot: root,
        downloader: (_) async {
          started.complete();
          await release.future;
          return [1, 2, 3, 4];
        },
      ).materialize(_entry('first'), budget: OfflineCacheBudget(totalBytes: 6));
      await started.future;
      try {
        await expectLater(
          manager.materialize(_entry('second')),
          throwsA(isA<OfflineCacheBusy>()),
        );
        await expectLater(
          manager.evictToSize(entries: [], maxBytes: 0),
          throwsA(isA<OfflineCacheBusy>()),
        );
        await expectLater(
          manager.clearPrivateMedia(),
          throwsA(isA<OfflineCacheBusy>()),
        );
        expect(await _otherIsolate(root.path), 'busy');
      } finally {
        release.complete();
      }
      await first;
      await expectLater(
        manager.materialize(
          _entry('second'),
          budget: OfflineCacheBudget(totalBytes: 6),
        ),
        throwsA(isA<OfflineCacheQuotaExceeded>()),
      );
      expect(await _mediaBytes(manager.mediaDirectory), 4);
    },
  );

  test('a failed transfer releases the cache lock for a later retry', () async {
    final failing = OfflineCacheManager(
      cacheRoot: root,
      downloader: (_) async => throw const FileSystemException('disk full'),
    );
    await expectLater(
      failing.materialize(_entry('new')),
      throwsA(isA<FileSystemException>()),
    );
    final result = await manager.materialize(_entry('new'));
    expect(result.byteCount, 4);
  });

  test('displayed storage includes partial and unindexed media', () async {
    final indexed = await media('known.mp3', 4);
    await media('paused.mp3.part', 3);
    await media('orphan.mp3', 2);
    await File(
      p.join(manager.mediaDirectory.path, 'paused.mp3.part.resume'),
    ).writeAsString('{}');
    final usage = await manager.storageUsage([
      _entry('known', cachedPath: indexed.path),
    ]);
    expect(usage.byteCount, 9);
    expect(usage.cachedEntryCount, 1);
    expect(usage.partialByteCount, 3);
    expect(usage.unindexedByteCount, 2);
  });

  test(
    'explicit cleanup removes private files and retains original library media',
    () async {
      SharedPreferences.setMockInitialValues({});
      final cached = await media('known.mp3', 4);
      await media('paused.mp3.part', 3);
      await media('orphan.mp3', 2);
      final original = await File(
        p.join(root.path, 'original.mp3'),
      ).writeAsBytes([5, 6]);
      final library = LibraryStore();
      await library.load();
      final cachedTrack = _entry('known', cachedPath: cached.path).track;
      await library.addTracks([
        cachedTrack,
        Track(id: 'original', title: 'Original', localPath: original.path),
      ]);
      // A removed queue entry must not hide a remaining cached track from cleanup.
      final result = await manager.clearPrivateMedia();
      await library.forgetClearedOfflineFiles(result.deletedPaths);
      expect(result.byteCount, 9);
      expect(result.failedFileCount, 0);
      expect(await manager.mediaDirectory.list().toList(), isEmpty);
      expect(await original.readAsBytes(), [5, 6]);
      expect(library.tracks, hasLength(2));
      expect(
        library.tracks
            .firstWhere((track) => track.id == 'known')
            .hasLocalSource,
        isFalse,
      );
      final reopened = LibraryStore();
      await reopened.load();
      expect(
        reopened.tracks
            .firstWhere((track) => track.id == 'known')
            .hasLocalSource,
        isFalse,
      );
      expect(
        reopened.tracks.firstWhere((track) => track.id == 'original').localPath,
        original.path,
      );
      library.dispose();
      reopened.dispose();
    },
  );

  test(
    'cleanup refuses unexpected directories without deleting other files',
    () async {
      final original = await media('known.mp3', 4);
      await Directory(
        p.join(manager.mediaDirectory.path, 'unexpected'),
      ).create();
      await expectLater(manager.clearPrivateMedia(), throwsStateError);
      expect(await original.length(), 4);
    },
  );

  test(
    'post-download cleanup can defer without failing completed work',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final active = OfflineCacheManager(
        cacheRoot: root,
        downloader: (_) async {
          entered.complete();
          await release.future;
          return [1];
        },
      ).materialize(_entry('active'));
      await entered.future;
      try {
        final result = await manager.evictToSize(
          entries: [],
          maxBytes: 0,
          skipIfBusy: true,
        );
        expect(result.evictedEntryIds, isEmpty);
      } finally {
        release.complete();
      }
      expect((await active).byteCount, 1);
    },
  );

  test(
    'ordinary eviction deduplicates paths and updates every alias',
    () async {
      final file = await media('shared.mp3', 4);
      final entries = [
        _entry('first', cachedPath: file.path),
        _entry('second', cachedPath: file.path),
      ];
      expect((await manager.usage(entries)).byteCount, 4);
      final result = await manager.evictToSize(entries: entries, maxBytes: 0);
      expect(result.evictedBytes, 4);
      expect(result.evictedEntryIds, ['first', 'second']);
      expect(result.bytesAfter, 0);
    },
  );

  test(
    'case variants and the reserved hash namespace cannot overwrite other IDs',
    () async {
      final lower = await manager.materialize(_entry('entry'));
      final upper = await manager.materialize(_entry('Entry'));
      final hash = OfflineCachePaths.fileStem('Entry');
      final reserved = await manager.materialize(_entry(hash));
      final paths = [
        lower,
        upper,
        reserved,
      ].map((item) => item.track.localPath!.toLowerCase()).toSet();
      expect(paths, hasLength(3));
      expect(await _mediaBytes(manager.mediaDirectory), 12);
    },
  );

  test(
    'chunked responses are bounded before writing beyond available media space',
    () async {
      await media('paused.mp3.part', 6);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        try {
          request.response.add([1, 2]);
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          request.response.add([3, 4, 5]);
          await request.response.close();
        } on IOException {
          /* The bounded client closes the stream. */
        }
      });
      await expectLater(
        OfflineCacheManager(cacheRoot: root).materialize(
          _entry('new', url: 'http://127.0.0.1:${server.port}/song.mp3'),
          budget: OfflineCacheBudget(totalBytes: 10),
        ),
        throwsA(isA<OfflineCacheQuotaExceeded>()),
      );
      expect(await _mediaBytes(manager.mediaDirectory), 6);
    },
  );
}

OfflineCacheEntry _entry(
  String id, {
  String source = 'archive',
  String? cachedPath,
  String url = 'https://example.invalid/song.mp3',
}) => OfflineCacheEntry(
  id: id,
  track: Track(
    id: id,
    title: id,
    sourceId: source,
    streamUrl: url,
    localPath: cachedPath,
  ),
  status: cachedPath == null
      ? OfflineCacheEntryStatus.queued
      : OfflineCacheEntryStatus.cached,
  action: OfflineMediaAction.cache,
  createdAt: DateTime.utc(2026, 1, 1),
);

Future<int> _mediaBytes(Directory directory) async {
  var bytes = 0;
  await for (final entity in directory.list()) {
    if (entity is File && !entity.path.endsWith('.part.resume')) {
      bytes += await entity.length();
    }
  }
  return bytes;
}

Future<String> _otherIsolate(String rootPath) => Isolate.run(() async {
  try {
    await OfflineCacheManager(
      cacheRoot: Directory(rootPath),
      downloader: (_) async => [9],
    ).materialize(_entry('second'));
    return 'overwritten';
  } on OfflineCacheBusy {
    return 'busy';
  }
});
