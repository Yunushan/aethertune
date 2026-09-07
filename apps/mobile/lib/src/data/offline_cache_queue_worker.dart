// Public dependency names are part of the API; backing fields stay private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
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
  bool _stopRequested = false;
  OfflineCacheCancellationToken? _activeToken;

  bool get busy => _busy;

  /// Stops this pass, including its current transfer. The caller must await
  /// the pass before requeuing processing entries or scheduling another owner.
  void stop() {
    _stopRequested = true;
    _activeToken?.cancel();
  }

  Future<OfflineCacheEntry?> processNext(LibraryStore library) async {
    final processed = await processPending(library, maxEntries: 1);
    return processed.isEmpty ? null : processed.single;
  }

  Future<List<OfflineCacheEntry>> processPending(
    LibraryStore library, {
    int maxEntries = defaultMaximumEntriesPerPass,
  }) async {
    if (_busy ||
        !library.loaded ||
        library.saveError != null ||
        library.offlineModeEnabled) {
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
    _stopRequested = false;
    try {
      final processed = <OfflineCacheEntry>[];
      for (final entryId in entryIds) {
        if (_stopRequested || library.offlineModeEnabled) {
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
    final cancellationToken = OfflineCacheCancellationRegistry.instance
        .tokenFor(entry.id);
    _activeToken = cancellationToken;
    if (_stopRequested) cancellationToken.cancel();
    final processing = library.offlineCacheEntryById(entry.id) ?? entry;
    try {
      cancellationToken.throwIfCancelled();
      // Resolution can write private artwork. Cancellation must await those
      // side effects before another engine is allowed to own the queue.
      final resolvedTrack = await _resolveTrack(processing.track);
      cancellationToken.throwIfCancelled();
      final materialization = await _manager.materialize(
        processing.copyWith(track: resolvedTrack),
        cancellationToken: cancellationToken,
        budget: offlineCacheBudget(library),
        maxBytes: offlineCacheTransferLimitBytes(
          library,
          resolvedTrack.sourceId,
        ),
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
      // User pause already records its state. A lifecycle owner requeues only
      // after this pass drains; private `.part` bytes remain resumable.
    } on Object catch (error) {
      if (library.saveError != null) rethrow;
      if (cancellationToken.isCancelled) {
        return library.offlineCacheEntryById(entry.id) ?? entry;
      }
      if (library.offlineCacheEntryById(entry.id)?.status ==
          OfflineCacheEntryStatus.paused) {
        return library.offlineCacheEntryById(entry.id) ?? entry;
      }
      await library.markOfflineCacheEntryFailed(
        entry.id,
        reason: error.toString(),
      );
    } finally {
      if (identical(_activeToken, cancellationToken)) _activeToken = null;
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
