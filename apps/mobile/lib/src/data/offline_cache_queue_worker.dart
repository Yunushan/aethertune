import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/offline_cache_entry.dart';
import '../domain/track.dart';
import 'library_store.dart';
import 'offline_cache_manager.dart';
import 'offline_cache_pressure_enforcer.dart';

typedef OfflineCacheTrackResolver = Future<Track> Function(Track track);

class OfflineCacheQueueWorker {
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
    if (_busy || library.offlineModeEnabled) {
      return null;
    }
    final entry = library.offlineCacheQueue.firstWhere(
      _canProcess,
      orElse: () => _emptyEntry,
    );
    if (entry.id.isEmpty) {
      return null;
    }

    _busy = true;
    try {
      await library.markOfflineCacheEntryProcessing(entry.id);
      final processing = library.offlineCacheEntryById(entry.id) ?? entry;
      try {
        final resolvedTrack = await _resolveTrack(processing.track);
        final materialization = await _manager.materialize(
          processing.copyWith(track: resolvedTrack),
        );
        final reason = materialization.checksum.isEmpty
            ? 'Cached ${materialization.byteCount} bytes.'
            : 'Cached ${materialization.byteCount} bytes; checksum verified.';
        await library.markOfflineCacheEntryCached(
          entry.id,
          materialization.track,
          reason: reason,
          byteCount: materialization.byteCount,
          checksum: materialization.checksum,
        );
        await enforceOfflineCacheLimit(library: library, manager: _manager);
      } on Object catch (error) {
        await library.markOfflineCacheEntryFailed(
          entry.id,
          reason: error.toString(),
        );
      }
      return library.offlineCacheEntryById(entry.id);
    } finally {
      _busy = false;
    }
  }
}

bool _canProcess(OfflineCacheEntry entry) {
  return entry.status == OfflineCacheEntryStatus.queued ||
      entry.status == OfflineCacheEntryStatus.failed;
}

final _emptyEntry = OfflineCacheEntry(
  id: '',
  track: Track(id: '', title: ''),
  action: OfflineMediaAction.cache,
  status: OfflineCacheEntryStatus.paused,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
);
