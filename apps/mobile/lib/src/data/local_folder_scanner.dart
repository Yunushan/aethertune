import 'dart:convert';
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
    this.genre,
  });

  final String title;
  final String artist;
  final String? album;
  final String? genre;
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
      genre: metadata.genre ?? 'Unknown Genre',
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
      genre: embeddedMetadata.genre ?? fallbackMetadata.genre,
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
      if (length < 10) {
        return null;
      }

      final access = await file.open();
      try {
        await access.setPosition(0);
        final headerBytes = await access.read(10);
        final id3v2 = await _id3v2Metadata(access, headerBytes);
        if (id3v2 != null) {
          return id3v2;
        }

        if (length < 128) {
          return null;
        }

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

  Future<_LocalFileMetadata?> _id3v2Metadata(
    RandomAccessFile access,
    List<int> header,
  ) async {
    if (header.length != 10 ||
        header[0] != 0x49 ||
        header[1] != 0x44 ||
        header[2] != 0x33) {
      return null;
    }

    final majorVersion = header[3];
    if (majorVersion < 2 || majorVersion > 4) {
      return null;
    }

    final tagSize = _id3v2SynchsafeInt(header, 6);
    if (tagSize <= 0) {
      return null;
    }

    final bytesToRead = tagSize > _maxId3v2TagBytes
        ? _maxId3v2TagBytes
        : tagSize;
    final tagBytes = await access.read(bytesToRead);
    final textFrames = majorVersion == 2
        ? _id3v22TextFrames(tagBytes)
        : _id3v23Or24TextFrames(tagBytes, majorVersion);
    if (textFrames.isEmpty) {
      return null;
    }

    final title = textFrames['title'] ?? '';
    final artist = textFrames['artist'] ?? '';
    final album = textFrames['album'];
    final genre = textFrames['genre'];
    if (title.isEmpty &&
        artist.isEmpty &&
        (album == null || album.isEmpty) &&
        (genre == null || genre.isEmpty)) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album == null || album.isEmpty ? null : album,
      genre: genre == null || genre.isEmpty ? null : genre,
    );
  }

  Map<String, String> _id3v23Or24TextFrames(
    List<int> bytes,
    int majorVersion,
  ) {
    final textFrames = <String, String>{};
    var offset = 0;
    while (offset + 10 <= bytes.length) {
      final frameId = String.fromCharCodes(bytes.skip(offset).take(4));
      if (!_isId3v2FrameId(frameId)) {
        break;
      }

      final frameSize = majorVersion == 4
          ? _id3v2SynchsafeInt(bytes, offset + 4)
          : _uint32(bytes, offset + 4);
      offset += 10;
      if (frameSize <= 0 || offset + frameSize > bytes.length) {
        break;
      }

      final key = _id3v2FrameKey(frameId);
      if (key != null && !textFrames.containsKey(key)) {
        final value = _id3v2TextFrame(
          bytes.sublist(offset, offset + frameSize),
        );
        if (value.isNotEmpty) {
          textFrames[key] = value;
        }
      }

      offset += frameSize;
    }

    return textFrames;
  }

  Map<String, String> _id3v22TextFrames(List<int> bytes) {
    final textFrames = <String, String>{};
    var offset = 0;
    while (offset + 6 <= bytes.length) {
      final frameId = String.fromCharCodes(bytes.skip(offset).take(3));
      if (!_isId3v2FrameId(frameId)) {
        break;
      }

      final frameSize = _uint24(bytes, offset + 3);
      offset += 6;
      if (frameSize <= 0 || offset + frameSize > bytes.length) {
        break;
      }

      final key = _id3v2FrameKey(frameId);
      if (key != null && !textFrames.containsKey(key)) {
        final value = _id3v2TextFrame(
          bytes.sublist(offset, offset + frameSize),
        );
        if (value.isNotEmpty) {
          textFrames[key] = value;
        }
      }

      offset += frameSize;
    }

    return textFrames;
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

  String _id3v2TextFrame(List<int> bytes) {
    if (bytes.isEmpty) {
      return '';
    }

    final encoding = bytes.first;
    final payload = bytes.skip(1).toList(growable: false);
    final decoded = switch (encoding) {
      0 => latin1.decode(_trimTrailingZeroBytes(payload)),
      1 => _decodeUtf16(payload, useBom: true),
      2 => _decodeUtf16(payload, bigEndian: true),
      3 => utf8.decode(
          _trimTrailingZeroBytes(payload),
          allowMalformed: true,
        ),
      _ => utf8.decode(
          _trimTrailingZeroBytes(payload),
          allowMalformed: true,
        ),
    };

    return _normalizeEmbeddedText(decoded);
  }

  String _decodeUtf16(
    List<int> bytes, {
    bool useBom = false,
    bool bigEndian = false,
  }) {
    var offset = 0;
    var readBigEndian = bigEndian;
    if (useBom && bytes.length >= 2) {
      final first = bytes[0];
      final second = bytes[1];
      if (first == 0xfe && second == 0xff) {
        readBigEndian = true;
        offset = 2;
      } else if (first == 0xff && second == 0xfe) {
        readBigEndian = false;
        offset = 2;
      }
    }

    final codeUnits = <int>[];
    for (var index = offset; index + 1 < bytes.length; index += 2) {
      final codeUnit = readBigEndian
          ? (bytes[index] << 8) | bytes[index + 1]
          : bytes[index] | (bytes[index + 1] << 8);
      codeUnits.add(codeUnit);
    }

    return String.fromCharCodes(codeUnits);
  }

  String _normalizeEmbeddedText(String value) {
    final parts = value
        .replaceAll('\ufeff', '')
        .split(RegExp('\u0000+'))
        .map((part) => part.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    return parts.join(' / ');
  }

  List<int> _trimTrailingZeroBytes(List<int> bytes) {
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0) {
      end -= 1;
    }

    return bytes.take(end).toList(growable: false);
  }

  String? _id3v2FrameKey(String frameId) {
    switch (frameId) {
      case 'TIT2':
      case 'TT2':
        return 'title';
      case 'TPE1':
      case 'TP1':
        return 'artist';
      case 'TALB':
      case 'TAL':
        return 'album';
      case 'TCON':
      case 'TCO':
        return 'genre';
    }

    return null;
  }

  bool _isId3v2FrameId(String frameId) {
    return RegExp(r'^[A-Z0-9]{3,4}$').hasMatch(frameId);
  }

  int _id3v2SynchsafeInt(List<int> bytes, int offset) {
    if (offset + 4 > bytes.length) {
      return 0;
    }

    return ((bytes[offset] & 0x7f) << 21) |
        ((bytes[offset + 1] & 0x7f) << 14) |
        ((bytes[offset + 2] & 0x7f) << 7) |
        (bytes[offset + 3] & 0x7f);
  }

  int _uint32(List<int> bytes, int offset) {
    if (offset + 4 > bytes.length) {
      return 0;
    }

    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  int _uint24(List<int> bytes, int offset) {
    if (offset + 3 > bytes.length) {
      return 0;
    }

    return (bytes[offset] << 16) |
        (bytes[offset + 1] << 8) |
        bytes[offset + 2];
  }
}

const _maxId3v2TagBytes = 1024 * 1024;
