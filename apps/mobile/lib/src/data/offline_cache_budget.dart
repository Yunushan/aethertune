import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../domain/offline_cache_cancellation.dart';
import '../domain/offline_cache_entry.dart';
import 'offline_cache_paths.dart';

final class OfflineCacheBusy implements Exception {
  const OfflineCacheBusy();
  @override
  String toString() =>
      'Another offline cache operation is active. Retry later.';
}

final class OfflineCacheQuotaExceeded implements Exception {
  const OfflineCacheQuotaExceeded();
  @override
  String toString() =>
      'Offline storage is full. Clear private media in Offline cache storage, or increase the cache limit.';
}

final class OfflineCacheBudget {
  OfflineCacheBudget({
    required this.totalBytes,
    Iterable<OfflineCacheEntry> entries = const [],
    Map<String, int> providerBytes = const {},
    this.onEvicted,
  }) : entries = List.unmodifiable(entries),
       providerBytes = Map.unmodifiable(providerBytes) {
    if (totalBytes <= 0 || providerBytes.values.any((value) => value <= 0)) {
      throw ArgumentError('Offline cache budgets must be positive.');
    }
  }

  final int totalBytes;
  final List<OfflineCacheEntry> entries;
  final Map<String, int> providerBytes;
  final Future<void> Function(List<String> entryIds)? onEvicted;
}

/// Serializes cache mutations across managers, isolates, and native processes.
/// A killed process releases SQLite's OS locks; no expiring lease can overlap
/// a slow but still-live transfer. Network concurrency stays at one per cache.
Future<T> withOfflineCacheLock<T>(
  OfflineCachePaths paths,
  Future<T> Function() operation, {
  OfflineCacheCancellationToken? cancellationToken,
}) async {
  final directory = await paths.verifyDirectory(create: true);
  final lockFile = File(
    p.join(p.dirname(directory), 'offline_cache.lock.sqlite'),
  );
  final type = await FileSystemEntity.type(lockFile.path, followLinks: false);
  if (type != FileSystemEntityType.file &&
      type != FileSystemEntityType.notFound) {
    throw StateError('Offline cache lock must not be a link or directory.');
  }
  cancellationToken?.throwIfCancelled();
  final lock = sqlite3.open(lockFile.path);
  try {
    try {
      lock.execute('BEGIN EXCLUSIVE');
    } on SqliteException catch (error) {
      if (error.resultCode == 5 || error.resultCode == 6) {
        throw const OfflineCacheBusy();
      }
      rethrow;
    }
    return await operation();
  } finally {
    lock.close();
  }
}

final class _BudgetFile {
  _BudgetFile(this.file, this.bytes, this.sourceId, this.entries);
  final File file;
  final int bytes;
  final String? sourceId;
  final List<OfflineCacheEntry> entries;
}

/// Called only while holding the cache lock. Completed, partial, replacement,
/// and unindexed media all count, using actual file lengths, not saved counters.
final class OfflineCacheReservation {
  OfflineCacheReservation._(
    this._paths,
    this._budget,
    this._sourceId,
    this._files,
    this._baseTotal,
    this._baseProvider,
  );

  final OfflineCachePaths _paths;
  final OfflineCacheBudget _budget;
  final String _sourceId;
  final List<_BudgetFile> _files;
  int _baseTotal;
  int _baseProvider;
  int evictedBytes = 0;
  final List<String> evictedEntryIds = [];

  static Future<OfflineCacheReservation> create({
    required OfflineCachePaths paths,
    required OfflineCacheBudget budget,
    required OfflineCacheEntry entry,
    required File destination,
    required File partial,
  }) async {
    final byPath = <String, List<OfflineCacheEntry>>{};
    final byStem = <String, String>{};
    for (final known in [...budget.entries, entry]) {
      final source = known.track.sourceId.trim().toLowerCase();
      byStem[_pathKey(OfflineCachePaths.fileStem(known.id))] = source;
      if (known.status == OfflineCacheEntryStatus.cached &&
          known.track.hasLocalSource) {
        final file = File(known.track.localPath!);
        if (paths.containsPath(file)) {
          byPath.putIfAbsent(_pathKey(file.absolute.path), () => []).add(known);
        }
      }
    }
    final sourceId = entry.track.sourceId.trim().toLowerCase();
    final candidates = <_BudgetFile>[];
    var total = 0;
    var provider = 0;
    await for (final entity in paths.mediaDirectory.list(followLinks: false)) {
      final file = File(entity.path);
      await paths.verifyDestination(file);
      if (_pathKey(file.absolute.path) == _pathKey(partial.absolute.path)) {
        continue;
      }
      final bytes = await file.length();
      // Resume bookkeeping is capped independently; it is not media content.
      if (file.path.endsWith('.part.resume') && bytes <= 4096) continue;
      final known =
          byPath[_pathKey(file.absolute.path)] ?? const <OfflineCacheEntry>[];
      final sources = known
          .map((item) => item.track.sourceId.trim().toLowerCase())
          .toSet();
      final source = known.isNotEmpty
          ? (sources.length == 1 ? sources.single : null)
          : byStem[_pathKey(p.basename(file.path).split('.').first)];
      total += bytes;
      // Unknown ownership is charged conservatively to each provider budget.
      if (source == null || source == sourceId) provider += bytes;
      if (known.isNotEmpty &&
          _pathKey(file.absolute.path) != _pathKey(destination.absolute.path)) {
        candidates.add(_BudgetFile(file, bytes, source, known));
      }
    }
    candidates.sort((left, right) {
      final comparison = left.entries.first.updatedAt.compareTo(
        right.entries.first.updatedAt,
      );
      return comparison != 0
          ? comparison
          : left.file.path.compareTo(right.file.path);
    });
    return OfflineCacheReservation._(
      paths,
      budget,
      sourceId,
      candidates,
      total,
      provider,
    );
  }

  Future<void> reserve(int partialBytes) async {
    final providerLimit = _budget.providerBytes[_sourceId];
    if (partialBytes > _budget.totalBytes ||
        (providerLimit != null && partialBytes > providerLimit)) {
      throw const OfflineCacheQuotaExceeded();
    }
    bool providerExceeded() =>
        providerLimit != null && _baseProvider + partialBytes > providerLimit;
    bool totalExceeded() => _baseTotal + partialBytes > _budget.totalBytes;
    while (providerExceeded() || totalExceeded()) {
      final index = _files.indexWhere(
        (candidate) =>
            !providerExceeded() ||
            candidate.sourceId == null ||
            candidate.sourceId == _sourceId,
      );
      if (index == -1) throw const OfflineCacheQuotaExceeded();
      final candidate = _files.removeAt(index);
      try {
        await _paths.deleteFile(candidate.file);
      } on FileSystemException {
        continue;
      }
      _baseTotal -= candidate.bytes;
      if (candidate.sourceId == null || candidate.sourceId == _sourceId) {
        _baseProvider -= candidate.bytes;
      }
      final ids = candidate.entries.map((entry) => entry.id).toList();
      evictedEntryIds.addAll(ids);
      evictedBytes += candidate.bytes;
      await _budget.onEvicted?.call(ids);
    }
  }
}

String _pathKey(String path) => Platform.isWindows ? path.toLowerCase() : path;
