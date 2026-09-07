import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/offline_cache_queue_worker.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/offline_cache_entry.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'does not resolve media without an eligible foreground queue entry',
    () async {
      final root = await Directory.systemTemp.createTemp('aethertune-worker-');
      addTearDown(() => root.delete(recursive: true));
      final library = LibraryStore();
      await library.load();
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: (_) => throw StateError('Resolver must not run.'),
      );

      expect(await worker.processNext(library), isNull);
      await library.setOfflineModeEnabled(true);
      expect(await worker.processNext(library), isNull);
    },
  );

  test('processes a bounded foreground batch sequentially', () async {
    final root = await Directory.systemTemp.createTemp('aethertune-worker-');
    addTearDown(() => root.delete(recursive: true));
    final library = LibraryStore();
    await library.load();
    await _queueLocalEntry(library, 'first');
    await _queueLocalEntry(library, 'second');
    await _queueLocalEntry(library, 'third');
    expect(library.hasPendingOfflineCacheWork, isTrue);
    final resolvedIds = <String>[];
    final worker = OfflineCacheQueueWorker(
      cacheRoot: root,
      resolveTrack: (track) async {
        resolvedIds.add(track.id);
        return track;
      },
    );

    final processed = await worker.processPending(library, maxEntries: 2);

    expect(processed, hasLength(2));
    expect(resolvedIds, processed.map((entry) => entry.track.id));
    expect(
      processed.map((entry) => entry.status),
      everyElement(OfflineCacheEntryStatus.cached),
    );
    expect(
      library.offlineCacheQueue.where(
        (entry) => entry.status == OfflineCacheEntryStatus.cached,
      ),
      hasLength(2),
    );
    expect(
      library.offlineCacheQueue.where(
        (entry) => entry.status == OfflineCacheEntryStatus.queued,
      ),
      hasLength(1),
    );
    expect(library.hasPendingOfflineCacheWork, isTrue);
  });

  test(
    'stopping waits for resolver cleanup without starting the next entry',
    () async {
      final root = await Directory.systemTemp.createTemp('aethertune-handoff-');
      addTearDown(() => root.delete(recursive: true));
      final library = LibraryStore();
      addTearDown(library.dispose);
      await library.load();
      await _queueLocalEntry(library, 'first');
      await _queueLocalEntry(library, 'second');
      final started = Completer<void>();
      final lookup = Completer<Track>();
      var resolutions = 0;
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: (_) {
          resolutions++;
          started.complete();
          return lookup.future;
        },
      );
      final pass = worker.processPending(library);
      await started.future;
      worker.stop();
      var drained = false;
      unawaited(pass.then((_) => drained = true));
      await Future<void>.delayed(Duration.zero);
      expect(drained, isFalse);
      expect(worker.busy, isTrue);
      lookup.completeError(StateError('Provider failure during shutdown'));
      final result = await pass.timeout(const Duration(seconds: 2));
      expect(result, hasLength(1));
      expect(resolutions, 1);
      expect(worker.busy, isFalse);
      expect(await root.list().toList(), isEmpty);
      await library.requeueProcessingOfflineCacheEntriesForBackground();
      expect(
        library.offlineCacheQueue.map((entry) => entry.status),
        everyElement(OfflineCacheEntryStatus.queued),
      );
      expect(library.saveError, isNull);
    },
  );

  test('a stopped worker can run a new explicitly requested pass', () async {
    final root = await Directory.systemTemp.createTemp('aethertune-handoff-');
    addTearDown(() => root.delete(recursive: true));
    final library = LibraryStore();
    addTearDown(library.dispose);
    await library.load();
    await _queueLocalEntry(library, 'retry');
    final started = Completer<void>();
    final lookup = Completer<Track>();
    var resolutions = 0;
    final worker = OfflineCacheQueueWorker(
      cacheRoot: root,
      resolveTrack: (track) {
        resolutions++;
        if (resolutions > 1) return Future.value(track);
        started.complete();
        return lookup.future;
      },
    );
    final first = worker.processPending(library);
    await started.future;
    worker.stop();
    lookup.complete(library.offlineCacheQueue.single.track);
    await first;
    await library.requeueProcessingOfflineCacheEntriesForBackground();
    final second = await worker.processNext(library);
    expect(second!.status, OfflineCacheEntryStatus.cached);
    expect(resolutions, 2);
  });

  test(
    'continues past a failed entry without retrying it in the same pass',
    () async {
      final root = await Directory.systemTemp.createTemp('aethertune-worker-');
      addTearDown(() => root.delete(recursive: true));
      final library = LibraryStore();
      await library.load();
      final failedEntry = await _queueLocalEntry(library, 'will-fail');
      final successfulEntry = await _queueLocalEntry(library, 'will-succeed');
      final resolvedIds = <String>[];
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: (track) async {
          resolvedIds.add(track.id);
          if (track.id == 'will-fail') {
            throw StateError('Expected resolution failure.');
          }
          return track;
        },
      );

      final processed = await worker.processPending(library);

      expect(resolvedIds, containsAll(<String>['will-fail', 'will-succeed']));
      expect(resolvedIds, hasLength(2));
      expect(processed, hasLength(2));
      expect(
        library.offlineCacheEntryById(failedEntry.id)!.status,
        OfflineCacheEntryStatus.failed,
      );
      expect(
        library.offlineCacheEntryById(successfulEntry.id)!.status,
        OfflineCacheEntryStatus.cached,
      );
    },
  );

  test('skips paused work and stops after offline mode is enabled', () async {
    final root = await Directory.systemTemp.createTemp('aethertune-worker-');
    addTearDown(() => root.delete(recursive: true));
    final library = LibraryStore();
    await library.load();
    final pausedEntry = await _queueLocalEntry(library, 'paused');
    await library.pauseOfflineCacheEntry(pausedEntry.id);
    final firstEntry = await _queueLocalEntry(library, 'first');
    final secondEntry = await _queueLocalEntry(library, 'second');
    final worker = OfflineCacheQueueWorker(
      cacheRoot: root,
      resolveTrack: (track) async {
        await library.setOfflineModeEnabled(true);
        return track;
      },
    );

    final processed = await worker.processPending(library);

    expect(processed, hasLength(1));
    final completedEntry = processed.single;
    expect(<String>[
      firstEntry.id,
      secondEntry.id,
    ], contains(completedEntry.id));
    expect(
      library.offlineCacheEntryById(pausedEntry.id)!.status,
      OfflineCacheEntryStatus.paused,
    );
    expect(
      library.offlineCacheEntryById(completedEntry.id)!.status,
      OfflineCacheEntryStatus.cached,
    );
    final waitingEntryId = <String>[
      firstEntry.id,
      secondEntry.id,
    ].firstWhere((id) => id != completedEntry.id);
    expect(
      library.offlineCacheEntryById(waitingEntryId)!.status,
      OfflineCacheEntryStatus.queued,
    );
  });

  test(
    'requeues interrupted processing work after a background handoff',
    () async {
      final library = LibraryStore();
      await library.load();
      final entry = await _queueLocalEntry(library, 'background-handoff');
      await library.markOfflineCacheEntryProcessing(entry.id);

      await library.requeueProcessingOfflineCacheEntriesForBackground();

      expect(
        library.offlineCacheEntryById(entry.id)!.status,
        OfflineCacheEntryStatus.queued,
      );
      expect(
        library.offlineCacheEntryById(entry.id)!.reason,
        'Continuing with the background downloader.',
      );
      final reloaded = LibraryStore();
      await reloaded.load();
      expect(
        reloaded.offlineCacheEntryById(entry.id)!.status,
        OfflineCacheEntryStatus.queued,
      );
    },
  );

  test(
    'restores processing work as queued after an interrupted process',
    () async {
      final library = LibraryStore();
      await library.load();
      final entry = await _queueLocalEntry(library, 'interrupted-process');
      await library.markOfflineCacheEntryProcessing(entry.id);

      final reloaded = LibraryStore();
      await reloaded.load();

      expect(
        reloaded.offlineCacheEntryById(entry.id)!.status,
        OfflineCacheEntryStatus.queued,
      );
      expect(
        reloaded.offlineCacheEntryById(entry.id)!.reason,
        'Resuming an interrupted cache request.',
      );
    },
  );

  test(
    'pauses an active request without marking it as a failed cache',
    () async {
      final root = await Directory.systemTemp.createTemp('aethertune-worker-');
      addTearDown(() => root.delete(recursive: true));
      final library = LibraryStore();
      await library.load();
      final entry = await _queueLocalEntry(library, 'active-pause');
      final resolverStarted = Completer<void>();
      final releaseResolver = Completer<void>();
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: (track) async {
          resolverStarted.complete();
          await releaseResolver.future;
          return track;
        },
      );

      final processing = worker.processNext(library);
      await resolverStarted.future;
      await library.pauseOfflineCacheEntry(entry.id);
      releaseResolver.complete();

      final result = await processing;

      expect(result!.status, OfflineCacheEntryStatus.paused);
      expect(
        library.offlineCacheEntryById(entry.id)!.status,
        OfflineCacheEntryStatus.paused,
      );
      expect(
        library.offlineCacheEntryById(entry.id)!.reason,
        'Paused by user.',
      );
    },
  );

  test(
    'evicted media stays paused across restart until explicitly resumed',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'aethertune-eviction-',
      );
      addTearDown(() => root.delete(recursive: true));
      final library = LibraryStore();
      await library.load();
      final entry = await _queueLocalEntry(library, 'evicted');
      await library.markOfflineCacheEntryCached(
        entry.id,
        entry.track,
        reason: 'Cached',
      );
      await library.markOfflineCacheEntryEvicted(
        entry.id,
        reason: 'Cache budget',
      );
      final reopened = LibraryStore();
      await reopened.load();
      var resolved = 0;
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: (track) async {
          resolved++;
          return track.copyWith(localPath: 'C:/fixture/evicted.mp3');
        },
      );
      expect(reopened.hasPendingOfflineCacheWork, isFalse);
      expect(await worker.processPending(reopened), isEmpty);
      expect(resolved, 0);
      await reopened.resumeOfflineCacheEntry(entry.id);
      expect(reopened.hasPendingOfflineCacheWork, isTrue);
      expect(
        (await worker.processNext(reopened))!.status,
        OfflineCacheEntryStatus.cached,
      );
      expect(resolved, 1);
      library.dispose();
      reopened.dispose();
    },
  );
}

Future<OfflineCacheEntry> _queueLocalEntry(LibraryStore library, String id) {
  final track = Track(id: id, title: id, localPath: 'C:/fixture/$id.mp3');
  return library.queueOfflineCache(
    track,
    OfflineMediaAction.cache,
    const OfflineMediaPolicy(
      <MusicSourceProvider>[],
    ).evaluate(track, OfflineMediaAction.cache),
  );
}
