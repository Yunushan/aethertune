import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/track.dart';
import 'provider_binary_loader.dart';

typedef ProviderArtworkCacheRootLoader = Future<Directory> Function();

final class ProviderArtworkFileCache {
  ProviderArtworkFileCache({
    ProviderArtworkCacheRootLoader? cacheRootLoader,
    this.maxFileCount = 256,
    this.maxTotalBytes = 100 * 1024 * 1024,
  }) : _cacheRootLoader = cacheRootLoader ?? getTemporaryDirectory;

  final ProviderArtworkCacheRootLoader _cacheRootLoader;
  final int maxFileCount;
  final int maxTotalBytes;
  Future<Directory>? _cacheRootRequest;

  Future<Uri> materialize({
    required String sourceId,
    required String artworkId,
    required Uint8List bytes,
    String? version,
  }) async {
    if (sourceId.trim().isEmpty || artworkId.trim().isEmpty) {
      throw ArgumentError('Provider and artwork IDs are required.');
    }
    if (bytes.isEmpty || bytes.length > maxProviderArtworkBytes) {
      throw StateError('Artwork bytes are empty or exceed the safety limit.');
    }
    if (maxFileCount <= 0 || maxTotalBytes <= 0) {
      throw StateError('Artwork file-cache limits must be positive.');
    }

    final directory = await _providerDirectory(sourceId);
    await directory.create(recursive: true);
    final fileKey = Track.stableLocalId(
      '${artworkId.trim()}|${version?.trim() ?? ''}',
    );
    final file = File(
      p.join(directory.path, '$fileKey${_imageExtension(bytes)}'),
    );
    if (await file.exists() && await file.length() > 0) {
      await _prune(keep: file);
      return file.uri;
    }

    final partial = File('${file.path}.part');
    if (await partial.exists()) {
      await partial.delete();
    }
    await partial.writeAsBytes(bytes, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await partial.rename(file.path);
    await _prune(keep: file);
    return file.uri;
  }

  Future<void> removeProvider(String sourceId) async {
    if (sourceId.trim().isEmpty) {
      return;
    }
    final root = await _artworkDirectory();
    final provider = await _providerDirectory(sourceId);
    final rootPath = p.normalize(p.absolute(root.path));
    final providerPath = p.normalize(p.absolute(provider.path));
    if (!p.isWithin(rootPath, providerPath)) {
      throw StateError('Refusing to remove artwork outside the private cache.');
    }
    if (await provider.exists()) {
      await provider.delete(recursive: true);
    }
  }

  Future<Directory> _providerDirectory(String sourceId) async {
    final root = await _artworkDirectory();
    return Directory(
      p.join(root.path, Track.stableLocalId(sourceId.trim())),
    );
  }

  Future<Directory> _artworkDirectory() async {
    final cacheRoot = await (_cacheRootRequest ??= _cacheRootLoader());
    return Directory(
      p.join(cacheRoot.path, 'aethertune', 'provider_artwork'),
    );
  }

  Future<void> _prune({required File keep}) async {
    final root = await _artworkDirectory();
    if (!await root.exists()) {
      return;
    }
    final candidates = <_ArtworkFileCandidate>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (entity.path.endsWith('.part')) {
        await entity.delete();
        continue;
      }
      final stat = await entity.stat();
      candidates.add(
        _ArtworkFileCandidate(
          file: entity,
          byteCount: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
    candidates.sort(
      (left, right) => left.modifiedAt.compareTo(right.modifiedAt),
    );
    var totalBytes = candidates.fold<int>(
      0,
      (total, candidate) => total + candidate.byteCount,
    );
    var totalFiles = candidates.length;
    for (final candidate in candidates) {
      if (totalFiles <= maxFileCount && totalBytes <= maxTotalBytes) {
        break;
      }
      if (p.equals(candidate.file.path, keep.path)) {
        continue;
      }
      if (await candidate.file.exists()) {
        await candidate.file.delete();
      }
      totalFiles -= 1;
      totalBytes -= candidate.byteCount;
    }
  }
}

final class _ArtworkFileCandidate {
  const _ArtworkFileCandidate({
    required this.file,
    required this.byteCount,
    required this.modifiedAt,
  });

  final File file;
  final int byteCount;
  final DateTime modifiedAt;
}

String _imageExtension(Uint8List bytes) {
  if (_startsWith(bytes, const <int>[0x89, 0x50, 0x4e, 0x47])) {
    return '.png';
  }
  if (_startsWith(bytes, const <int>[0xff, 0xd8, 0xff])) {
    return '.jpg';
  }
  if (_startsWith(bytes, const <int>[0x47, 0x49, 0x46, 0x38])) {
    return '.gif';
  }
  if (bytes.length >= 12 &&
      _startsWith(bytes, const <int>[0x52, 0x49, 0x46, 0x46]) &&
      _matchesAt(bytes, 8, const <int>[0x57, 0x45, 0x42, 0x50])) {
    return '.webp';
  }
  return '.img';
}

bool _startsWith(Uint8List bytes, List<int> signature) {
  return _matchesAt(bytes, 0, signature);
}

bool _matchesAt(Uint8List bytes, int offset, List<int> signature) {
  if (offset < 0 || offset + signature.length > bytes.length) {
    return false;
  }
  for (var index = 0; index < signature.length; index += 1) {
    if (bytes[offset + index] != signature[index]) {
      return false;
    }
  }
  return true;
}
