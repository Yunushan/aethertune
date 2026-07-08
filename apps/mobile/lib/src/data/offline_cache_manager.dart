import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/offline_cache_entry.dart';
import '../domain/track.dart';

typedef OfflineMediaDownloader = Future<List<int>> Function(Uri uri);

final class OfflineCacheMaterialization {
  const OfflineCacheMaterialization({
    required this.track,
    required this.byteCount,
    required this.checksum,
  });

  final Track track;
  final int byteCount;
  final String checksum;
}

final class OfflineCacheUsage {
  const OfflineCacheUsage({
    required this.byteCount,
    required this.cachedEntryCount,
  });

  final int byteCount;
  final int cachedEntryCount;
}

final class OfflineCacheEvictionResult {
  const OfflineCacheEvictionResult({
    required this.bytesBefore,
    required this.bytesAfter,
    required this.evictedEntryIds,
    required this.evictedBytes,
  });

  final int bytesBefore;
  final int bytesAfter;
  final List<String> evictedEntryIds;
  final int evictedBytes;
}

final class _OfflineCacheFileCandidate {
  const _OfflineCacheFileCandidate({
    required this.entry,
    required this.file,
    required this.byteCount,
  });

  final OfflineCacheEntry entry;
  final File file;
  final int byteCount;
}

final class OfflineCacheManager {
  OfflineCacheManager({
    required this.cacheRoot,
    OfflineMediaDownloader? downloader,
  }) : _downloader = downloader ?? _downloadWithHttpClient;

  final Directory cacheRoot;
  final OfflineMediaDownloader _downloader;

  Directory get mediaDirectory {
    return Directory(
      p.join(cacheRoot.path, 'aethertune', 'offline_media'),
    );
  }

  Future<OfflineCacheMaterialization> materialize(
    OfflineCacheEntry entry,
  ) async {
    if (entry.track.hasLocalSource) {
      return OfflineCacheMaterialization(
        track: entry.track,
        byteCount: 0,
        checksum: '',
      );
    }

    final streamUrl = entry.track.streamUrl?.trim();
    final streamUri = Uri.tryParse(streamUrl ?? '');
    if (streamUri == null || !streamUri.hasScheme) {
      throw StateError('No downloadable stream URL for ${entry.track.title}.');
    }
    if (streamUri.scheme != 'http' && streamUri.scheme != 'https') {
      throw StateError(
        'Unsupported offline cache URL scheme: ${streamUri.scheme}.',
      );
    }

    final bytes = await _downloader(streamUri);
    if (bytes.isEmpty) {
      throw StateError('Downloaded media is empty for ${entry.track.title}.');
    }

    await mediaDirectory.create(recursive: true);

    final file = File(
      p.join(mediaDirectory.path, '${entry.id}${_mediaExtension(streamUri)}'),
    );
    await file.writeAsBytes(bytes, flush: true);
    final checksum = offlineMediaChecksum(bytes);
    final savedBytes = await file.readAsBytes();
    if (savedBytes.length != bytes.length ||
        offlineMediaChecksum(savedBytes) != checksum) {
      throw StateError(
        'Cached media checksum verification failed for ${entry.track.title}.',
      );
    }

    return OfflineCacheMaterialization(
      track: entry.track.copyWith(localPath: file.path),
      byteCount: bytes.length,
      checksum: checksum,
    );
  }

  Future<OfflineCacheUsage> usage(Iterable<OfflineCacheEntry> entries) async {
    final candidates = await _privateCachedFiles(entries);

    return OfflineCacheUsage(
      byteCount: candidates.fold<int>(
        0,
        (total, candidate) => total + candidate.byteCount,
      ),
      cachedEntryCount: candidates.length,
    );
  }

  Future<OfflineCacheEvictionResult> evictToSize({
    required Iterable<OfflineCacheEntry> entries,
    required int maxBytes,
  }) async {
    final limit = maxBytes < 0 ? 0 : maxBytes;
    final candidates = await _privateCachedFiles(entries);
    var currentBytes = candidates.fold<int>(
      0,
      (total, candidate) => total + candidate.byteCount,
    );
    final bytesBefore = currentBytes;
    final evictedEntryIds = <String>[];
    var evictedBytes = 0;

    candidates.sort((left, right) {
      final updatedComparison = left.entry.updatedAt.compareTo(
        right.entry.updatedAt,
      );
      if (updatedComparison != 0) {
        return updatedComparison;
      }

      return left.entry.track.title.toLowerCase().compareTo(
            right.entry.track.title.toLowerCase(),
          );
    });

    for (final candidate in candidates) {
      if (currentBytes <= limit) {
        break;
      }

      try {
        await candidate.file.delete();
      } on FileSystemException {
        // Missing or locked files should not prevent metadata cleanup.
      }
      currentBytes -= candidate.byteCount;
      evictedBytes += candidate.byteCount;
      evictedEntryIds.add(candidate.entry.id);
    }

    return OfflineCacheEvictionResult(
      bytesBefore: bytesBefore,
      bytesAfter: currentBytes,
      evictedEntryIds: List.unmodifiable(evictedEntryIds),
      evictedBytes: evictedBytes,
    );
  }

  Future<List<_OfflineCacheFileCandidate>> _privateCachedFiles(
    Iterable<OfflineCacheEntry> entries,
  ) async {
    final candidates = <_OfflineCacheFileCandidate>[];
    for (final entry in entries) {
      final file = _privateCacheFileFor(entry);
      if (file == null || !await file.exists()) {
        continue;
      }

      candidates.add(
        _OfflineCacheFileCandidate(
          entry: entry,
          file: file,
          byteCount: await file.length(),
        ),
      );
    }

    return candidates;
  }

  File? _privateCacheFileFor(OfflineCacheEntry entry) {
    if (entry.status != OfflineCacheEntryStatus.cached ||
        !entry.track.hasLocalSource) {
      return null;
    }

    final path = entry.track.localPath!;
    final normalizedMediaPath = p.normalize(mediaDirectory.path);
    final normalizedFilePath = p.normalize(path);
    if (normalizedFilePath != normalizedMediaPath &&
        !p.isWithin(normalizedMediaPath, normalizedFilePath)) {
      return null;
    }

    return File(path);
  }

  static Future<List<int>> _downloadWithHttpClient(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < HttpStatus.ok ||
          response.statusCode >= HttpStatus.multipleChoices) {
        throw HttpException(
          'HTTP ${response.statusCode} while downloading media.',
          uri: uri,
        );
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }
}

String _mediaExtension(Uri uri) {
  final extension = p.extension(uri.path).toLowerCase();
  final isSafeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension);
  return isSafeExtension ? extension : '.mp3';
}

String offlineMediaChecksum(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash = (hash ^ (byte & 0xff)).toUnsigned(64);
    hash = (hash * 0x100000001b3).toUnsigned(64);
  }

  return hash.toRadixString(16).padLeft(16, '0');
}
