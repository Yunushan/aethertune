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

final class OfflineCacheExport {
  const OfflineCacheExport({
    required this.file,
    required this.byteCount,
    required this.checksum,
  });

  final File file;
  final int byteCount;
  final String checksum;
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
  }) : _downloader = downloader;

  final Directory cacheRoot;
  final OfflineMediaDownloader? _downloader;

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

    await mediaDirectory.create(recursive: true);

    final file = File(
      p.join(mediaDirectory.path, '${entry.id}${_mediaExtension(streamUri)}'),
    );
    final partialFile = File('${file.path}.part');
    final downloader = _downloader;
    if (downloader == null) {
      await _downloadWithHttpClient(streamUri, file, partialFile);
    } else {
      final bytes = await downloader(streamUri);
      if (bytes.isEmpty) {
        throw StateError('Downloaded media is empty for ${entry.track.title}.');
      }
      await _deleteIfExists(partialFile);
      await file.writeAsBytes(bytes, flush: true);
    }

    final savedBytes = await file.readAsBytes();
    if (savedBytes.isEmpty) {
      throw StateError('Downloaded media is empty for ${entry.track.title}.');
    }
    final checksum = offlineMediaChecksum(savedBytes);
    final savedBytesAfterChecksum = await file.readAsBytes();
    if (savedBytesAfterChecksum.length != savedBytes.length ||
        offlineMediaChecksum(savedBytesAfterChecksum) != checksum) {
      throw StateError(
        'Cached media checksum verification failed for ${entry.track.title}.',
      );
    }

    return OfflineCacheMaterialization(
      track: entry.track.copyWith(localPath: file.path),
      byteCount: savedBytes.length,
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

  Future<OfflineCacheExport> exportCachedMedia({
    required OfflineCacheEntry entry,
    required Directory destinationDirectory,
  }) async {
    final sourceFile = _privateCacheFileFor(entry);
    if (sourceFile == null) {
      throw StateError(
        'Only private cached media can be exported for ${entry.track.title}.',
      );
    }
    if (!await sourceFile.exists()) {
      throw StateError('Cached media is missing for ${entry.track.title}.');
    }

    final sourceBytes = await sourceFile.readAsBytes();
    if (entry.cachedByteCount > 0 &&
        sourceBytes.length != entry.cachedByteCount) {
      throw StateError(
        'Cached media byte count changed for ${entry.track.title}.',
      );
    }

    final checksum = offlineMediaChecksum(sourceBytes);
    if (entry.cachedMediaChecksum.isNotEmpty &&
        checksum != entry.cachedMediaChecksum) {
      throw StateError(
        'Cached media checksum changed for ${entry.track.title}.',
      );
    }

    await destinationDirectory.create(recursive: true);
    final exportFile = await _availableExportFile(
      destinationDirectory,
      entry,
      p.extension(sourceFile.path),
    );
    await exportFile.writeAsBytes(sourceBytes, flush: true);

    final exportedBytes = await exportFile.readAsBytes();
    if (exportedBytes.length != sourceBytes.length ||
        offlineMediaChecksum(exportedBytes) != checksum) {
      throw StateError(
        'Exported media checksum verification failed for ${entry.track.title}.',
      );
    }

    return OfflineCacheExport(
      file: exportFile,
      byteCount: exportedBytes.length,
      checksum: checksum,
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

  static Future<void> _downloadWithHttpClient(
    Uri uri,
    File targetFile,
    File partialFile,
  ) async {
    final client = HttpClient();
    try {
      var resumeStart = await _fileLength(partialFile);
      var restartedAfterInvalidRange = false;
      while (true) {
        final request = await client.getUrl(uri);
        if (resumeStart > 0) {
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=$resumeStart-',
          );
        }
        final response = await request.close();

        if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
            resumeStart > 0 &&
            !restartedAfterInvalidRange) {
          await _drainResponse(response);
          await _deleteIfExists(partialFile);
          resumeStart = 0;
          restartedAfterInvalidRange = true;
          continue;
        }

        final shouldAppend = resumeStart > 0 &&
            response.statusCode == HttpStatus.partialContent;
        final isFreshDownload = response.statusCode == HttpStatus.ok;
        if (!shouldAppend && !isFreshDownload) {
          throw HttpException(
            'HTTP ${response.statusCode} while downloading media.',
            uri: uri,
          );
        }

        if (resumeStart > 0 && !shouldAppend) {
          await _deleteIfExists(partialFile);
          resumeStart = 0;
        }

        final expectedResponseBytes = response.contentLength;
        var receivedBytes = 0;
        final sink = partialFile.openWrite(
          mode: shouldAppend ? FileMode.append : FileMode.write,
        );
        try {
          await for (final chunk in response) {
            receivedBytes += chunk.length;
            sink.add(chunk);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        if (expectedResponseBytes >= 0 &&
            receivedBytes != expectedResponseBytes) {
          throw HttpException(
            'Downloaded $receivedBytes of $expectedResponseBytes bytes.',
            uri: uri,
          );
        }

        if (await partialFile.length() == 0) {
          throw StateError('Downloaded media is empty.');
        }

        await _deleteIfExists(targetFile);
        await partialFile.rename(targetFile.path);
        return;
      }
    } finally {
      client.close(force: true);
    }
  }
}

Future<int> _fileLength(File file) async {
  try {
    return await file.length();
  } on FileSystemException {
    return 0;
  }
}

Future<void> _deleteIfExists(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // A missing or locked temp file should not mask the real cache operation.
  }
}

Future<void> _drainResponse(HttpClientResponse response) async {
  await for (final _ in response) {
    // Drain so the client can reuse/close the connection cleanly.
  }
}

String _mediaExtension(Uri uri) {
  final extension = p.extension(uri.path).toLowerCase();
  final isSafeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension);
  return isSafeExtension ? extension : '.mp3';
}

Future<File> _availableExportFile(
  Directory destinationDirectory,
  OfflineCacheEntry entry,
  String rawExtension,
) async {
  final extension = _safeMediaExtension(rawExtension);
  final baseName = _safeExportBaseName(entry);
  var candidate = File(p.join(destinationDirectory.path, '$baseName$extension'));
  var suffix = 2;
  while (await candidate.exists()) {
    candidate = File(
      p.join(destinationDirectory.path, '$baseName ($suffix)$extension'),
    );
    suffix += 1;
  }

  return candidate;
}

String _safeExportBaseName(OfflineCacheEntry entry) {
  final title = entry.track.title.trim();
  final artist = entry.track.artist.trim();
  final rawName = <String>[
    if (artist.isNotEmpty && artist != 'Unknown Artist') artist,
    if (title.isNotEmpty) title,
  ].join(' - ');
  final fallback = 'aethertune-${entry.id}';
  final sanitized = (rawName.isEmpty ? fallback : rawName)
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');

  if (sanitized.isEmpty) {
    return fallback;
  }

  return sanitized.length <= 96 ? sanitized : sanitized.substring(0, 96).trim();
}

String _safeMediaExtension(String rawExtension) {
  final extension = rawExtension.toLowerCase();
  final isSafeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension);
  return isSafeExtension ? extension : '.mp3';
}

String offlineMediaChecksum(List<int> bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = (hash ^ (byte & 0xff)).toUnsigned(32);
    hash = (hash * 0x01000193).toUnsigned(32);
  }

  return hash.toRadixString(16).padLeft(8, '0');
}
