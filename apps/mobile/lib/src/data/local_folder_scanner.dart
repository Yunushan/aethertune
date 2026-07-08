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
    this.album,
  });

  final String title;
  final String artist;
  final String? album;
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

      tracks.add(await _trackForFile(entry.path));
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

  Future<Track> _trackForFile(String path) async {
    final metadata = await _metadataForFile(path);

    return Track(
      id: Track.stableLocalId(path),
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album ?? _albumLabelFor(path),
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

  Future<_LocalFileMetadata> _metadataForFile(String path) async {
    final fallbackMetadata = _filenameMetadataForFile(path);
    final embeddedMetadata = await _embeddedMetadataForFile(path);
    if (embeddedMetadata == null) {
      return fallbackMetadata;
    }

    return _LocalFileMetadata(
      title: embeddedMetadata.title.isEmpty
          ? fallbackMetadata.title
          : embeddedMetadata.title,
      artist: embeddedMetadata.artist.isEmpty
          ? fallbackMetadata.artist
          : embeddedMetadata.artist,
      album: embeddedMetadata.album ?? fallbackMetadata.album,
    );
  }

  _LocalFileMetadata _filenameMetadataForFile(String path) {
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

  Future<_LocalFileMetadata?> _embeddedMetadataForFile(String path) async {
    if (p.extension(path).toLowerCase() != '.mp3') {
      return null;
    }

    try {
      final file = File(path);
      final length = await file.length();
      if (length < 128) {
        return null;
      }

      final access = await file.open();
      try {
        await access.setPosition(length - 128);
        final bytes = await access.read(128);
        return _id3v1Metadata(bytes);
      } finally {
        await access.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  _LocalFileMetadata? _id3v1Metadata(List<int> bytes) {
    if (bytes.length != 128 ||
        bytes[0] != 0x54 ||
        bytes[1] != 0x41 ||
        bytes[2] != 0x47) {
      return null;
    }

    final title = _id3v1Text(bytes, 3, 30);
    final artist = _id3v1Text(bytes, 33, 30);
    final album = _id3v1Text(bytes, 63, 30);
    if (title.isEmpty && artist.isEmpty && album.isEmpty) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album.isEmpty ? null : album,
    );
  }

  String _id3v1Text(List<int> bytes, int start, int length) {
    final rawBytes = bytes
        .skip(start)
        .take(length)
        .takeWhile((byte) => byte != 0)
        .toList(growable: false);
    final text = String.fromCharCodes(rawBytes)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return text;
  }
}
