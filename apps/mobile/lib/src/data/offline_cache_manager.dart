// Public dependency names are part of the API; backing fields stay private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/offline_cache_cancellation.dart';
import '../domain/offline_cache_entry.dart';
import '../domain/track.dart';
import 'offline_cache_budget.dart';
import 'offline_cache_paths.dart';
import 'offline_cache_resume.dart';
import 'offline_media_integrity.dart';

export 'offline_media_integrity.dart' show OfflineMediaSizeLimitExceeded;
export 'offline_cache_budget.dart'
    show OfflineCacheBudget, OfflineCacheBusy, OfflineCacheQuotaExceeded;

typedef OfflineMediaDownloader = Future<List<int>> Function(Uri uri);

final class OfflineCacheMaterialization {
  const OfflineCacheMaterialization({
    required this.track,
    required this.byteCount,
    required this.checksum,
    required this.expectedMediaChecksumVerified,
    this.evictedEntryIds = const [],
    this.evictedBytes = 0,
  });

  final Track track;
  final int byteCount;
  final String checksum;
  final bool expectedMediaChecksumVerified;
  final List<String> evictedEntryIds;
  final int evictedBytes;
}

final class OfflineCacheUsage {
  const OfflineCacheUsage({
    required this.byteCount,
    required this.cachedEntryCount,
    this.partialByteCount = 0,
    this.unindexedByteCount = 0,
  });

  final int byteCount;
  final int cachedEntryCount;
  final int partialByteCount;
  final int unindexedByteCount;
}

final class OfflineCacheClearResult {
  const OfflineCacheClearResult({
    required this.deletedPaths,
    required this.byteCount,
    required this.failedFileCount,
  });
  final List<String> deletedPaths;
  final int byteCount;
  final int failedFileCount;
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
  _OfflineCacheFileCandidate({
    required OfflineCacheEntry entry,
    required this.file,
    required this.byteCount,
  }) : entries = [entry];

  final List<OfflineCacheEntry> entries;
  OfflineCacheEntry get entry => entries.first;
  final File file;
  final int byteCount;
}

final class OfflineCacheManager {
  OfflineCacheManager({
    required this.cacheRoot,
    OfflineMediaDownloader? downloader,
    this.requestTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 30),
    this.transferTimeout = const Duration(minutes: 30),
  }) : _downloader = downloader,
       _paths = OfflineCachePaths(cacheRoot) {
    if (requestTimeout <= Duration.zero ||
        idleTimeout <= Duration.zero ||
        transferTimeout <= Duration.zero) {
      throw ArgumentError('Offline transfer timeouts must be positive.');
    }
  }

  static const defaultMaximumMediaBytes = 500 * 1024 * 1024;

  final Directory cacheRoot;
  final OfflineMediaDownloader? _downloader;
  final OfflineCachePaths _paths;
  final Duration requestTimeout;
  final Duration idleTimeout;
  final Duration transferTimeout;

  Directory get mediaDirectory => _paths.mediaDirectory;

  Future<OfflineCacheMaterialization> materialize(
    OfflineCacheEntry entry, {
    OfflineCacheCancellationToken? cancellationToken,
    int maxBytes = defaultMaximumMediaBytes,
    OfflineCacheBudget? budget,
  }) async {
    OfflineCachePaths.fileStem(entry.id);
    return withOfflineCacheLock(
      _paths,
      () => _materialize(
        entry,
        cancellationToken: cancellationToken,
        maxBytes: maxBytes,
        budget:
            budget ?? OfflineCacheBudget(totalBytes: defaultMaximumMediaBytes),
      ),
      cancellationToken: cancellationToken,
    );
  }

  Future<OfflineCacheMaterialization> _materialize(
    OfflineCacheEntry entry, {
    OfflineCacheCancellationToken? cancellationToken,
    required int maxBytes,
    required OfflineCacheBudget budget,
  }) async {
    final fileStem = OfflineCachePaths.fileStem(entry.id);
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
    }
    cancellationToken?.throwIfCancelled();
    if (entry.track.hasLocalSource) {
      return OfflineCacheMaterialization(
        track: entry.track,
        byteCount: 0,
        checksum: '',
        expectedMediaChecksumVerified: false,
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

    await _paths.verifyDirectory(create: true);

    final file = File(
      p.join(mediaDirectory.path, '$fileStem${_mediaExtension(streamUri)}'),
    );
    final partialFile = File('${file.path}.part');
    await _paths.verifyDestination(file);
    await _paths.verifyDestination(partialFile);
    final resume = OfflineCacheResume(_paths, partialFile);
    final reservation = await OfflineCacheReservation.create(
      paths: _paths,
      budget: budget,
      entry: entry,
      destination: file,
      partial: partialFile,
    );
    final downloader = _downloader;
    try {
      if (downloader == null) {
        await _downloadWithHttpClient(
          streamUri,
          partialFile,
          maxBytes: maxBytes,
          cancellationToken: cancellationToken,
          expectedChecksum: entry.track.expectedMediaChecksum,
          reservation: reservation,
          resume: resume,
        );
      } else {
        final bytes = await downloader(streamUri).timeout(transferTimeout);
        cancellationToken?.throwIfCancelled();
        if (bytes.length > maxBytes) {
          throw OfflineMediaSizeLimitExceeded(maxBytes);
        }
        await reservation.reserve(bytes.length);
        await resume.delete();
        await _paths.verifyDestination(partialFile);
        await partialFile.writeAsBytes(bytes, flush: true);
      }
    } on OfflineMediaSizeLimitExceeded {
      await _paths.deleteFile(partialFile);
      await resume.delete();
      rethrow;
    } on OfflineCacheQuotaExceeded {
      await _paths.deleteFile(partialFile);
      await resume.delete();
      rethrow;
    }

    cancellationToken?.throwIfCancelled();
    await _paths.verifyDestination(partialFile);
    final inspection = await inspectOfflineMedia(
      partialFile,
      expectedChecksum: entry.track.expectedMediaChecksum,
      maxBytes: maxBytes,
      cancellationToken: cancellationToken,
    );
    if (inspection.byteCount == 0) {
      await _paths.deleteFile(partialFile);
      await resume.delete();
      throw StateError('Downloaded media is empty for ${entry.track.title}.');
    }
    if (entry.track.expectedMediaChecksum != null &&
        !inspection.expectedChecksumVerified) {
      await _paths.deleteFile(partialFile);
      await resume.delete();
      throw StateError(
        'Provider media checksum mismatch for ${entry.track.title}.',
      );
    }
    cancellationToken?.throwIfCancelled();
    // Never replace an existing cache until the new bytes pass verification.
    await _paths.verifyDestination(file);
    await _paths.verifyDestination(partialFile);
    await resume.delete();
    await partialFile.rename(file.path);

    return OfflineCacheMaterialization(
      track: entry.track.copyWith(localPath: file.path),
      byteCount: inspection.byteCount,
      checksum: inspection.checksum,
      expectedMediaChecksumVerified: inspection.expectedChecksumVerified,
      evictedEntryIds: List.unmodifiable(reservation.evictedEntryIds),
      evictedBytes: reservation.evictedBytes,
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

  Future<OfflineCacheUsage> storageUsage(Iterable<OfflineCacheEntry> entries) =>
      withOfflineCacheLock(_paths, () async {
        final cached = await _privateCachedFiles(entries);
        final known = cached.map((item) => _cachePathKey(item.file)).toSet();
        var total = 0;
        var partial = 0;
        var unindexed = 0;
        await for (final entity in mediaDirectory.list(followLinks: false)) {
          final file = File(entity.path);
          await _paths.verifyDestination(file);
          final size = await file.length();
          if (file.path.endsWith('.part.resume') && size <= 4096) continue;
          total += size;
          if (file.path.endsWith('.part')) {
            partial += size;
          } else if (!known.contains(_cachePathKey(file))) {
            unindexed += size;
          }
        }
        return OfflineCacheUsage(
          byteCount: total,
          cachedEntryCount: cached.length,
          partialByteCount: partial,
          unindexedByteCount: unindexed,
        );
      });

  /// Explicit user-directed cleanup, never automatic quota eviction. Validate
  /// all destinations first and report locked files without hiding partial work.
  Future<OfflineCacheClearResult> clearPrivateMedia() =>
      withOfflineCacheLock(_paths, () async {
        final files = <File>[];
        await for (final entity in mediaDirectory.list(followLinks: false)) {
          final file = File(entity.path);
          await _paths.verifyDestination(file);
          files.add(file);
        }
        final deleted = <String>[];
        var bytes = 0;
        var failures = 0;
        for (final file in files) {
          try {
            final size = await file.length();
            await _paths.deleteFile(file);
            bytes += size;
            deleted.add(file.absolute.path);
          } on FileSystemException {
            failures++;
          }
        }
        return OfflineCacheClearResult(
          deletedPaths: List.unmodifiable(deleted),
          byteCount: bytes,
          failedFileCount: failures,
        );
      });

  Future<OfflineCacheEvictionResult> evictToSize({
    required Iterable<OfflineCacheEntry> entries,
    required int maxBytes,
    bool skipIfBusy = false,
  }) async {
    try {
      return await withOfflineCacheLock(
        _paths,
        () => _evictToSize(entries: entries, maxBytes: maxBytes),
      );
    } on OfflineCacheBusy {
      if (!skipIfBusy) rethrow;
      final current = await usage(entries);
      return OfflineCacheEvictionResult(
        bytesBefore: current.byteCount,
        bytesAfter: current.byteCount,
        evictedEntryIds: const [],
        evictedBytes: 0,
      );
    }
  }

  Future<OfflineCacheEvictionResult> _evictToSize({
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
        await _paths.deleteFile(candidate.file);
      } on FileSystemException {
        // A locked file still consumes storage and must remain in the index.
        continue;
      }
      currentBytes -= candidate.byteCount;
      evictedBytes += candidate.byteCount;
      evictedEntryIds.addAll(candidate.entries.map((entry) => entry.id));
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
    final verifiedCache = await verifyCachedMedia(entry: entry);
    final sourceFile = verifiedCache.file;

    await destinationDirectory.create(recursive: true);
    final exportFile = await _availableExportFile(
      destinationDirectory,
      entry,
      p.extension(sourceFile.path),
    );
    try {
      await _paths.verifyDestination(sourceFile);
      final output = await exportFile.open(mode: FileMode.write);
      try {
        await for (final chunk in sourceFile.openRead()) {
          await output.writeFrom(chunk);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      final exported = await inspectOfflineMedia(exportFile);
      if (exported.byteCount != verifiedCache.byteCount ||
          exported.checksum != verifiedCache.checksum) {
        throw StateError(
          'Exported media checksum verification failed for ${entry.track.title}.',
        );
      }
    } on Object {
      await exportFile.delete();
      rethrow;
    }

    return OfflineCacheExport(
      file: exportFile,
      byteCount: verifiedCache.byteCount,
      checksum: verifiedCache.checksum,
    );
  }

  /// Verifies a private cached file before an explicit user-directed export.
  ///
  /// Callers may pass the resulting file to a platform-owned destination such
  /// as Android's system Downloads collection. The platform bridge must verify
  /// the supplied byte count and checksum again while copying it.
  Future<OfflineCacheExport> verifyCachedMedia({
    required OfflineCacheEntry entry,
  }) async {
    final sourceFile = _privateCacheFileFor(entry);
    if (sourceFile == null) {
      throw StateError(
        'Only private cached media can be exported for ${entry.track.title}.',
      );
    }
    if (!await _paths.containsRegularFile(sourceFile)) {
      throw StateError('Cached media is missing for ${entry.track.title}.');
    }

    final inspection = await inspectOfflineMedia(sourceFile);
    if (entry.cachedByteCount > 0 &&
        inspection.byteCount != entry.cachedByteCount) {
      throw StateError(
        'Cached media byte count changed for ${entry.track.title}.',
      );
    }

    final checksum = inspection.checksum;
    if (entry.cachedMediaChecksum.isNotEmpty &&
        checksum != entry.cachedMediaChecksum) {
      throw StateError(
        'Cached media checksum changed for ${entry.track.title}.',
      );
    }

    return OfflineCacheExport(
      file: sourceFile,
      byteCount: inspection.byteCount,
      checksum: checksum,
    );
  }

  String exportDisplayName(OfflineCacheEntry entry) {
    final sourceFile = _privateCacheFileFor(entry);
    return '${_safeExportBaseName(entry)}${_safeMediaExtension(sourceFile == null ? '' : p.extension(sourceFile.path))}';
  }

  Future<List<_OfflineCacheFileCandidate>> _privateCachedFiles(
    Iterable<OfflineCacheEntry> entries,
  ) async {
    final candidates = <String, _OfflineCacheFileCandidate>{};
    for (final entry in entries) {
      final file = _privateCacheFileFor(entry);
      if (file == null || !await _paths.containsRegularFile(file)) {
        continue;
      }

      final key = _cachePathKey(file);
      final existing = candidates[key];
      if (existing != null) {
        existing.entries.add(entry);
      } else {
        candidates[key] = _OfflineCacheFileCandidate(
          entry: entry,
          file: file,
          byteCount: await file.length(),
        );
      }
    }

    return candidates.values.toList();
  }

  File? _privateCacheFileFor(OfflineCacheEntry entry) {
    if (entry.status != OfflineCacheEntryStatus.cached ||
        !entry.track.hasLocalSource) {
      return null;
    }

    final path = entry.track.localPath!;
    if (!_paths.containsPath(File(path))) {
      return null;
    }

    return File(path);
  }

  Future<void> _downloadWithHttpClient(
    Uri uri,
    File partialFile, {
    required int maxBytes,
    OfflineCacheCancellationToken? cancellationToken,
    required String? expectedChecksum,
    required OfflineCacheReservation reservation,
    required OfflineCacheResume resume,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = requestTimeout
      ..autoUncompress = false;
    var deadlineExpired = false;
    final deadline = Timer(transferTimeout, () {
      deadlineExpired = true;
      client.close(force: true);
    });
    cancellationToken?.whenCancelled.then<void>((_) {
      client.close(force: true);
    });
    try {
      var resumeStart = await _fileLength(partialFile);
      if (resumeStart > maxBytes) {
        throw OfflineMediaSizeLimitExceeded(maxBytes);
      }
      var validator = await resume.validator(uri, expectedChecksum);
      if (resumeStart > 0 && validator == null && expectedChecksum == null) {
        await _paths.deleteFile(partialFile);
        await resume.delete();
        resumeStart = 0;
      }
      await reservation.reserve(resumeStart);
      var restartedAfterInvalidRange = false;
      while (true) {
        cancellationToken?.throwIfCancelled();
        final request = await client.getUrl(uri).timeout(requestTimeout);
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (resumeStart > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeStart-');
          if (validator != null) {
            request.headers.set(HttpHeaders.ifRangeHeader, validator);
          }
        }
        final response = await request.close().timeout(requestTimeout);
        cancellationToken?.throwIfCancelled();

        if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
            resumeStart > 0 &&
            !restartedAfterInvalidRange) {
          await response.listen(null).cancel();
          await _paths.deleteFile(partialFile);
          await resume.delete();
          resumeStart = 0;
          validator = null;
          restartedAfterInvalidRange = true;
          continue;
        }

        final shouldAppend =
            resumeStart > 0 && response.statusCode == HttpStatus.partialContent;
        final isFreshDownload = response.statusCode == HttpStatus.ok;
        if (!shouldAppend && !isFreshDownload) {
          throw HttpException(
            'HTTP ${response.statusCode} while downloading media.',
            uri: uri,
          );
        }

        final encoding = response.headers.value(
          HttpHeaders.contentEncodingHeader,
        );
        if (encoding != null && encoding.toLowerCase() != 'identity') {
          throw HttpException(
            'Offline media must use identity content encoding.',
            uri: uri,
          );
        }
        if (shouldAppend &&
            validator != null &&
            OfflineCacheResume.strongEtag(
                  response.headers.value(HttpHeaders.etagHeader),
                ) !=
                validator) {
          // A server that ignores If-Range must not splice different versions.
          await response.listen(null).cancel();
          if (restartedAfterInvalidRange) {
            throw HttpException('Media changed while resuming.', uri: uri);
          }
          await _paths.deleteFile(partialFile);
          await resume.delete();
          resumeStart = 0;
          validator = null;
          restartedAfterInvalidRange = true;
          continue;
        }

        int? expectedRangeBytes;
        if (shouldAppend) {
          final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
            response.headers.value(HttpHeaders.contentRangeHeader) ?? '',
          );
          final start = int.tryParse(range?.group(1) ?? '');
          final end = int.tryParse(range?.group(2) ?? '');
          final total = int.tryParse(range?.group(3) ?? '');
          if (start != resumeStart ||
              end == null ||
              total == null ||
              end < resumeStart ||
              end + 1 != total) {
            throw HttpException(
              'Invalid media resume Content-Range.',
              uri: uri,
            );
          }
          if (total > maxBytes) {
            throw OfflineMediaSizeLimitExceeded(maxBytes);
          }
          expectedRangeBytes = end - resumeStart + 1;
        }

        if (resumeStart > 0 && !shouldAppend) {
          await _paths.deleteFile(partialFile);
          resumeStart = 0;
        }

        final expectedResponseBytes = response.contentLength;
        if (expectedResponseBytes > maxBytes - resumeStart) {
          throw OfflineMediaSizeLimitExceeded(maxBytes);
        }
        await reservation.reserve(
          expectedRangeBytes != null
              ? resumeStart + expectedRangeBytes
              : expectedResponseBytes >= 0
              ? resumeStart + expectedResponseBytes
              : resumeStart,
        );
        if (!shouldAppend) {
          // Remove old bytes before publishing their replacement's validator.
          await _paths.deleteFile(partialFile);
          await resume.write(
            uri,
            expectedChecksum,
            response.headers.value(HttpHeaders.etagHeader),
          );
        }
        var receivedBytes = 0;
        await _paths.verifyDestination(partialFile);
        final output = await partialFile.open(
          mode: shouldAppend ? FileMode.append : FileMode.write,
        );
        try {
          await for (final chunk in response.timeout(idleTimeout)) {
            cancellationToken?.throwIfCancelled();
            if (deadlineExpired) {
              throw TimeoutException('Offline transfer deadline exceeded.');
            }
            receivedBytes += chunk.length;
            if (resumeStart + receivedBytes > maxBytes) {
              throw OfflineMediaSizeLimitExceeded(maxBytes);
            }
            await reservation.reserve(resumeStart + receivedBytes);
            await output.writeFrom(chunk);
          }
          await output.flush();
        } finally {
          await output.close();
        }

        if (expectedResponseBytes >= 0 &&
            receivedBytes != expectedResponseBytes) {
          throw HttpException(
            'Downloaded $receivedBytes of $expectedResponseBytes bytes.',
            uri: uri,
          );
        }

        if (expectedRangeBytes != null && receivedBytes != expectedRangeBytes) {
          throw HttpException('Incomplete media resume response.', uri: uri);
        }

        if (await partialFile.length() == 0) {
          throw StateError('Downloaded media is empty.');
        }

        cancellationToken?.throwIfCancelled();
        if (deadlineExpired) {
          throw TimeoutException('Offline transfer deadline exceeded.');
        }
        return;
      }
    } on Object {
      cancellationToken?.throwIfCancelled();
      if (deadlineExpired) {
        throw TimeoutException('Offline transfer deadline exceeded.');
      }
      rethrow;
    } finally {
      deadline.cancel();
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

String _cachePathKey(File file) => Platform.isWindows
    ? p.normalize(file.absolute.path).toLowerCase()
    : p.normalize(file.absolute.path);

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
  var candidate = File(
    p.join(destinationDirectory.path, '$baseName$extension'),
  );
  var suffix = 2;
  while (true) {
    try {
      await candidate.create(exclusive: true);
      return candidate;
    } on FileSystemException {
      if (await FileSystemEntity.type(candidate.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        rethrow;
      }
    }
    candidate = File(
      p.join(destinationDirectory.path, '$baseName ($suffix)$extension'),
    );
    suffix += 1;
  }
}

String _safeExportBaseName(OfflineCacheEntry entry) {
  final title = entry.track.title.trim();
  final artist = entry.track.artist.trim();
  final rawName = <String>[
    if (artist.isNotEmpty && artist != 'Unknown Artist') artist,
    if (title.isNotEmpty) title,
  ].join(' - ');
  final fallback = 'aethertune-${OfflineCachePaths.fileStem(entry.id)}';
  final sanitized = (rawName.isEmpty ? fallback : rawName)
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');

  if (sanitized.isEmpty) {
    return fallback;
  }

  final portable =
      RegExp(
        r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(sanitized)
      ? 'aethertune-$sanitized'
      : sanitized;
  return portable.length <= 96 ? portable : portable.substring(0, 96).trim();
}

String _safeMediaExtension(String rawExtension) {
  final extension = rawExtension.toLowerCase();
  final isSafeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension);
  return isSafeExtension ? extension : '.mp3';
}

String offlineMediaChecksum(List<int> bytes) {
  return (OfflineMediaChecksum()..add(bytes)).value;
}
