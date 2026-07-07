import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/offline_cache_entry.dart';
import '../domain/track.dart';

typedef OfflineMediaDownloader = Future<List<int>> Function(Uri uri);

final class OfflineCacheMaterialization {
  const OfflineCacheMaterialization({
    required this.track,
    required this.byteCount,
  });

  final Track track;
  final int byteCount;
}

final class OfflineCacheManager {
  OfflineCacheManager({
    required this.cacheRoot,
    OfflineMediaDownloader? downloader,
  }) : _downloader = downloader ?? _downloadWithHttpClient;

  final Directory cacheRoot;
  final OfflineMediaDownloader _downloader;

  Future<OfflineCacheMaterialization> materialize(
    OfflineCacheEntry entry,
  ) async {
    if (entry.track.hasLocalSource) {
      return OfflineCacheMaterialization(
        track: entry.track,
        byteCount: 0,
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

    final mediaDirectory = Directory(
      p.join(cacheRoot.path, 'aethertune', 'offline_media'),
    );
    await mediaDirectory.create(recursive: true);

    final file = File(
      p.join(mediaDirectory.path, '${entry.id}${_mediaExtension(streamUri)}'),
    );
    await file.writeAsBytes(bytes, flush: true);

    return OfflineCacheMaterialization(
      track: entry.track.copyWith(localPath: file.path),
      byteCount: bytes.length,
    );
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
