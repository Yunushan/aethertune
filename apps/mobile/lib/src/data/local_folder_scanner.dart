import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/lyrics_document.dart';
import '../domain/replay_gain.dart';
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
    required this.sidecarLyricsByTrackId,
    this.embeddedLyricsByTrackId = const <String, String>{},
  });

  final List<Track> tracks;
  final int ignoredFileCount;
  final int inaccessibleDirectoryCount;
  final Map<String, String> sidecarLyricsByTrackId;
  final Map<String, String> embeddedLyricsByTrackId;

  int get sidecarLyricsCount => sidecarLyricsByTrackId.length;
  int get embeddedLyricsCount => embeddedLyricsByTrackId.length;
}

final class _LocalFileMetadata {
  const _LocalFileMetadata({
    required this.title,
    required this.artist,
    this.album,
    this.genre,
    this.artworkUri,
    this.replayGainTrackDb,
    this.replayGainAlbumDb,
    this.embeddedLyrics,
  });

  final String title;
  final String artist;
  final String? album;
  final String? genre;
  final Uri? artworkUri;
  final double? replayGainTrackDb;
  final double? replayGainAlbumDb;
  final String? embeddedLyrics;
}

final class _ScannedLocalTrack {
  const _ScannedLocalTrack({
    required this.track,
    this.embeddedLyrics,
  });

  final Track track;
  final String? embeddedLyrics;
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
      sidecarLyricsByTrackId: Map.unmodifiable(
        scanState.sidecarLyricsByTrackId,
      ),
      embeddedLyricsByTrackId: Map.unmodifiable(
        scanState.embeddedLyricsByTrackId,
      ),
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
  final Map<String, String> sidecarLyricsByTrackId = <String, String>{};
  final Map<String, String> embeddedLyricsByTrackId = <String, String>{};
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
        if (await _isMatchedSidecarLyricsPath(entry.path)) {
          continue;
        }
        ignoredFileCount += 1;
        continue;
      }

      final scannedTrack = await _trackForFile(entry.path);
      final track = scannedTrack.track;
      tracks.add(track);
      final sidecarLyrics = await _sidecarLyricsForFile(entry.path);
      if (sidecarLyrics != null) {
        sidecarLyricsByTrackId[track.id] = sidecarLyrics;
      } else if (scannedTrack.embeddedLyrics != null) {
        embeddedLyricsByTrackId[track.id] = scannedTrack.embeddedLyrics!;
      }
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

  Future<bool> _isMatchedSidecarLyricsPath(String path) async {
    if (!isSupportedLyricsDocumentName(p.basename(path))) {
      return false;
    }

    final siblings = await _siblingFilePathsWithSameStem(path);
    return siblings.any(
      (siblingPath) =>
          siblingPath.toLowerCase() != path.toLowerCase() &&
          supportedExtensions.contains(p.extension(siblingPath).toLowerCase()),
    );
  }

  Future<_ScannedLocalTrack> _trackForFile(String path) async {
    final metadata = await _metadataForFile(path);
    final contentHash = await _contentHashForFile(path);

    return _ScannedLocalTrack(
      track: Track(
        id: Track.stableLocalId(path),
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album ?? _albumLabelFor(path),
        genre: metadata.genre ?? 'Unknown Genre',
        artworkUri: metadata.artworkUri,
        localPath: path,
        contentHash: contentHash,
        replayGainTrackDb: metadata.replayGainTrackDb,
        replayGainAlbumDb: metadata.replayGainAlbumDb,
        sourceId: 'local',
        addedAt: importedAt,
      ),
      embeddedLyrics: metadata.embeddedLyrics,
    );
  }

  Future<String?> _contentHashForFile(String path) async {
    try {
      return localFileContentHash(await File(path).readAsBytes());
    } on FileSystemException {
      return null;
    }
  }

  Future<String?> _sidecarLyricsForFile(String path) async {
    final sidecarPathsByExtension = <String, String>{};
    for (final siblingPath in await _siblingFilePathsWithSameStem(path)) {
      final extension = p.extension(siblingPath).toLowerCase();
      if (_sidecarLyricsExtensionsByPreference.contains(extension)) {
        sidecarPathsByExtension.putIfAbsent(extension, () => siblingPath);
      }
    }

    for (final extension in _sidecarLyricsExtensionsByPreference) {
      final sidecarPath = sidecarPathsByExtension[extension];
      if (sidecarPath == null) {
        continue;
      }

      try {
        final lyrics = decodeLyricsDocumentBytes(
          await File(sidecarPath).readAsBytes(),
          fileName: p.basename(sidecarPath),
        );
        if (lyrics.isNotEmpty) {
          return lyrics;
        }
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }

    return null;
  }

  Future<List<String>> _siblingFilePathsWithSameStem(String path) async {
    final entries = await _listDirectory(Directory(p.dirname(path)));
    if (entries == null) {
      return const <String>[];
    }

    final stem = p.basenameWithoutExtension(path).toLowerCase();
    final siblings = <String>[];
    for (final entry in entries) {
      if (p.basenameWithoutExtension(entry.path).toLowerCase() != stem) {
        continue;
      }
      if (await _entityType(entry) == FileSystemEntityType.file) {
        siblings.add(entry.path);
      }
    }

    return siblings;
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
      artworkUri: embeddedMetadata.artworkUri ?? fallbackMetadata.artworkUri,
      replayGainTrackDb: embeddedMetadata.replayGainTrackDb,
      replayGainAlbumDb: embeddedMetadata.replayGainAlbumDb,
      embeddedLyrics: embeddedMetadata.embeddedLyrics,
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
    switch (p.extension(path).toLowerCase()) {
      case '.mp3':
        return _mp3MetadataForFile(path);
      case '.flac':
        return _flacMetadataForFile(path);
      case '.ogg':
      case '.oga':
      case '.opus':
        return _oggMetadataForFile(path);
      case '.m4a':
        return _m4aMetadataForFile(path);
      case '.wav':
        return _wavMetadataForFile(path);
    }

    return null;
  }

  Future<_LocalFileMetadata?> _mp3MetadataForFile(String path) async {
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

  Future<_LocalFileMetadata?> _flacMetadataForFile(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 8) {
        return null;
      }

      final access = await file.open();
      try {
        final marker = await access.read(4);
        if (!_matchesAscii(marker, 'fLaC')) {
          return null;
        }

        _LocalFileMetadata? metadata;
        Uri? artworkUri;
        var metadataBytesRead = 0;
        while (metadataBytesRead < _maxFlacMetadataBytes) {
          final header = await access.read(4);
          if (header.length != 4) {
            return null;
          }

          final isLastBlock = (header[0] & 0x80) != 0;
          final blockType = header[0] & 0x7f;
          final blockLength = _uint24(header, 1);
          metadataBytesRead += 4 + blockLength;

          if (blockLength < 0 || metadataBytesRead > _maxFlacMetadataBytes) {
            return null;
          }

          if (blockType == _flacVorbisCommentBlockType ||
              blockType == _flacPictureBlockType) {
            final blockBytes = await access.read(blockLength);
            if (blockBytes.length != blockLength) {
              return null;
            }

            if (blockType == _flacVorbisCommentBlockType) {
              metadata = _vorbisCommentMetadata(blockBytes) ?? metadata;
            } else {
              artworkUri = _flacPictureArtworkUri(blockBytes) ?? artworkUri;
            }
          } else {
            await access.setPosition(await access.position() + blockLength);
          }

          if (isLastBlock) {
            break;
          }
        }

        if (metadata == null && artworkUri == null) {
          return null;
        }

        return _LocalFileMetadata(
          title: metadata?.title ?? '',
          artist: metadata?.artist ?? '',
          album: metadata?.album,
          genre: metadata?.genre,
          artworkUri: artworkUri,
          replayGainTrackDb: metadata?.replayGainTrackDb,
          replayGainAlbumDb: metadata?.replayGainAlbumDb,
          embeddedLyrics: metadata?.embeddedLyrics,
        );
      } finally {
        await access.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  Future<_LocalFileMetadata?> _oggMetadataForFile(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 27) {
        return null;
      }

      final access = await file.open();
      try {
        final bytes = await access.read(
          length > _maxOggMetadataBytes ? _maxOggMetadataBytes : length,
        );
        final packets = _oggPackets(bytes);
        if (packets.length < 2) {
          return null;
        }

        final firstPacket = packets.first;
        final isVorbis = _startsWithBytes(
          firstPacket,
          const <int>[1, 0x76, 0x6f, 0x72, 0x62, 0x69, 0x73],
        );
        final isOpus = _startsWithAscii(firstPacket, 'OpusHead');
        if (!isVorbis && !isOpus) {
          return null;
        }

        List<int>? commentBytes;
        for (final packet in packets.skip(1)) {
          if (isVorbis &&
              _startsWithBytes(
                packet,
                const <int>[3, 0x76, 0x6f, 0x72, 0x62, 0x69, 0x73],
              )) {
            commentBytes = packet.sublist(7);
            break;
          }
          if (isOpus && _startsWithAscii(packet, 'OpusTags')) {
            commentBytes = packet.sublist(8);
            break;
          }
        }
        if (commentBytes == null) {
          return null;
        }

        final comments = _vorbisComments(commentBytes);
        if (comments == null) {
          return null;
        }
        final metadata = _vorbisCommentMetadataFromComments(comments);
        final artworkUri = _vorbisCommentArtworkUri(comments);
        final embeddedLyrics = _vorbisCommentLyrics(comments);
        if (metadata == null && artworkUri == null && embeddedLyrics == null) {
          return null;
        }

        return _LocalFileMetadata(
          title: metadata?.title ?? '',
          artist: metadata?.artist ?? '',
          album: metadata?.album,
          genre: metadata?.genre,
          artworkUri: artworkUri,
          replayGainTrackDb: metadata?.replayGainTrackDb,
          replayGainAlbumDb: metadata?.replayGainAlbumDb,
          embeddedLyrics: embeddedLyrics,
        );
      } finally {
        await access.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  Future<_LocalFileMetadata?> _wavMetadataForFile(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 12) {
        return null;
      }

      final access = await file.open();
      try {
        final header = await access.read(12);
        if (header.length != 12 ||
            !_matchesAscii(header.sublist(0, 4), 'RIFF') ||
            !_matchesAscii(header.sublist(8, 12), 'WAVE')) {
          return null;
        }

        final infoTags = <String, String>{};
        var chunkCount = 0;
        while (chunkCount < _maxWavChunks) {
          final chunkStart = await access.position();
          if (chunkStart + 8 > length) {
            break;
          }

          chunkCount += 1;
          final chunkHeader = await access.read(8);
          if (chunkHeader.length != 8) {
            break;
          }

          final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
          final chunkLength = _uint32LittleEndian(chunkHeader, 4);
          final payloadStart = await access.position();
          final payloadEnd = payloadStart + chunkLength;
          if (chunkLength < 0 || payloadEnd > length) {
            break;
          }

          if (chunkId == 'LIST' &&
              chunkLength >= 4 &&
              chunkLength <= _maxWavInfoBytes) {
            final payload = await access.read(chunkLength);
            if (payload.length != chunkLength) {
              break;
            }

            if (_matchesAscii(payload.sublist(0, 4), 'INFO')) {
              _readWavInfoList(payload, 4, payload.length, infoTags);
              if (_wavInfoComplete(infoTags)) {
                break;
              }
            }
          } else {
            await access.setPosition(payloadEnd);
          }

          final nextOffset = payloadEnd + (chunkLength.isOdd ? 1 : 0);
          await access.setPosition(nextOffset > length ? length : nextOffset);
        }

        return _wavMetadataFromInfoTags(infoTags);
      } finally {
        await access.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  Future<_LocalFileMetadata?> _m4aMetadataForFile(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 8) {
        return null;
      }

      final access = await file.open();
      try {
        var atomCount = 0;
        while (atomCount < _maxMp4TopLevelAtoms) {
          final atomStart = await access.position();
          if (atomStart + 8 > length) {
            break;
          }

          atomCount += 1;
          final header = await access.read(8);
          if (header.length != 8) {
            return null;
          }

          var atomSize = _uint32(header, 0);
          var headerSize = 8;
          if (atomSize == 1) {
            final extendedSize = await access.read(8);
            if (extendedSize.length != 8) {
              return null;
            }
            atomSize = _uint64(extendedSize, 0);
            headerSize = 16;
          } else if (atomSize == 0) {
            atomSize = length - atomStart;
          }

          if (atomSize < headerSize || atomStart + atomSize > length) {
            return null;
          }

          if (_matchesAscii(header.sublist(4, 8), 'moov')) {
            final payloadLength = atomSize - headerSize;
            if (payloadLength > _maxM4aMetadataBytes) {
              return null;
            }

            final payload = await access.read(payloadLength);
            if (payload.length != payloadLength) {
              return null;
            }

            return _m4aMetadata(payload);
          }

          await access.setPosition(atomStart + atomSize);
        }

        return null;
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
    final tagData = majorVersion == 2
        ? _id3v22TagData(tagBytes)
        : _id3v23Or24TagData(tagBytes, majorVersion);
    if (tagData.textFrames.isEmpty &&
        tagData.artworkUri == null &&
        tagData.replayGainTrackDb == null &&
        tagData.replayGainAlbumDb == null &&
        tagData.embeddedLyrics == null) {
      return null;
    }

    final title = tagData.textFrames['title'] ?? '';
    final artist = tagData.textFrames['artist'] ?? '';
    final album = tagData.textFrames['album'];
    final genre = tagData.textFrames['genre'];
    if (title.isEmpty &&
        artist.isEmpty &&
        (album == null || album.isEmpty) &&
        (genre == null || genre.isEmpty) &&
        tagData.artworkUri == null &&
        tagData.replayGainTrackDb == null &&
        tagData.replayGainAlbumDb == null &&
        tagData.embeddedLyrics == null) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album == null || album.isEmpty ? null : album,
      genre: genre == null || genre.isEmpty ? null : genre,
      artworkUri: tagData.artworkUri,
      replayGainTrackDb: tagData.replayGainTrackDb,
      replayGainAlbumDb: tagData.replayGainAlbumDb,
      embeddedLyrics: tagData.embeddedLyrics,
    );
  }

  _Id3v2TagData _id3v23Or24TagData(
    List<int> bytes,
    int majorVersion,
  ) {
    final textFrames = <String, String>{};
    Uri? artworkUri;
    double? replayGainTrackDb;
    double? replayGainAlbumDb;
    String? embeddedLyrics;
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
      } else if (frameId == 'APIC' && artworkUri == null) {
        artworkUri = _id3v23PictureArtworkUri(
          bytes.sublist(offset, offset + frameSize),
        );
      } else if (frameId == 'TXXX' && replayGainTrackDb == null) {
        replayGainTrackDb = _id3v2ReplayGainUserText(
          bytes.sublist(offset, offset + frameSize),
          'REPLAYGAIN_TRACK_GAIN',
        );
        replayGainAlbumDb ??= _id3v2ReplayGainUserText(
          bytes.sublist(offset, offset + frameSize),
          'REPLAYGAIN_ALBUM_GAIN',
        );
      } else if (frameId == 'TXXX' && replayGainAlbumDb == null) {
        replayGainAlbumDb = _id3v2ReplayGainUserText(
          bytes.sublist(offset, offset + frameSize),
          'REPLAYGAIN_ALBUM_GAIN',
        );
      } else if (frameId == 'USLT' && embeddedLyrics == null) {
        embeddedLyrics = _id3v2UnsynchronizedLyrics(
          bytes.sublist(offset, offset + frameSize),
        );
      }

      offset += frameSize;
    }

    return _Id3v2TagData(
      textFrames: textFrames,
      artworkUri: artworkUri,
      replayGainTrackDb: replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb,
      embeddedLyrics: embeddedLyrics,
    );
  }

  _Id3v2TagData _id3v22TagData(List<int> bytes) {
    final textFrames = <String, String>{};
    Uri? artworkUri;
    double? replayGainTrackDb;
    double? replayGainAlbumDb;
    String? embeddedLyrics;
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
      } else if (frameId == 'PIC' && artworkUri == null) {
        artworkUri = _id3v22PictureArtworkUri(
          bytes.sublist(offset, offset + frameSize),
        );
      } else if (frameId == 'TXX' && replayGainTrackDb == null) {
        replayGainTrackDb = _id3v2ReplayGainUserText(
          bytes.sublist(offset, offset + frameSize),
          'REPLAYGAIN_TRACK_GAIN',
        );
        replayGainAlbumDb ??= _id3v2ReplayGainUserText(
          bytes.sublist(offset, offset + frameSize),
          'REPLAYGAIN_ALBUM_GAIN',
        );
      } else if (frameId == 'TXX' && replayGainAlbumDb == null) {
        replayGainAlbumDb = _id3v2ReplayGainUserText(
          bytes.sublist(offset, offset + frameSize),
          'REPLAYGAIN_ALBUM_GAIN',
        );
      } else if (frameId == 'ULT' && embeddedLyrics == null) {
        embeddedLyrics = _id3v2UnsynchronizedLyrics(
          bytes.sublist(offset, offset + frameSize),
        );
      }

      offset += frameSize;
    }

    return _Id3v2TagData(
      textFrames: textFrames,
      artworkUri: artworkUri,
      replayGainTrackDb: replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb,
      embeddedLyrics: embeddedLyrics,
    );
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

  _LocalFileMetadata? _vorbisCommentMetadata(List<int> bytes) {
    final comments = _vorbisComments(bytes);
    if (comments == null) {
      return null;
    }
    final metadata = _vorbisCommentMetadataFromComments(comments);
    final embeddedLyrics = _vorbisCommentLyrics(comments);
    if (metadata == null && embeddedLyrics == null) {
      return null;
    }
    return _LocalFileMetadata(
      title: metadata?.title ?? '',
      artist: metadata?.artist ?? '',
      album: metadata?.album,
      genre: metadata?.genre,
      replayGainTrackDb: metadata?.replayGainTrackDb,
      replayGainAlbumDb: metadata?.replayGainAlbumDb,
      embeddedLyrics: embeddedLyrics,
    );
  }

  Map<String, List<String>>? _vorbisComments(List<int> bytes) {
    var offset = 0;
    if (offset + 4 > bytes.length) {
      return null;
    }
    final vendorLength = _uint32LittleEndian(bytes, offset);
    offset += 4;
    if (vendorLength < 0 || offset + vendorLength > bytes.length) {
      return null;
    }

    offset += vendorLength;
    if (offset + 4 > bytes.length) {
      return null;
    }
    final commentCount = _uint32LittleEndian(bytes, offset);
    offset += 4;
    if (commentCount < 0 || commentCount > _maxVorbisComments) {
      return null;
    }

    final comments = <String, List<String>>{};
    for (var index = 0; index < commentCount; index += 1) {
      if (offset + 4 > bytes.length) {
        return null;
      }

      final commentLength = _uint32LittleEndian(bytes, offset);
      offset += 4;
      if (commentLength < 0 || offset + commentLength > bytes.length) {
        return null;
      }

      final rawComment = utf8.decode(
        bytes.sublist(offset, offset + commentLength),
        allowMalformed: true,
      );
      offset += commentLength;

      final separatorIndex = rawComment.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }

      final key = rawComment.substring(0, separatorIndex).toUpperCase();
      final value = _isVorbisLyricsKey(key)
          ? _normalizeEmbeddedLyrics(rawComment.substring(separatorIndex + 1))
          : _normalizeEmbeddedText(rawComment.substring(separatorIndex + 1));
      if (value == null || value.isEmpty) {
        continue;
      }

      comments.putIfAbsent(key, () => <String>[]).add(value);
    }

    return comments;
  }

  _LocalFileMetadata? _vorbisCommentMetadataFromComments(
    Map<String, List<String>> comments,
  ) {
    final title = _firstVorbisComment(comments, 'TITLE') ?? '';
    final artist = _joinedVorbisComment(comments, 'ARTIST') ?? '';
    final album = _firstVorbisComment(comments, 'ALBUM');
    final genre = _joinedVorbisComment(comments, 'GENRE');
    final replayGainTrackDb = parseReplayGainDb(
      _firstVorbisComment(comments, 'REPLAYGAIN_TRACK_GAIN'),
    );
    final replayGainAlbumDb = parseReplayGainDb(
      _firstVorbisComment(comments, 'REPLAYGAIN_ALBUM_GAIN'),
    );
    if (title.isEmpty &&
        artist.isEmpty &&
        (album == null || album.isEmpty) &&
        (genre == null || genre.isEmpty) &&
        replayGainTrackDb == null &&
        replayGainAlbumDb == null) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album == null || album.isEmpty ? null : album,
      genre: genre == null || genre.isEmpty ? null : genre,
      replayGainTrackDb: replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb,
    );
  }

  String? _vorbisCommentLyrics(Map<String, List<String>> comments) {
    return _firstVorbisComment(comments, 'LYRICS') ??
        _firstVorbisComment(comments, 'UNSYNCEDLYRICS');
  }

  bool _isVorbisLyricsKey(String key) =>
      key == 'LYRICS' || key == 'UNSYNCEDLYRICS';

  Uri? _vorbisCommentArtworkUri(Map<String, List<String>> comments) {
    final picture = _firstVorbisComment(comments, 'METADATA_BLOCK_PICTURE');
    if (picture != null && picture.isNotEmpty) {
      try {
        final artworkUri = _flacPictureArtworkUri(base64.decode(picture));
        if (artworkUri != null) {
          return artworkUri;
        }
      } on FormatException {
        // Try the older COVERART form below.
      }
    }

    final coverArt = _firstVorbisComment(comments, 'COVERART');
    if (coverArt == null || coverArt.isEmpty) {
      return null;
    }
    try {
      final bytes = base64.decode(coverArt);
      return _artworkDataUri(
        bytes,
        mimeType: _firstVorbisComment(comments, 'COVERARTMIME') ??
            _inferArtworkMimeType(bytes),
      );
    } on FormatException {
      return null;
    }
  }

  List<List<int>> _oggPackets(List<int> bytes) {
    final packets = <List<int>>[];
    final packet = <int>[];
    var offset = 0;
    var pageCount = 0;
    var isContinuingPacket = false;

    while (offset + 27 <= bytes.length && pageCount < _maxOggPages) {
      if (!_matchesAscii(bytes.sublist(offset, offset + 4), 'OggS') ||
          bytes[offset + 4] != 0) {
        return const <List<int>>[];
      }
      pageCount += 1;
      final segmentCount = bytes[offset + 26];
      final segmentTableStart = offset + 27;
      final bodyStart = segmentTableStart + segmentCount;
      if (bodyStart > bytes.length) {
        return const <List<int>>[];
      }

      var bodyLength = 0;
      for (var index = 0; index < segmentCount; index += 1) {
        bodyLength += bytes[segmentTableStart + index];
      }
      final bodyEnd = bodyStart + bodyLength;
      if (bodyEnd > bytes.length) {
        return const <List<int>>[];
      }

      final pageContinuesPacket = (bytes[offset + 5] & 0x01) != 0;
      if (pageContinuesPacket != isContinuingPacket) {
        return const <List<int>>[];
      }

      var bodyOffset = bodyStart;
      for (var index = 0; index < segmentCount; index += 1) {
        final segmentLength = bytes[segmentTableStart + index];
        packet.addAll(bytes.sublist(bodyOffset, bodyOffset + segmentLength));
        bodyOffset += segmentLength;
        if (packet.length > _maxOggPacketBytes) {
          return const <List<int>>[];
        }
        if (segmentLength < 255) {
          packets.add(List<int>.unmodifiable(packet));
          packet.clear();
          isContinuingPacket = false;
          if (packets.length >= _maxOggPackets) {
            return packets;
          }
        } else {
          isContinuingPacket = true;
        }
      }

      offset = bodyEnd;
    }

    return packets;
  }

  _LocalFileMetadata? _m4aMetadata(List<int> moovPayload) {
    final udta = _mp4ChildPayload(moovPayload, 'udta');
    if (udta == null) {
      return null;
    }

    final meta = _mp4ChildPayload(udta, 'meta');
    if (meta == null || meta.length <= 4) {
      return null;
    }

    final ilst = _mp4ChildPayload(meta, 'ilst', startOffset: 4);
    if (ilst == null) {
      return null;
    }

    final fields = <String, List<String>>{};
    Uri? artworkUri;
    double? replayGainTrackDb;
    double? replayGainAlbumDb;
    for (final atom in _mp4Atoms(ilst)) {
      if (_matchesAscii(atom.typeBytes, 'covr') && artworkUri == null) {
        artworkUri = _m4aDataAtomArtworkUri(
          ilst,
          atom.payloadOffset,
          atom.payloadEnd,
        );
        continue;
      }

      if (_matchesAscii(atom.typeBytes, '----') && replayGainTrackDb == null) {
        replayGainTrackDb = _m4aFreeformReplayGain(
          ilst,
          atom.payloadOffset,
          atom.payloadEnd,
          'REPLAYGAIN_TRACK_GAIN',
        );
        replayGainAlbumDb ??= _m4aFreeformReplayGain(
          ilst,
          atom.payloadOffset,
          atom.payloadEnd,
          'REPLAYGAIN_ALBUM_GAIN',
        );
        continue;
      }

      if (_matchesAscii(atom.typeBytes, '----') && replayGainAlbumDb == null) {
        replayGainAlbumDb = _m4aFreeformReplayGain(
          ilst,
          atom.payloadOffset,
          atom.payloadEnd,
          'REPLAYGAIN_ALBUM_GAIN',
        );
        continue;
      }

      final key = _m4aFieldKey(atom.typeBytes);
      if (key == null) {
        continue;
      }

      final value = key == 'lyrics'
          ? _m4aDataAtomRawText(
              ilst,
              atom.payloadOffset,
              atom.payloadEnd,
            )
          : _m4aDataAtomText(
              ilst,
              atom.payloadOffset,
              atom.payloadEnd,
            );
      if (value == null || value.isEmpty) {
        continue;
      }

      fields.putIfAbsent(key, () => <String>[]).add(value);
    }

    final title = _firstVorbisComment(fields, 'title') ?? '';
    final artist = _joinedVorbisComment(fields, 'artist') ?? '';
    final album = _firstVorbisComment(fields, 'album');
    final genre = _joinedVorbisComment(fields, 'genre');
    final embeddedLyrics = _normalizeEmbeddedLyrics(
      _firstVorbisComment(fields, 'lyrics') ?? '',
    );
    if (title.isEmpty &&
        artist.isEmpty &&
        (album == null || album.isEmpty) &&
        (genre == null || genre.isEmpty) &&
        artworkUri == null &&
        replayGainTrackDb == null &&
        replayGainAlbumDb == null &&
        embeddedLyrics == null) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album == null || album.isEmpty ? null : album,
      genre: genre == null || genre.isEmpty ? null : genre,
      artworkUri: artworkUri,
      replayGainTrackDb: replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb,
      embeddedLyrics: embeddedLyrics,
    );
  }

  _LocalFileMetadata? _wavMetadataFromInfoTags(Map<String, String> infoTags) {
    final title = infoTags['title'] ?? '';
    final artist = infoTags['artist'] ?? '';
    final album = infoTags['album'];
    final genre = infoTags['genre'];
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

  bool _wavInfoComplete(Map<String, String> tags) {
    return tags.containsKey('title') &&
        tags.containsKey('artist') &&
        tags.containsKey('album') &&
        tags.containsKey('genre');
  }

  void _readWavInfoList(
    List<int> bytes,
    int start,
    int end,
    Map<String, String> tags,
  ) {
    var offset = start;
    while (offset + 8 <= end) {
      final tagId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final valueLength = _uint32LittleEndian(bytes, offset + 4);
      final valueStart = offset + 8;
      final valueEnd = valueStart + valueLength;
      if (valueLength < 0 || valueEnd > end) {
        break;
      }

      final fieldKey = _wavInfoFieldKey(tagId);
      if (fieldKey != null) {
        final value = _normalizeEmbeddedText(
          latin1.decode(
            bytes.sublist(valueStart, valueEnd),
            allowInvalid: true,
          ),
        );
        if (value.isNotEmpty) {
          tags.putIfAbsent(fieldKey, () => value);
        }
      }

      offset = valueEnd + (valueLength.isOdd ? 1 : 0);
    }
  }

  String? _wavInfoFieldKey(String tagId) {
    return switch (tagId) {
      'INAM' => 'title',
      'IART' => 'artist',
      'IPRD' => 'album',
      'IGNR' => 'genre',
      _ => null,
    };
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

    return _id3v2DecodedText(bytes.sublist(1), bytes.first);
  }

  double? _id3v2ReplayGainUserText(List<int> bytes, String expectedKey) {
    if (bytes.length < 3) {
      return null;
    }

    final encoding = bytes.first;
    final terminatorLength = _id3v2TerminatorLength(encoding);
    var descriptionEnd = 1;
    while (descriptionEnd < bytes.length) {
      if (_hasZeroTerminator(bytes, descriptionEnd, terminatorLength)) {
        break;
      }
      descriptionEnd += 1;
    }
    if (descriptionEnd + terminatorLength >= bytes.length) {
      return null;
    }

    final description = _id3v2DecodedText(
      bytes.sublist(1, descriptionEnd),
      encoding,
    );
    if (description.toUpperCase() != expectedKey) {
      return null;
    }

    return parseReplayGainDb(
      _id3v2DecodedText(
        bytes.sublist(descriptionEnd + terminatorLength),
        encoding,
      ),
    );
  }

  String? _id3v2UnsynchronizedLyrics(List<int> bytes) {
    if (bytes.length < 5 || bytes.length > _maxEmbeddedLyricsBytes) {
      return null;
    }

    final encoding = bytes.first;
    final terminatorLength = _id3v2TerminatorLength(encoding);
    var descriptionEnd = 4; // Encoding plus the three-byte language code.
    while (descriptionEnd < bytes.length) {
      if (_hasZeroTerminator(bytes, descriptionEnd, terminatorLength)) {
        break;
      }
      descriptionEnd += terminatorLength;
    }
    if (descriptionEnd + terminatorLength > bytes.length) {
      return null;
    }

    return _normalizeEmbeddedLyrics(
      _id3v2DecodedRawText(
        bytes.sublist(descriptionEnd + terminatorLength),
        encoding,
      ),
    );
  }

  String _id3v2DecodedText(List<int> payload, int encoding) {
    return _normalizeEmbeddedText(_id3v2DecodedRawText(payload, encoding));
  }

  String _id3v2DecodedRawText(List<int> payload, int encoding) {
    return switch (encoding) {
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
  }

  double? _m4aFreeformReplayGain(
    List<int> bytes,
    int startOffset,
    int endOffset,
    String expectedKey,
  ) {
    String? name;
    for (final atom in _mp4Atoms(bytes.sublist(startOffset, endOffset))) {
      final atomStart = startOffset + atom.payloadOffset;
      final atomEnd = startOffset + atom.payloadEnd;
      if (_matchesAscii(atom.typeBytes, 'name')) {
        name = _m4aFreeformHeaderText(bytes.sublist(atomStart, atomEnd));
      }
    }

    if (name?.toUpperCase() != expectedKey) {
      return null;
    }
    return parseReplayGainDb(
      _m4aDataAtomText(bytes, startOffset, endOffset),
    );
  }

  String? _m4aFreeformHeaderText(List<int> payload) {
    if (payload.length <= 4) {
      return null;
    }
    return _normalizeEmbeddedText(
      utf8.decode(payload.sublist(4), allowMalformed: true),
    );
  }

  Uri? _id3v23PictureArtworkUri(List<int> bytes) {
    if (bytes.length < 4) {
      return null;
    }

    final encoding = bytes[0];
    final mimeEnd = bytes.indexOf(0, 1);
    if (mimeEnd <= 1 || mimeEnd + 2 >= bytes.length) {
      return null;
    }

    final mimeType = _normalizeArtworkMimeType(
      latin1.decode(bytes.sublist(1, mimeEnd), allowInvalid: true),
    );
    var imageStart = mimeEnd + 2;
    final descriptionTerminator = _id3v2TerminatorLength(encoding);
    while (imageStart < bytes.length) {
      if (_hasZeroTerminator(bytes, imageStart, descriptionTerminator)) {
        imageStart += descriptionTerminator;
        break;
      }
      imageStart += descriptionTerminator;
    }

    if (imageStart >= bytes.length) {
      return null;
    }

    final imageBytes = bytes.sublist(imageStart);
    return _artworkDataUri(
      imageBytes,
      mimeType: mimeType ?? _inferArtworkMimeType(imageBytes),
    );
  }

  Uri? _id3v22PictureArtworkUri(List<int> bytes) {
    if (bytes.length < 6) {
      return null;
    }

    final encoding = bytes[0];
    final imageFormat = latin1.decode(
      bytes.sublist(1, 4),
      allowInvalid: true,
    );
    final mimeType = switch (imageFormat.toUpperCase()) {
      'PNG' => 'image/png',
      'JPG' || 'JPEG' => 'image/jpeg',
      _ => null,
    };
    var imageStart = 5;
    final descriptionTerminator = _id3v2TerminatorLength(encoding);
    while (imageStart < bytes.length) {
      if (_hasZeroTerminator(bytes, imageStart, descriptionTerminator)) {
        imageStart += descriptionTerminator;
        break;
      }
      imageStart += descriptionTerminator;
    }

    if (imageStart >= bytes.length) {
      return null;
    }

    final imageBytes = bytes.sublist(imageStart);
    return _artworkDataUri(
      imageBytes,
      mimeType: mimeType ?? _inferArtworkMimeType(imageBytes),
    );
  }

  Uri? _flacPictureArtworkUri(List<int> bytes) {
    var offset = 0;
    if (offset + 8 > bytes.length) {
      return null;
    }

    offset += 4; // Picture type.
    final mimeLength = _uint32(bytes, offset);
    offset += 4;
    if (mimeLength < 0 || offset + mimeLength > bytes.length) {
      return null;
    }

    final mimeType = _normalizeArtworkMimeType(
      latin1.decode(bytes.sublist(offset, offset + mimeLength)),
    );
    offset += mimeLength;
    if (offset + 4 > bytes.length) {
      return null;
    }

    final descriptionLength = _uint32(bytes, offset);
    offset += 4;
    if (descriptionLength < 0 || offset + descriptionLength > bytes.length) {
      return null;
    }

    offset += descriptionLength;
    if (offset + 20 > bytes.length) {
      return null;
    }

    offset += 16; // Width, height, color depth, and indexed colors.
    final dataLength = _uint32(bytes, offset);
    offset += 4;
    if (dataLength <= 0 || offset + dataLength > bytes.length) {
      return null;
    }

    final imageBytes = bytes.sublist(offset, offset + dataLength);
    return _artworkDataUri(
      imageBytes,
      mimeType: mimeType ?? _inferArtworkMimeType(imageBytes),
    );
  }

  Uri? _m4aDataAtomArtworkUri(
    List<int> bytes,
    int startOffset,
    int endOffset,
  ) {
    for (final atom in _mp4Atoms(bytes.sublist(startOffset, endOffset))) {
      if (!_matchesAscii(atom.typeBytes, 'data')) {
        continue;
      }

      final payload = bytes.sublist(
        startOffset + atom.payloadOffset,
        startOffset + atom.payloadEnd,
      );
      if (payload.length <= 8) {
        return null;
      }

      final dataType = _uint32(payload, 0) & 0xffffff;
      final mimeType = switch (dataType) {
        13 => 'image/jpeg',
        14 => 'image/png',
        _ => _inferArtworkMimeType(payload.sublist(8)),
      };

      return _artworkDataUri(payload.sublist(8), mimeType: mimeType);
    }

    return null;
  }

  int _id3v2TerminatorLength(int encoding) {
    return encoding == 1 || encoding == 2 ? 2 : 1;
  }

  bool _hasZeroTerminator(List<int> bytes, int offset, int length) {
    if (offset + length > bytes.length) {
      return false;
    }

    for (var index = 0; index < length; index += 1) {
      if (bytes[offset + index] != 0) {
        return false;
      }
    }

    return true;
  }

  Uri? _artworkDataUri(List<int> bytes, {String? mimeType}) {
    if (bytes.isEmpty || bytes.length > _maxEmbeddedArtworkBytes) {
      return null;
    }

    final normalizedMimeType =
        _normalizeArtworkMimeType(mimeType) ?? _inferArtworkMimeType(bytes);
    if (normalizedMimeType == null) {
      return null;
    }

    return Uri.parse(
      'data:$normalizedMimeType;base64,${base64Encode(bytes)}',
    );
  }

  String? _inferArtworkMimeType(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }

    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }

    return null;
  }

  String? _normalizeArtworkMimeType(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'image/jpeg' || 'image/jpg' || 'jpg' || 'jpeg' => 'image/jpeg',
      'image/png' || 'png' => 'image/png',
      _ => null,
    };
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

  String? _normalizeEmbeddedLyrics(String value) {
    if (value.length > _maxEmbeddedLyricsBytes) {
      return null;
    }
    final normalized = value
        .replaceAll('﻿', '')
        .replaceAll('\u0000', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    return normalized.isEmpty ? null : normalized;
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

  bool _matchesAscii(List<int> bytes, String value) {
    if (bytes.length != value.length) {
      return false;
    }

    for (var index = 0; index < value.length; index += 1) {
      if (bytes[index] != value.codeUnitAt(index)) {
        return false;
      }
    }

    return true;
  }

  bool _startsWithAscii(List<int> bytes, String value) {
    if (bytes.length < value.length) {
      return false;
    }

    for (var index = 0; index < value.length; index += 1) {
      if (bytes[index] != value.codeUnitAt(index)) {
        return false;
      }
    }

    return true;
  }

  String? _firstVorbisComment(
    Map<String, List<String>> comments,
    String key,
  ) {
    final values = comments[key];
    if (values == null || values.isEmpty) {
      return null;
    }

    return values.first;
  }

  String? _joinedVorbisComment(
    Map<String, List<String>> comments,
    String key,
  ) {
    final values = comments[key];
    if (values == null || values.isEmpty) {
      return null;
    }

    return values.join(' / ');
  }

  List<_Mp4Atom> _mp4Atoms(List<int> bytes, {int startOffset = 0}) {
    final atoms = <_Mp4Atom>[];
    var offset = startOffset;
    while (offset + 8 <= bytes.length && atoms.length < _maxMp4ChildAtoms) {
      var atomSize = _uint32(bytes, offset);
      var headerSize = 8;
      if (atomSize == 1) {
        if (offset + 16 > bytes.length) {
          break;
        }
        atomSize = _uint64(bytes, offset + 8);
        headerSize = 16;
      } else if (atomSize == 0) {
        atomSize = bytes.length - offset;
      }

      if (atomSize < headerSize || offset + atomSize > bytes.length) {
        break;
      }

      atoms.add(
        _Mp4Atom(
          typeBytes: bytes.sublist(offset + 4, offset + 8),
          payloadOffset: offset + headerSize,
          payloadEnd: offset + atomSize,
        ),
      );

      offset += atomSize;
    }

    return atoms;
  }

  List<int>? _mp4ChildPayload(
    List<int> bytes,
    String type, {
    int startOffset = 0,
  }) {
    for (final atom in _mp4Atoms(bytes, startOffset: startOffset)) {
      if (_matchesAscii(atom.typeBytes, type)) {
        return bytes.sublist(atom.payloadOffset, atom.payloadEnd);
      }
    }

    return null;
  }

  String? _m4aDataAtomText(
    List<int> bytes,
    int startOffset,
    int endOffset,
  ) {
    for (final atom in _mp4Atoms(bytes.sublist(startOffset, endOffset))) {
      if (!_matchesAscii(atom.typeBytes, 'data')) {
        continue;
      }

      final payload = bytes.sublist(
        startOffset + atom.payloadOffset,
        startOffset + atom.payloadEnd,
      );
      if (payload.length <= 8) {
        return null;
      }

      final dataType = _uint32(payload, 0);
      if (dataType != 0 && dataType != 1) {
        return null;
      }

      return _normalizeEmbeddedText(
        utf8.decode(payload.sublist(8), allowMalformed: true),
      );
    }

    return null;
  }

  String? _m4aDataAtomRawText(
    List<int> bytes,
    int startOffset,
    int endOffset,
  ) {
    for (final atom in _mp4Atoms(bytes.sublist(startOffset, endOffset))) {
      if (!_matchesAscii(atom.typeBytes, 'data')) {
        continue;
      }

      final payload = bytes.sublist(
        startOffset + atom.payloadOffset,
        startOffset + atom.payloadEnd,
      );
      if (payload.length <= 8 || payload.length - 8 > _maxEmbeddedLyricsBytes) {
        return null;
      }
      final dataType = _uint32(payload, 0);
      if (dataType != 0 && dataType != 1) {
        return null;
      }
      return utf8.decode(payload.sublist(8), allowMalformed: true);
    }

    return null;
  }

  String? _m4aFieldKey(List<int> typeBytes) {
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x6e, 0x61, 0x6d])) {
      return 'title';
    }
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x41, 0x52, 0x54]) ||
        _matchesAscii(typeBytes, 'aART')) {
      return 'artist';
    }
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x61, 0x6c, 0x62])) {
      return 'album';
    }
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x67, 0x65, 0x6e])) {
      return 'genre';
    }
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x6c, 0x79, 0x72])) {
      return 'lyrics';
    }

    return null;
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

  int _uint64(List<int> bytes, int offset) {
    if (offset + 8 > bytes.length) {
      return 0;
    }

    return (bytes[offset] << 56) |
        (bytes[offset + 1] << 48) |
        (bytes[offset + 2] << 40) |
        (bytes[offset + 3] << 32) |
        (bytes[offset + 4] << 24) |
        (bytes[offset + 5] << 16) |
        (bytes[offset + 6] << 8) |
        bytes[offset + 7];
  }

  int _uint32LittleEndian(List<int> bytes, int offset) {
    if (offset + 4 > bytes.length) {
      return -1;
    }

    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  int _uint24(List<int> bytes, int offset) {
    if (offset + 3 > bytes.length) {
      return 0;
    }

    return (bytes[offset] << 16) |
        (bytes[offset + 1] << 8) |
        bytes[offset + 2];
  }

  bool _matchesBytes(List<int> bytes, List<int> expected) {
    if (bytes.length != expected.length) {
      return false;
    }

    for (var index = 0; index < expected.length; index += 1) {
      if (bytes[index] != expected[index]) {
        return false;
      }
    }

    return true;
  }

  bool _startsWithBytes(List<int> bytes, List<int> expected) {
    if (bytes.length < expected.length) {
      return false;
    }

    for (var index = 0; index < expected.length; index += 1) {
      if (bytes[index] != expected[index]) {
        return false;
      }
    }

    return true;
  }
}

String localFileContentHash(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash = (hash ^ (byte & 0xff)).toUnsigned(64);
    hash = (hash * 0x100000001b3).toUnsigned(64);
  }

  return 'fnv64-${hash.toRadixString(16).padLeft(16, '0')}';
}

final class _Mp4Atom {
  const _Mp4Atom({
    required this.typeBytes,
    required this.payloadOffset,
    required this.payloadEnd,
  });

  final List<int> typeBytes;
  final int payloadOffset;
  final int payloadEnd;
}

final class _Id3v2TagData {
  const _Id3v2TagData({
    required this.textFrames,
    this.artworkUri,
    this.replayGainTrackDb,
    this.replayGainAlbumDb,
    this.embeddedLyrics,
  });

  final Map<String, String> textFrames;
  final Uri? artworkUri;
  final double? replayGainTrackDb;
  final double? replayGainAlbumDb;
  final String? embeddedLyrics;
}

const _maxId3v2TagBytes = 1024 * 1024;
const _maxFlacMetadataBytes = 1024 * 1024;
const _maxOggMetadataBytes = 1024 * 1024;
const _maxM4aMetadataBytes = 1024 * 1024;
const _maxWavInfoBytes = 1024 * 1024;
const _maxEmbeddedArtworkBytes = 512 * 1024;
const _maxEmbeddedLyricsBytes = 256 * 1024;
const _maxMp4TopLevelAtoms = 512;
const _maxMp4ChildAtoms = 1024;
const _maxWavChunks = 2048;
const _maxOggPages = 128;
const _maxOggPackets = 8;
const _maxOggPacketBytes = 512 * 1024;
const _maxVorbisComments = 2048;
const _flacVorbisCommentBlockType = 4;
const _flacPictureBlockType = 6;
const _sidecarLyricsExtensionsByPreference = <String>[
  '.ttml',
  '.srt',
  '.lrc',
  '.txt',
];
