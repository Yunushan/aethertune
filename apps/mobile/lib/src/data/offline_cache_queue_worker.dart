import 'dart:io';

import '../domain/offline_cache_cancellation.dart';
import '../domain/offline_cache_entry.dart';
import '../domain/track.dart';
import 'library_store.dart';
import 'offline_cache_manager.dart';
import 'offline_cache_pressure_enforcer.dart';

typedef OfflineCacheTrackResolver = Future<Track> Function(Track track);

class OfflineCacheQueueWorker {
  static const defaultMaximumEntriesPerPass = 25;

  OfflineCacheQueueWorker({
    required Directory cacheRoot,
    required OfflineCacheTrackResolver resolveTrack,
  }) : _manager = OfflineCacheManager(cacheRoot: cacheRoot),
       _resolveTrack = resolveTrack;

  final OfflineCacheManager _manager;
  final OfflineCacheTrackResolver _resolveTrack;
  bool _busy = false;

  bool get busy => _busy;

  Future<OfflineCacheEntry?> processNext(LibraryStore library) async {
    final processed = await processPending(library, maxEntries: 1);
    return processed.isEmpty ? null : processed.single;
  }

  Future<List<OfflineCacheEntry>> processPending(
    LibraryStore library, {
    int maxEntries = defaultMaximumEntriesPerPass,
  }) async {
    if (_busy || library.offlineModeEnabled) {
      return const <OfflineCacheEntry>[];
    }

    final entryIds = library.offlineCacheQueue
        .where(_canProcess)
        .take(maxEntries < 1 ? 1 : maxEntries)
        .map((entry) => entry.id)
        .toList(growable: false);
    if (entryIds.isEmpty) {
      return const <OfflineCacheEntry>[];
    }

    _busy = true;
    try {
      final processed = <OfflineCacheEntry>[];
      for (final entryId in entryIds) {
        if (library.offlineModeEnabled) {
          break;
        }

        final entry = library.offlineCacheEntryById(entryId);
        if (entry == null || !_canProcess(entry)) {
          continue;
        }

        processed.add(await _processEntry(library, entry));
      }

      return List<OfflineCacheEntry>.unmodifiable(processed);
    } finally {
      _busy = false;
    }
  }

  Future<OfflineCacheEntry> _processEntry(
    LibraryStore library,
    OfflineCacheEntry entry,
  ) async {
    await library.markOfflineCacheEntryProcessing(entry.id);
    final cancellationToken = OfflineCacheCancellationRegistry.instance.tokenFor(
      entry.id,
    );
    final processing = library.offlineCacheEntryById(entry.id) ?? entry;
    try {
      final resolvedTrack = await _resolveTrack(processing.track);
      cancellationToken.throwIfCancelled();
      final materialization = await _manager.materialize(
        processing.copyWith(track: resolvedTrack),
        cancellationToken: cancellationToken,
      );
      if (library.offlineCacheEntryById(entry.id)?.status !=
          OfflineCacheEntryStatus.processing) {
        return library.offlineCacheEntryById(entry.id) ?? entry;
      }
      final reason = materialization.expectedMediaChecksumVerified
          ? 'Cached ${materialization.byteCount} bytes; provider checksum verified.'
          : 'Cached ${materialization.byteCount} bytes; integrity check verified.';
      await library.markOfflineCacheEntryCached(
        entry.id,
        materialization.track,
        reason: reason,
        byteCount: materialization.byteCount,
        checksum: materialization.checksum,
      );
      await enforceOfflineCacheLimit(library: library, manager: _manager);
    } on OfflineCacheCancelled {
      // The store already records the paused state; the private `.part` file
      // remains available for a later HTTP Range resume.
    } on Object catch (error) {
      if (library.offlineCacheEntryById(entry.id)?.status ==
          OfflineCacheEntryStatus.paused) {
        return library.offlineCacheEntryById(entry.id) ?? entry;
      }
      await library.markOfflineCacheEntryFailed(
        entry.id,
        reason: error.toString(),
      );
    } finally {
      OfflineCacheCancellationRegistry.instance.release(
        entry.id,
        cancellationToken,
      );
    }

    return library.offlineCacheEntryById(entry.id) ?? entry;
  }
}

bool _canProcess(OfflineCacheEntry entry) {
  return entry.status == OfflineCacheEntryStatus.queued ||
      entry.status == OfflineCacheEntryStatus.failed;
}
