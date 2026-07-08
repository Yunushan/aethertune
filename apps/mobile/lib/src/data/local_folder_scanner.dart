import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/track.dart';

const supportedLocalAudioExtensions = <String>{
  '.aac',
  '.aiff',
  '.alac',
  '.flac',
  '.m4a',
  '.mp3',
  '.oga',
  '.ogg',
  '.opus',
  '.wav',
  '.wma',
};

final class LocalFolderScanResult {
  const LocalFolderScanResult({
    required this.tracks,
    required this.ignoredFileCount,
    required this.inaccessibleDirectoryCount,
  });

  final List<Track> tracks;
  final int ignoredFileCount;
  final int inaccessibleDirectoryCount;
}

final class _LocalFileMetadata {
  const _LocalFileMetadata({
    required this.title,
    required this.artist,
  });

  final String title;
  final String artist;
}

final class LocalFolderScanner {
  const LocalFolderScanner({
    this.supportedExtensions = supportedLocalAudioExtensions,
  });

  final Set<String> supportedExtensions;

  Future<LocalFolderScanResult> scan(
    String rootPath, {
    DateTime? importedAt,
  }) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      throw FileSystemException('Folder does not exist.', rootPath);
    }

    final scanState = _LocalFolderScanState(
      rootPath: root.path,
      importedAt: importedAt ?? DateTime.now(),
      supportedExtensions: supportedExtensions,
    );
    await scanState.visit(root);

    return LocalFolderScanResult(
      tracks: List.unmodifiable(scanState.tracks),
      ignoredFileCount: scanState.ignoredFileCount,
      inaccessibleDirectoryCount: scanState.inaccessibleDirectoryCount,
    );
  }
}

final class _LocalFolderScanState {
  _LocalFolderScanState({
    required this.rootPath,
    required this.importedAt,
    required this.supportedExtensions,
  });

  final String rootPath;
  final DateTime importedAt;
  final Set<String> supportedExtensions;
  final List<Track> tracks = <Track>[];
  int ignoredFileCount = 0;
  int inaccessibleDirectoryCount = 0;

  Future<void> visit(Directory directory) async {
    final entries = await _listDirectory(directory);
    if (entries == null) {
      inaccessibleDirectoryCount += 1;
      return;
    }

    entries.sort(
      (left, right) => left.path.toLowerCase().compareTo(
            right.path.toLowerCase(),
          ),
    );

    for (final entry in entries) {
      final entityType = await _entityType(entry);
      if (entityType == null) {
        continue;
      }
      if (entityType == FileSystemEntityType.directory) {
        await visit(Directory(entry.path));
        continue;
      }
      if (entityType != FileSystemEntityType.file) {
        continue;
      }
      if (!_isSupportedAudioPath(entry.path)) {
        ignoredFileCount += 1;
        continue;
      }

      tracks.add(_trackForFile(entry.path));
    }
  }

  Future<List<FileSystemEntity>?> _listDirectory(Directory directory) async {
    try {
      return await directory.list(followLinks: false).toList();
    } on FileSystemException {
      return null;
    }
  }

  Future<FileSystemEntityType?> _entityType(FileSystemEntity entity) async {
    try {
      return await FileSystemEntity.type(entity.path, followLinks: false);
    } on FileSystemException {
      return null;
    }
  }

  bool _isSupportedAudioPath(String path) {
    return supportedExtensions.contains(p.extension(path).toLowerCase());
  }

  Track _trackForFile(String path) {
    final metadata = _metadataForFile(path);

    return Track(
      id: Track.stableLocalId(path),
      title: metadata.title,
      artist: metadata.artist,
      album: _albumLabelFor(path),
      localPath: path,
      sourceId: 'local',
      addedAt: importedAt,
    );
  }

  String _albumLabelFor(String filePath) {
    final parent = p.dirname(filePath);
    final relativeParent = p.relative(parent, from: rootPath);
    if (relativeParent == '.') {
      return p.basename(rootPath);
    }

    return relativeParent;
  }

  _LocalFileMetadata _metadataForFile(String path) {
    final fallbackTitle = p.basenameWithoutExtension(path).trim();
    final normalizedName = _withoutLeadingTrackNumber(fallbackTitle);
    final titleParts = normalizedName
        .split(RegExp(r'\s+-\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    if (titleParts.length >= 2) {
      return _LocalFileMetadata(
        artist: titleParts.first,
        title: titleParts.skip(1).join(' - '),
      );
    }

    return _LocalFileMetadata(
      title: normalizedName.isEmpty ? fallbackTitle : normalizedName,
      artist: 'Local Folder',
    );
  }

  String _withoutLeadingTrackNumber(String value) {
    final match = RegExp(r'^\s*\d{1,3}[\s._-]+(.+)$').firstMatch(value);
    if (match == null) {
      return value.trim();
    }

    return match.group(1)!.trim().replaceFirst(RegExp(r'^[-._\s]+'), '');
  }
}
