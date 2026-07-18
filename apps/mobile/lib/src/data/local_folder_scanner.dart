import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/lyrics_document.dart';
import '../domain/replay_gain.dart';
import '../domain/track.dart';
import '../domain/track_chapter.dart';
import '../domain/track_lyrics.dart';

const supportedLocalAudioExtensions = <String>{
  '.aac',
  '.aiff',
  '.alac',
  '.flac',
  '.m4a',
  '.m4b',
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
    this.sidecarChaptersByTrackId = const <String, List<TrackChapter>>{},
  });

  final List<Track> tracks;
  final int ignoredFileCount;
  final int inaccessibleDirectoryCount;
  final Map<String, String> sidecarLyricsByTrackId;
  final Map<String, String> embeddedLyricsByTrackId;
  final Map<String, List<TrackChapter>> sidecarChaptersByTrackId;

  int get sidecarLyricsCount => sidecarLyricsByTrackId.length;
  int get embeddedLyricsCount => embeddedLyricsByTrackId.length;
  int get sidecarChaptersCount => sidecarChaptersByTrackId.length;
}

final class _LocalFileMetadata {
  const _LocalFileMetadata({
    required this.title,
    required this.artist,
    this.album,
    this.albumArtist,
    this.year,
    this.trackNumber,
    this.genre,
    this.artworkUri,
    this.replayGainTrackDb,
    this.replayGainAlbumDb,
    this.embeddedLyrics,
    this.rating,
    this.chapters,
  });

  final String title;
  final String artist;
  final String? album;
  final String? albumArtist;
  final int? year;
  final int? trackNumber;
  final String? genre;
  final Uri? artworkUri;
  final double? replayGainTrackDb;
  final double? replayGainAlbumDb;
  final String? embeddedLyrics;
  final int? rating;
  final List<TrackChapter>? chapters;
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
      sidecarChaptersByTrackId: Map.unmodifiable(
        scanState.sidecarChaptersByTrackId,
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
  final Map<String, List<TrackChapter>> sidecarChaptersByTrackId =
      <String, List<TrackChapter>>{};
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

    final cuePaths = <String>[];
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
        if (p.extension(entry.path).toLowerCase() == '.cue') {
          cuePaths.add(entry.path);
          continue;
        }
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

    for (final cuePath in cuePaths) {
      final chaptersByTrackId = await _sidecarChaptersForCue(cuePath);
      for (final entry in chaptersByTrackId.entries) {
        sidecarChaptersByTrackId.putIfAbsent(entry.key, () => entry.value);
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
        albumArtist: metadata.albumArtist,
        year: metadata.year,
        trackNumber: metadata.trackNumber,
        genre: metadata.genre ?? 'Unknown Genre',
        artworkUri: metadata.artworkUri,
        localPath: path,
        contentHash: contentHash,
        replayGainTrackDb: metadata.replayGainTrackDb,
        replayGainAlbumDb: metadata.replayGainAlbumDb,
        rating: metadata.rating ?? 0,
        chapters: metadata.chapters,
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
      albumArtist: embeddedMetadata.albumArtist,
      year: embeddedMetadata.year,
      trackNumber: embeddedMetadata.trackNumber,
      genre: embeddedMetadata.genre ?? fallbackMetadata.genre,
      artworkUri: embeddedMetadata.artworkUri ?? fallbackMetadata.artworkUri,
      replayGainTrackDb: embeddedMetadata.replayGainTrackDb,
      replayGainAlbumDb: embeddedMetadata.replayGainAlbumDb,
      embeddedLyrics: embeddedMetadata.embeddedLyrics,
      rating: embeddedMetadata.rating,
      chapters: embeddedMetadata.chapters,
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
      case '.aac':
        return _mp3MetadataForFile(path);
      case '.flac':
        return _flacMetadataForFile(path);
      case '.ogg':
      case '.oga':
      case '.opus':
        return _oggMetadataForFile(path);
      case '.m4a':
      case '.m4b':
      case '.alac':
        return _m4aMetadataForFile(path);
      case '.wav':
        return _wavMetadataForFile(path);
      case '.aiff':
        return _aiffMetadataForFile(path);
      case '.wma':
        return _wmaMetadataForFile(path);
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

        final apev2 = await _apev2Metadata(access, length);
        if (apev2 != null) {
          return apev2;
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

  Future<_LocalFileMetadata?> _apev2Metadata(
    RandomAccessFile access,
    int length,
  ) async {
    if (length < _apev2FooterBytes) {
      return null;
    }

    final footerOffsets = <int>[length - _apev2FooterBytes];
    if (length >= _apev2FooterBytes + 128) {
      await access.setPosition(length - 128);
      final id3v1 = await access.read(3);
      if (_matchesAscii(id3v1, 'TAG')) {
        footerOffsets.add(length - 128 - _apev2FooterBytes);
      }
    }

    for (final footerOffset in footerOffsets) {
      if (footerOffset < 0) {
        continue;
      }
      await access.setPosition(footerOffset);
      final footer = await access.read(_apev2FooterBytes);
      if (footer.length != _apev2FooterBytes ||
          !_matchesAscii(footer.sublist(0, 8), 'APETAGEX') ||
          _uint32LittleEndian(footer, 8) != 2000) {
        continue;
      }

      final tagSize = _uint32LittleEndian(footer, 12);
      final itemCount = _uint32LittleEndian(footer, 16);
      final bodyLength = tagSize - _apev2FooterBytes;
      final bodyOffset = footerOffset - bodyLength;
      if (tagSize < _apev2FooterBytes ||
          tagSize > _maxApev2TagBytes ||
          itemCount < 0 ||
          itemCount > _maxApev2Items ||
          bodyOffset < 0 ||
          bodyLength < 0) {
        continue;
      }

      await access.setPosition(bodyOffset);
      final body = await access.read(bodyLength);
      if (body.length != bodyLength) {
        continue;
      }
      final comments = _apev2TextComments(body, itemCount);
      if (comments == null) {
        continue;
      }
      final metadata = _vorbisCommentMetadataFromComments(comments.fields);
      final lyrics = _vorbisCommentLyrics(comments.fields);
      if (metadata == null && lyrics == null && comments.artworkUri == null) {
        continue;
      }
      return _LocalFileMetadata(
        title: metadata?.title ?? '',
        artist: metadata?.artist ?? '',
        album: metadata?.album,
        albumArtist: metadata?.albumArtist,
        year: metadata?.year,
        trackNumber: metadata?.trackNumber,
        genre: metadata?.genre,
        replayGainTrackDb: metadata?.replayGainTrackDb,
        replayGainAlbumDb: metadata?.replayGainAlbumDb,
        embeddedLyrics: lyrics,
        rating: metadata?.rating,
        artworkUri: comments.artworkUri,
      );
    }

    return null;
  }

  Future<Map<String, List<TrackChapter>>> _sidecarChaptersForCue(
    String path,
  ) async {
    try {
      final cueFile = File(path);
      if (await cueFile.length() > _maxCueSheetBytes) {
        return const <String, List<TrackChapter>>{};
      }
      final bytes = await cueFile.readAsBytes();
      if (bytes.length > _maxCueSheetBytes) {
        return const <String, List<TrackChapter>>{};
      }

      final chaptersByFile = _parseCueSheet(
        utf8.decode(bytes, allowMalformed: true),
      );
      if (chaptersByFile.isEmpty) {
        return const <String, List<TrackChapter>>{};
      }

      final tracksByPath = <String, Track>{
        for (final track in tracks)
          if (track.localPath != null)
            p.normalize(p.absolute(track.localPath!)).toLowerCase(): track,
      };
      final root = p.normalize(p.absolute(rootPath));
      final result = <String, List<TrackChapter>>{};
      for (final entry in chaptersByFile.entries) {
        final referencedPath = p.normalize(
          p.absolute(p.join(p.dirname(path), entry.key)),
        );
        if (referencedPath != root && !p.isWithin(root, referencedPath)) {
          continue;
        }
        final track = tracksByPath[referencedPath.toLowerCase()];
        if (track == null) {
          continue;
        }
        final chapters = TrackChapter.normalize(
          entry.value,
          maximum: track.duration,
        );
        if (chapters.isNotEmpty) {
          result[track.id] = chapters;
        }
      }
      return result;
    } on FileSystemException {
      return const <String, List<TrackChapter>>{};
    }
  }

  _Apev2Comments? _apev2TextComments(
    List<int> bytes,
    int itemCount,
  ) {
    var offset = 0;
    final comments = <String, List<String>>{};
    Uri? artworkUri;
    for (var itemIndex = 0; itemIndex < itemCount; itemIndex += 1) {
      if (offset + 8 > bytes.length) {
        return null;
      }
      final valueLength = _uint32LittleEndian(bytes, offset);
      final flags = _uint32LittleEndian(bytes, offset + 4);
      offset += 8;
      final keyEnd = bytes.indexOf(0, offset);
      if (keyEnd == -1 || keyEnd == offset || keyEnd - offset > _maxApev2KeyBytes) {
        return null;
      }
      final key = String.fromCharCodes(bytes.sublist(offset, keyEnd)).toUpperCase();
      offset = keyEnd + 1;
      if (valueLength < 0 || valueLength > bytes.length - offset) {
        return null;
      }
      final valueBytes = bytes.sublist(offset, offset + valueLength);
      offset += valueLength;
      final itemType = flags & _apev2ItemTypeMask;
      if (itemType != _apev2TextItemType) {
        if (key == 'COVER ART (FRONT)' &&
            itemType == _apev2BinaryItemType &&
            artworkUri == null) {
          artworkUri = _apev2PictureArtworkUri(valueBytes);
        }
        continue;
      }

      final normalizedKey = switch (key) {
        'TRACK' => 'TRACKNUMBER',
        'ALBUM ARTIST' => 'ALBUMARTIST',
        _ => key,
      };
      final rawValue = utf8.decode(valueBytes, allowMalformed: true);
      final value = _isVorbisLyricsKey(normalizedKey)
          ? _normalizeEmbeddedLyrics(rawValue)
          : _normalizeEmbeddedText(rawValue);
      if (value == null || value.isEmpty) {
        continue;
      }
      comments.putIfAbsent(normalizedKey, () => <String>[]).add(value);
    }
    return _Apev2Comments(fields: comments, artworkUri: artworkUri);
  }

  Uri? _apev2PictureArtworkUri(List<int> bytes) {
    final filenameEnd = bytes.indexOf(0);
    if (filenameEnd < 0 || filenameEnd + 1 >= bytes.length) {
      return null;
    }

    final imageBytes = bytes.sublist(filenameEnd + 1);
    return _artworkDataUri(imageBytes);
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
        var hasFrontCover = false;
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
              final picture = _flacPictureArtwork(blockBytes);
              if (picture != null &&
                  (artworkUri == null ||
                      (!hasFrontCover && picture.isFrontCover))) {
                artworkUri = picture.artworkUri;
                hasFrontCover = picture.isFrontCover;
              }
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
          albumArtist: metadata?.albumArtist,
          year: metadata?.year,
          trackNumber: metadata?.trackNumber,
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
          albumArtist: metadata?.albumArtist,
          year: metadata?.year,
          trackNumber: metadata?.trackNumber,
          genre: metadata?.genre,
          artworkUri: artworkUri,
          replayGainTrackDb: metadata?.replayGainTrackDb,
          replayGainAlbumDb: metadata?.replayGainAlbumDb,
          embeddedLyrics: embeddedLyrics,
          rating: metadata?.rating,
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
    List<int> header, {
    int? maximumTagBytes,
  }) async {
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
    if (tagSize <= 0 ||
        (maximumTagBytes != null && tagSize > maximumTagBytes)) {
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
        tagData.embeddedLyrics == null &&
        tagData.rating == null) {
      return null;
    }

    final title = tagData.textFrames['title'] ?? '';
    final artist = tagData.textFrames['artist'] ?? '';
    final album = tagData.textFrames['album'];
    final albumArtist = tagData.textFrames['albumArtist'];
    final year = _releaseYearFromText(tagData.textFrames['year']);
    final trackNumber = _trackNumberFromText(tagData.textFrames['trackNumber']);
    final genre = tagData.textFrames['genre'];
    if (title.isEmpty &&
        artist.isEmpty &&
        (album == null || album.isEmpty) &&
        (albumArtist == null || albumArtist.isEmpty) &&
        year == null &&
        trackNumber == null &&
        (genre == null || genre.isEmpty) &&
        tagData.artworkUri == null &&
        tagData.replayGainTrackDb == null &&
        tagData.replayGainAlbumDb == null &&
        tagData.embeddedLyrics == null &&
        tagData.rating == null) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album == null || album.isEmpty ? null : album,
      albumArtist: albumArtist == null || albumArtist.isEmpty
          ? null
          : albumArtist,
      year: year,
      trackNumber: trackNumber,
      genre: genre == null || genre.isEmpty ? null : genre,
      artworkUri: tagData.artworkUri,
      replayGainTrackDb: tagData.replayGainTrackDb,
      replayGainAlbumDb: tagData.replayGainAlbumDb,
      embeddedLyrics: tagData.embeddedLyrics,
      rating: tagData.rating,
    );
  }

  _Id3v2TagData _id3v23Or24TagData(
    List<int> bytes,
    int majorVersion,
  ) {
    final textFrames = <String, String>{};
    Uri? artworkUri;
    var hasFrontCover = false;
    double? replayGainTrackDb;
    double? replayGainAlbumDb;
    String? embeddedLyrics;
    int? rating;
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
      } else if (frameId == 'APIC') {
        final picture = _id3v23PictureArtwork(
          bytes.sublist(offset, offset + frameSize),
        );
        if (picture != null &&
            (artworkUri == null ||
                (!hasFrontCover && picture.isFrontCover))) {
          artworkUri = picture.artworkUri;
          hasFrontCover = picture.isFrontCover;
        }
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
      } else if (frameId == 'SYLT' && embeddedLyrics == null) {
        embeddedLyrics = _id3v2SynchronizedLyrics(
          bytes.sublist(offset, offset + frameSize),
        );
      } else if (frameId == 'COMM' && embeddedLyrics == null) {
        embeddedLyrics = _id3v2CommentLyrics(
          bytes.sublist(offset, offset + frameSize),
        );
      } else if (frameId == 'POPM' && rating == null) {
        rating = _id3v2PopularimeterRating(
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
      rating: rating,
    );
  }

  _Id3v2TagData _id3v22TagData(List<int> bytes) {
    final textFrames = <String, String>{};
    Uri? artworkUri;
    var hasFrontCover = false;
    double? replayGainTrackDb;
    double? replayGainAlbumDb;
    String? embeddedLyrics;
    int? rating;
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
      } else if (frameId == 'PIC') {
        final picture = _id3v22PictureArtwork(
          bytes.sublist(offset, offset + frameSize),
        );
        if (picture != null &&
            (artworkUri == null ||
                (!hasFrontCover && picture.isFrontCover))) {
          artworkUri = picture.artworkUri;
          hasFrontCover = picture.isFrontCover;
        }
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
      } else if (frameId == 'SYL' && embeddedLyrics == null) {
        embeddedLyrics = _id3v2SynchronizedLyrics(
          bytes.sublist(offset, offset + frameSize),
        );
      } else if (frameId == 'COM' && embeddedLyrics == null) {
        embeddedLyrics = _id3v2CommentLyrics(
          bytes.sublist(offset, offset + frameSize),
        );
      } else if (frameId == 'POP' && rating == null) {
        rating = _id3v2PopularimeterRating(
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
      rating: rating,
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
      albumArtist: metadata?.albumArtist,
      year: metadata?.year,
      trackNumber: metadata?.trackNumber,
      genre: metadata?.genre,
      replayGainTrackDb: metadata?.replayGainTrackDb,
      replayGainAlbumDb: metadata?.replayGainAlbumDb,
      embeddedLyrics: embeddedLyrics,
      rating: metadata?.rating,
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
    final albumArtist = _joinedVorbisComment(comments, 'ALBUMARTIST') ??
        _joinedVorbisComment(comments, 'ALBUM ARTIST');
    final year = _releaseYearFromText(
      _firstVorbisComment(comments, 'DATE') ??
          _firstVorbisComment(comments, 'YEAR'),
    );
    final trackNumber = _trackNumberFromText(
      _firstVorbisComment(comments, 'TRACKNUMBER'),
    );
    final genre = _joinedVorbisComment(comments, 'GENRE');
    final replayGainTrackDb = parseReplayGainDb(
      _firstVorbisComment(comments, 'REPLAYGAIN_TRACK_GAIN'),
    );
    final replayGainAlbumDb = parseReplayGainDb(
      _firstVorbisComment(comments, 'REPLAYGAIN_ALBUM_GAIN'),
    );
    final rating = _vorbisRating(_firstVorbisComment(comments, 'RATING'));
    if (title.isEmpty &&
        artist.isEmpty &&
        (album == null || album.isEmpty) &&
        (albumArtist == null || albumArtist.isEmpty) &&
        year == null &&
        trackNumber == null &&
        (genre == null || genre.isEmpty) &&
        replayGainTrackDb == null &&
        replayGainAlbumDb == null &&
        rating == null) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album == null || album.isEmpty ? null : album,
      albumArtist: albumArtist == null || albumArtist.isEmpty
          ? null
          : albumArtist,
      year: year,
      trackNumber: trackNumber,
      genre: genre == null || genre.isEmpty ? null : genre,
      replayGainTrackDb: replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb,
      rating: rating,
    );
  }

  String? _vorbisCommentLyrics(Map<String, List<String>> comments) {
    return _firstVorbisComment(comments, 'LYRICS') ??
        _firstVorbisComment(comments, 'UNSYNCEDLYRICS');
  }

  Future<_LocalFileMetadata?> _wmaMetadataForFile(String path) async {
    try {
      final file = File(path);
      final fileLength = await file.length();
      if (fileLength < _asfHeaderPrefixBytes) {
        return null;
      }

      final access = await file.open();
      try {
        final prefix = await access.read(_asfHeaderPrefixBytes);
        if (prefix.length != _asfHeaderPrefixBytes ||
            !_matchesBytes(prefix.sublist(0, 16), _asfHeaderObjectGuid)) {
          return null;
        }

        final headerSize = _uint64LittleEndian(prefix, 16);
        final objectCount = _uint32LittleEndian(prefix, 24);
        if (headerSize < _asfHeaderPrefixBytes ||
            headerSize > fileLength ||
            headerSize > _maxAsfHeaderBytes ||
            objectCount > _maxAsfHeaderObjects) {
          return null;
        }

        final payloadLength = headerSize - _asfHeaderPrefixBytes;
        final header = await access.read(payloadLength);
        if (header.length != payloadLength) {
          return null;
        }

        final fields = <String, String>{};
        Uri? artworkUri;
        var hasFrontCover = false;
        String? embeddedLyrics;
        var offset = 0;
        var parsedObjects = 0;
        while (offset + _asfObjectPrefixBytes <= header.length &&
            parsedObjects < objectCount) {
          final objectSize = _uint64LittleEndian(header, offset + 16);
          if (objectSize < _asfObjectPrefixBytes ||
              objectSize > header.length - offset) {
            return null;
          }

          final payloadStart = offset + _asfObjectPrefixBytes;
          final payloadEnd = offset + objectSize;
          final objectGuid = header.sublist(offset, offset + 16);
          final payload = header.sublist(payloadStart, payloadEnd);
          if (_matchesBytes(objectGuid, _asfContentDescriptionObjectGuid)) {
            fields.addAll(_asfContentDescriptionFields(payload));
          } else if (_matchesBytes(
            objectGuid,
            _asfExtendedContentDescriptionObjectGuid,
          )) {
            final extendedDescription =
                _asfExtendedContentDescriptionMetadata(payload);
            fields.addAll(extendedDescription.fields);
            if (extendedDescription.artworkUri != null &&
                (artworkUri == null ||
                    (!hasFrontCover && extendedDescription.hasFrontCover))) {
              artworkUri = extendedDescription.artworkUri;
              hasFrontCover = extendedDescription.hasFrontCover;
            }
            embeddedLyrics ??= extendedDescription.embeddedLyrics;
          }

          offset = payloadEnd;
          parsedObjects += 1;
        }

        return _asfMetadataFromFields(
          fields,
          artworkUri: artworkUri,
          embeddedLyrics: embeddedLyrics,
        );
      } finally {
        await access.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  Map<String, String> _asfContentDescriptionFields(List<int> payload) {
    if (payload.length < 10) {
      return const <String, String>{};
    }

    final lengths = <int>[
      _uint16LittleEndian(payload, 0),
      _uint16LittleEndian(payload, 2),
      _uint16LittleEndian(payload, 4),
      _uint16LittleEndian(payload, 6),
      _uint16LittleEndian(payload, 8),
    ];
    var offset = 10;
    final fields = <String, String>{};
    for (var index = 0; index < lengths.length; index += 1) {
      final length = lengths[index];
      if (offset + length > payload.length) {
        return const <String, String>{};
      }
      if (index == 0 || index == 1) {
        final value = _normalizeEmbeddedText(
          _decodeUtf16(payload.sublist(offset, offset + length)),
        );
        if (value.isNotEmpty) {
          fields[index == 0 ? 'title' : 'artist'] = value;
        }
      }
      offset += length;
    }
    return fields;
  }

  _AsfExtendedContentDescription _asfExtendedContentDescriptionMetadata(
    List<int> payload,
  ) {
    if (payload.length < 2) {
      return const _AsfExtendedContentDescription();
    }

    final count = _uint16LittleEndian(payload, 0);
    if (count > _maxAsfExtendedProperties) {
      return const _AsfExtendedContentDescription();
    }

    var offset = 2;
    final fields = <String, String>{};
    Uri? artworkUri;
    var hasFrontCover = false;
    String? embeddedLyrics;
    for (var index = 0; index < count; index += 1) {
      if (offset + 6 > payload.length) {
        return const _AsfExtendedContentDescription();
      }
      final nameLength = _uint16LittleEndian(payload, offset);
      offset += 2;
      if (offset + nameLength + 4 > payload.length) {
        return const _AsfExtendedContentDescription();
      }
      final name = _normalizeEmbeddedText(
        _decodeUtf16(payload.sublist(offset, offset + nameLength)),
      ).toUpperCase();
      offset += nameLength;
      final valueType = _uint16LittleEndian(payload, offset);
      final valueLength = _uint16LittleEndian(payload, offset + 2);
      offset += 4;
      if (offset + valueLength > payload.length) {
        return const _AsfExtendedContentDescription();
      }
      final valueBytes = payload.sublist(offset, offset + valueLength);
      final key = _asfFieldKey(name);
      final value = key == null
          ? null
          : _asfPropertyValue(valueBytes, valueType);
      if (value != null && value.isNotEmpty) {
        fields[key!] = value;
      }
      if (name == 'WM/PICTURE') {
        final picture = _asfPictureArtwork(valueBytes, valueType);
        if (picture != null &&
            (artworkUri == null ||
                (!hasFrontCover && picture.isFrontCover))) {
          artworkUri = picture.artworkUri;
          hasFrontCover = picture.isFrontCover;
        }
      }
      if (name == 'WM/LYRICS' &&
          valueType == _asfUnicodeValueType &&
          embeddedLyrics == null) {
        embeddedLyrics = _normalizeEmbeddedLyrics(_decodeUtf16(valueBytes));
      }
      offset += valueLength;
    }
    return _AsfExtendedContentDescription(
      fields: fields,
      artworkUri: artworkUri,
      hasFrontCover: hasFrontCover,
      embeddedLyrics: embeddedLyrics,
    );
  }

  String? _asfFieldKey(String name) {
    return switch (name) {
      'TITLE' || 'WM/TITLE' => 'title',
      'AUTHOR' || 'WM/AUTHOR' => 'artist',
      'WM/ALBUMTITLE' => 'album',
      'WM/ALBUMARTIST' => 'albumArtist',
      'WM/YEAR' => 'year',
      'WM/TRACKNUMBER' => 'trackNumber',
      'WM/GENRE' => 'genre',
      'WM/SHAREDUSERRATING' => 'rating',
      _ => null,
    };
  }

  String? _asfPropertyValue(List<int> bytes, int valueType) {
    return switch (valueType) {
      _asfUnicodeValueType => _normalizeEmbeddedText(_decodeUtf16(bytes)),
      _asfDwordValueType when bytes.length == 4 =>
        _uint32LittleEndian(bytes, 0).toString(),
      _asfQwordValueType when bytes.length == 8 =>
        _uint64LittleEndian(bytes, 0).toString(),
      _asfWordValueType when bytes.length == 2 =>
        _uint16LittleEndian(bytes, 0).toString(),
      _ => null,
    };
  }

  _AsfPictureArtwork? _asfPictureArtwork(List<int> bytes, int valueType) {
    if (valueType != _asfByteArrayValueType || bytes.length < 9) {
      return null;
    }

    final pictureType = bytes[0];
    final dataLength = _uint32LittleEndian(bytes, 1);
    if (dataLength <= 0 || dataLength > _maxEmbeddedArtworkBytes) {
      return null;
    }

    var offset = 5; // Picture type byte and a little-endian image length.
    final mimeEnd = _utf16NullTerminatorOffset(bytes, offset);
    if (mimeEnd == null) {
      return null;
    }
    final mimeType = _normalizeArtworkMimeType(
      _decodeUtf16(bytes.sublist(offset, mimeEnd)),
    );

    offset = mimeEnd + 2;
    final descriptionEnd = _utf16NullTerminatorOffset(bytes, offset);
    if (descriptionEnd == null) {
      return null;
    }
    offset = descriptionEnd + 2;
    if (offset + dataLength > bytes.length) {
      return null;
    }

    final imageBytes = bytes.sublist(offset, offset + dataLength);
    final artworkUri = _artworkDataUri(
      imageBytes,
      mimeType: mimeType ?? _inferArtworkMimeType(imageBytes),
    );
    return artworkUri == null
        ? null
        : _AsfPictureArtwork(
            artworkUri: artworkUri,
            isFrontCover: pictureType == _frontCoverPictureType,
          );
  }

  int? _utf16NullTerminatorOffset(List<int> bytes, int offset) {
    for (var index = offset; index + 1 < bytes.length; index += 2) {
      if (bytes[index] == 0 && bytes[index + 1] == 0) {
        return index;
      }
    }
    return null;
  }

  _LocalFileMetadata? _asfMetadataFromFields(
    Map<String, String> fields, {
    Uri? artworkUri,
    String? embeddedLyrics,
  }) {
    final title = fields['title'] ?? '';
    final artist = fields['artist'] ?? '';
    final album = fields['album'];
    final albumArtist = fields['albumArtist'];
    final year = _releaseYearFromText(fields['year']);
    final trackNumber = _trackNumberFromText(fields['trackNumber']);
    final genre = fields['genre'];
    final rating = _vorbisRating(fields['rating']);
    if (title.isEmpty &&
        artist.isEmpty &&
        (album == null || album.isEmpty) &&
        (albumArtist == null || albumArtist.isEmpty) &&
        year == null &&
        trackNumber == null &&
        (genre == null || genre.isEmpty) &&
        rating == null &&
        artworkUri == null &&
        embeddedLyrics == null) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album == null || album.isEmpty ? null : album,
      albumArtist: albumArtist == null || albumArtist.isEmpty
          ? null
          : albumArtist,
      year: year,
      trackNumber: trackNumber,
      genre: genre == null || genre.isEmpty ? null : genre,
      rating: rating,
      artworkUri: artworkUri,
      embeddedLyrics: embeddedLyrics,
    );
  }

  Future<_LocalFileMetadata?> _aiffMetadataForFile(String path) async {
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
            !_matchesAscii(header.sublist(0, 4), 'FORM') ||
            (!_matchesAscii(header.sublist(8, 12), 'AIFF') &&
                !_matchesAscii(header.sublist(8, 12), 'AIFC'))) {
          return null;
        }

        final tags = <String, String>{};
        _LocalFileMetadata? id3Metadata;
        var chunkCount = 0;
        while (chunkCount < _maxAiffChunks) {
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
          final chunkLength = _uint32(chunkHeader, 4);
          final payloadStart = await access.position();
          final payloadEnd = payloadStart + chunkLength;
          if (payloadEnd > length) {
            break;
          }

          final fieldKey = _aiffTextFieldKey(chunkId);
          if (chunkId == 'ID3 ' &&
              chunkLength >= 10 &&
              chunkLength - 10 <= _maxId3v2TagBytes) {
            final id3Header = await access.read(10);
            id3Metadata ??= await _id3v2Metadata(
              access,
              id3Header,
              maximumTagBytes: chunkLength - 10,
            );
            await access.setPosition(payloadEnd);
          } else if (fieldKey != null && chunkLength <= _maxAiffTextBytes) {
            final payload = await access.read(chunkLength);
            if (payload.length != chunkLength) {
              break;
            }
            final value = _normalizeEmbeddedText(
              latin1.decode(payload, allowInvalid: true),
            );
            if (value.isNotEmpty) {
              tags.putIfAbsent(fieldKey, () => value);
            }
          } else {
            await access.setPosition(payloadEnd);
          }

          final nextOffset = payloadEnd + (chunkLength.isOdd ? 1 : 0);
          await access.setPosition(nextOffset > length ? length : nextOffset);
        }

        final title = id3Metadata?.title.isNotEmpty == true
            ? id3Metadata!.title
            : tags['title'] ?? '';
        final artist = id3Metadata?.artist.isNotEmpty == true
            ? id3Metadata!.artist
            : tags['artist'] ?? '';
        if (id3Metadata == null && title.isEmpty && artist.isEmpty) {
          return null;
        }
        return _LocalFileMetadata(
          title: title,
          artist: artist,
          album: id3Metadata?.album,
          albumArtist: id3Metadata?.albumArtist,
          year: id3Metadata?.year,
          trackNumber: id3Metadata?.trackNumber,
          genre: id3Metadata?.genre,
          artworkUri: id3Metadata?.artworkUri,
          replayGainTrackDb: id3Metadata?.replayGainTrackDb,
          replayGainAlbumDb: id3Metadata?.replayGainAlbumDb,
          embeddedLyrics: id3Metadata?.embeddedLyrics,
          rating: id3Metadata?.rating,
        );
      } finally {
        await access.close();
      }
    } on FileSystemException {
      return null;
    }
  }

  int? _vorbisRating(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite || parsed < 0 || parsed > 100) {
      return null;
    }

    final normalized = parsed <= 5 ? parsed : parsed / 20;
    return normalized.round().clamp(0, 5).toInt();
  }

  bool _isVorbisLyricsKey(String key) =>
      key == 'LYRICS' || key == 'UNSYNCEDLYRICS';

  Uri? _vorbisCommentArtworkUri(Map<String, List<String>> comments) {
    Uri? artworkUri;
    var hasFrontCover = false;
    for (final picture in comments['METADATA_BLOCK_PICTURE'] ??
        const <String>[]) {
      if (picture.isEmpty) {
        continue;
      }
      try {
        final decodedPicture = _flacPictureArtwork(base64.decode(picture));
        if (decodedPicture != null &&
            (artworkUri == null ||
                (!hasFrontCover && decodedPicture.isFrontCover))) {
          artworkUri = decodedPicture.artworkUri;
          hasFrontCover = decodedPicture.isFrontCover;
        }
      } on FormatException {
        // Skip malformed values and retain valid picture blocks.
      }
    }
    if (artworkUri != null) {
      return artworkUri;
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

    final chapters = _m4aChapters(udta);
    final meta = _mp4ChildPayload(udta, 'meta');
    final fields = <String, List<String>>{};
    Uri? artworkUri;
    double? replayGainTrackDb;
    double? replayGainAlbumDb;
    int? trackNumber;
    final ilst = meta == null || meta.length <= 4
        ? null
        : _mp4ChildPayload(meta, 'ilst', startOffset: 4);
    final metadataItems = ilst ?? const <int>[];
    for (final atom in _mp4Atoms(metadataItems)) {
      if (_matchesAscii(atom.typeBytes, 'covr') && artworkUri == null) {
        artworkUri = _m4aDataAtomArtworkUri(
          metadataItems,
          atom.payloadOffset,
          atom.payloadEnd,
        );
        continue;
      }

      if (_matchesAscii(atom.typeBytes, '----') && replayGainTrackDb == null) {
        replayGainTrackDb = _m4aFreeformReplayGain(
          metadataItems,
          atom.payloadOffset,
          atom.payloadEnd,
          'REPLAYGAIN_TRACK_GAIN',
        );
        replayGainAlbumDb ??= _m4aFreeformReplayGain(
          metadataItems,
          atom.payloadOffset,
          atom.payloadEnd,
          'REPLAYGAIN_ALBUM_GAIN',
        );
        continue;
      }

      if (_matchesAscii(atom.typeBytes, '----') && replayGainAlbumDb == null) {
        replayGainAlbumDb = _m4aFreeformReplayGain(
          metadataItems,
          atom.payloadOffset,
          atom.payloadEnd,
          'REPLAYGAIN_ALBUM_GAIN',
        );
        continue;
      }

      if (_matchesAscii(atom.typeBytes, 'trkn') && trackNumber == null) {
        trackNumber = _m4aDataAtomTrackNumber(
          metadataItems,
          atom.payloadOffset,
          atom.payloadEnd,
        );
        continue;
      }

      final key = _m4aFieldKey(atom.typeBytes);
      if (key == null) {
        continue;
      }

      final value = key == 'lyrics'
          ? _m4aDataAtomRawText(
              metadataItems,
              atom.payloadOffset,
              atom.payloadEnd,
            )
          : _m4aDataAtomText(
              metadataItems,
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
    final albumArtist = _joinedVorbisComment(fields, 'albumArtist');
    final year = _releaseYearFromText(_firstVorbisComment(fields, 'date'));
    final genre = _joinedVorbisComment(fields, 'genre');
    final embeddedLyrics = _normalizeEmbeddedLyrics(
      _firstVorbisComment(fields, 'lyrics') ?? '',
    );
    if (title.isEmpty &&
        artist.isEmpty &&
        (album == null || album.isEmpty) &&
        (albumArtist == null || albumArtist.isEmpty) &&
        year == null &&
        trackNumber == null &&
        (genre == null || genre.isEmpty) &&
        artworkUri == null &&
        replayGainTrackDb == null &&
        replayGainAlbumDb == null &&
        embeddedLyrics == null &&
        chapters.isEmpty) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album == null || album.isEmpty ? null : album,
      albumArtist: albumArtist == null || albumArtist.isEmpty
          ? null
          : albumArtist,
      year: year,
      trackNumber: trackNumber,
      genre: genre == null || genre.isEmpty ? null : genre,
      artworkUri: artworkUri,
      replayGainTrackDb: replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb,
      embeddedLyrics: embeddedLyrics,
      chapters: chapters,
    );
  }

  List<TrackChapter> _m4aChapters(List<int> udta) {
    final payload = _mp4ChildPayload(udta, 'chpl');
    if (payload == null || payload.length < 5) {
      return const <TrackChapter>[];
    }

    var offset = 4;
    final version = payload[0];
    if (version != 0) {
      if (offset + 4 >= payload.length) {
        return const <TrackChapter>[];
      }
      offset += 4;
    }
    if (offset >= payload.length) {
      return const <TrackChapter>[];
    }

    final chapterCount = payload[offset];
    offset += 1;
    final chapters = <TrackChapter>[];
    for (var index = 0;
        index < chapterCount && index < _maxMp4Chapters;
        index += 1) {
      if (offset + 9 > payload.length) {
        return const <TrackChapter>[];
      }

      final timestamp = _uint64(payload, offset);
      offset += 8;
      final titleLength = payload[offset];
      offset += 1;
      if (offset + titleLength > payload.length) {
        return const <TrackChapter>[];
      }

      final title = _normalizeEmbeddedText(
        utf8.decode(
          payload.sublist(offset, offset + titleLength),
          allowMalformed: true,
        ),
      );
      offset += titleLength;
      chapters.add(
        TrackChapter(
          start: Duration(microseconds: timestamp ~/ _mp4ChapterTicksPerMicrosecond),
          title: title.isEmpty ? 'Chapter ${index + 1}' : title,
        ),
      );
    }

    return TrackChapter.normalize(chapters);
  }

  _LocalFileMetadata? _wavMetadataFromInfoTags(Map<String, String> infoTags) {
    final title = infoTags['title'] ?? '';
    final artist = infoTags['artist'] ?? '';
    final album = infoTags['album'];
    final year = _releaseYearFromText(infoTags['date']);
    final trackNumber = _trackNumberFromText(infoTags['trackNumber']);
    final genre = infoTags['genre'];
    if (title.isEmpty &&
        artist.isEmpty &&
        (album == null || album.isEmpty) &&
        year == null &&
        trackNumber == null &&
        (genre == null || genre.isEmpty)) {
      return null;
    }

    return _LocalFileMetadata(
      title: title,
      artist: artist,
      album: album == null || album.isEmpty ? null : album,
      year: year,
      trackNumber: trackNumber,
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
      'ICRD' => 'date',
      'ITRK' => 'trackNumber',
      'IGNR' => 'genre',
      _ => null,
    };
  }

  String? _aiffTextFieldKey(String chunkId) {
    return switch (chunkId) {
      'NAME' => 'title',
      'AUTH' => 'artist',
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

  String? _id3v2CommentLyrics(List<int> bytes) {
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

    final description = _id3v2DecodedText(
      bytes.sublist(4, descriptionEnd),
      encoding,
    ).toLowerCase();
    if (description != 'lyrics' && description != 'lyric') {
      return null;
    }
    return _normalizeEmbeddedLyrics(
      _id3v2DecodedRawText(
        bytes.sublist(descriptionEnd + terminatorLength),
        encoding,
      ),
    );
  }

  String? _id3v2SynchronizedLyrics(List<int> bytes) {
    if (bytes.length < 8 || bytes.length > _maxEmbeddedLyricsBytes) {
      return null;
    }

    final encoding = bytes.first;
    // Only millisecond lyric timestamps can be represented faithfully as LRC.
    if (bytes[4] != 2 || bytes[5] != 1) {
      return null;
    }
    final terminatorLength = _id3v2TerminatorLength(encoding);
    var descriptionEnd = 6;
    while (descriptionEnd < bytes.length) {
      if (_hasZeroTerminator(bytes, descriptionEnd, terminatorLength)) {
        break;
      }
      descriptionEnd += terminatorLength;
    }
    if (descriptionEnd + terminatorLength >= bytes.length) {
      return null;
    }

    var offset = descriptionEnd + terminatorLength;
    final lines = <String>[];
    while (offset < bytes.length) {
      var textEnd = offset;
      while (textEnd < bytes.length) {
        if (_hasZeroTerminator(bytes, textEnd, terminatorLength)) {
          break;
        }
        textEnd += terminatorLength;
      }
      if (textEnd + terminatorLength + 4 > bytes.length) {
        break;
      }
      final text = _normalizeEmbeddedText(
        _id3v2DecodedRawText(bytes.sublist(offset, textEnd), encoding),
      );
      offset = textEnd + terminatorLength;
      final timestampMilliseconds = _uint32(bytes, offset);
      offset += 4;
      if (text.isEmpty) {
        continue;
      }
      lines.add(
        '[${formatSyncedLyricTimestamp(Duration(milliseconds: timestampMilliseconds))}]$text',
      );
      if (lines.length > _maxId3v2SyncedLyricEvents) {
        return null;
      }
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  int? _id3v2PopularimeterRating(List<int> bytes) {
    final emailEnd = bytes.indexOf(0);
    if (emailEnd < 0 || emailEnd + 1 >= bytes.length) {
      return null;
    }

    final value = bytes[emailEnd + 1];
    if (value == 0) {
      return 0;
    }
    if (value <= 31) {
      return 1;
    }
    if (value <= 95) {
      return 2;
    }
    if (value <= 159) {
      return 3;
    }
    if (value <= 223) {
      return 4;
    }
    return 5;
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

  _Id3v2PictureArtwork? _id3v23PictureArtwork(List<int> bytes) {
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
    final pictureType = bytes[mimeEnd + 1];
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
    final artworkUri = _artworkDataUri(
      imageBytes,
      mimeType: mimeType ?? _inferArtworkMimeType(imageBytes),
    );
    return artworkUri == null
        ? null
        : _Id3v2PictureArtwork(
            artworkUri: artworkUri,
            isFrontCover: pictureType == _frontCoverPictureType,
          );
  }

  _Id3v2PictureArtwork? _id3v22PictureArtwork(List<int> bytes) {
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
    final pictureType = bytes[4];
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
    final artworkUri = _artworkDataUri(
      imageBytes,
      mimeType: mimeType ?? _inferArtworkMimeType(imageBytes),
    );
    return artworkUri == null
        ? null
        : _Id3v2PictureArtwork(
            artworkUri: artworkUri,
            isFrontCover: pictureType == _frontCoverPictureType,
          );
  }

  _FlacPictureArtwork? _flacPictureArtwork(List<int> bytes) {
    var offset = 0;
    if (offset + 8 > bytes.length) {
      return null;
    }

    final pictureType = _uint32(bytes, offset);
    offset += 4;
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
    final artworkUri = _artworkDataUri(
      imageBytes,
      mimeType: mimeType ?? _inferArtworkMimeType(imageBytes),
    );
    return artworkUri == null
        ? null
        : _FlacPictureArtwork(
            artworkUri: artworkUri,
            isFrontCover: pictureType == _frontCoverPictureType,
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

  int? _releaseYearFromText(String? value) {
    if (value == null) {
      return null;
    }
    final match = RegExp(r'(?:^|\D)([1-9]\d{3})(?:\D|$)').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int? _trackNumberFromText(String? value) {
    if (value == null) {
      return null;
    }
    final match = RegExp(r'^\s*(\d+)').firstMatch(value);
    final trackNumber = match == null ? null : int.tryParse(match.group(1)!);
    return trackNumber == null || trackNumber <= 0 ? null : trackNumber;
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
      case 'TPE2':
      case 'TP2':
        return 'albumArtist';
      case 'TDRC':
      case 'TYER':
      case 'TYE':
        return 'year';
      case 'TRCK':
      case 'TRK':
        return 'trackNumber';
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

  int? _m4aDataAtomTrackNumber(
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
      if (payload.length < 12) {
        return null;
      }

      final trackNumber = (payload[10] << 8) | payload[11];
      return trackNumber > 0 ? trackNumber : null;
    }

    return null;
  }

  String? _m4aFieldKey(List<int> typeBytes) {
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x6e, 0x61, 0x6d])) {
      return 'title';
    }
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x41, 0x52, 0x54])) {
      return 'artist';
    }
    if (_matchesAscii(typeBytes, 'aART')) {
      return 'albumArtist';
    }
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x61, 0x6c, 0x62])) {
      return 'album';
    }
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x67, 0x65, 0x6e])) {
      return 'genre';
    }
    if (_matchesBytes(typeBytes, const <int>[0xa9, 0x64, 0x61, 0x79])) {
      return 'date';
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

  int _uint16LittleEndian(List<int> bytes, int offset) {
    if (offset + 2 > bytes.length) {
      return -1;
    }

    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  int _uint64LittleEndian(List<int> bytes, int offset) {
    if (offset + 8 > bytes.length) {
      return -1;
    }

    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24) |
        (bytes[offset + 4] << 32) |
        (bytes[offset + 5] << 40) |
        (bytes[offset + 6] << 48) |
        (bytes[offset + 7] << 56);
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

final class _AsfExtendedContentDescription {
  const _AsfExtendedContentDescription({
    this.fields = const <String, String>{},
    this.artworkUri,
    this.hasFrontCover = false,
    this.embeddedLyrics,
  });

  final Map<String, String> fields;
  final Uri? artworkUri;
  final bool hasFrontCover;
  final String? embeddedLyrics;
}

final class _AsfPictureArtwork {
  const _AsfPictureArtwork({
    required this.artworkUri,
    required this.isFrontCover,
  });

  final Uri artworkUri;
  final bool isFrontCover;
}

final class _Apev2Comments {
  const _Apev2Comments({required this.fields, this.artworkUri});

  final Map<String, List<String>> fields;
  final Uri? artworkUri;
}

final class _Id3v2PictureArtwork {
  const _Id3v2PictureArtwork({
    required this.artworkUri,
    required this.isFrontCover,
  });

  final Uri artworkUri;
  final bool isFrontCover;
}

final class _FlacPictureArtwork {
  const _FlacPictureArtwork({
    required this.artworkUri,
    required this.isFrontCover,
  });

  final Uri artworkUri;
  final bool isFrontCover;
}

final class _Id3v2TagData {
  const _Id3v2TagData({
    required this.textFrames,
    this.artworkUri,
    this.replayGainTrackDb,
    this.replayGainAlbumDb,
    this.embeddedLyrics,
    this.rating,
  });

  final Map<String, String> textFrames;
  final Uri? artworkUri;
  final double? replayGainTrackDb;
  final double? replayGainAlbumDb;
  final String? embeddedLyrics;
  final int? rating;
}

const _maxId3v2TagBytes = 1024 * 1024;
const _maxApev2TagBytes = 1024 * 1024;
const _maxFlacMetadataBytes = 1024 * 1024;
const _maxOggMetadataBytes = 1024 * 1024;
const _maxM4aMetadataBytes = 1024 * 1024;
const _maxAsfHeaderBytes = 1024 * 1024;
const _maxWavInfoBytes = 1024 * 1024;
const _maxAiffTextBytes = 1024 * 1024;
const _maxEmbeddedArtworkBytes = 512 * 1024;
const _maxEmbeddedLyricsBytes = 256 * 1024;
const _maxCueSheetBytes = 256 * 1024;
const _maxCueSheetChapters = 500;
const _maxMp4Chapters = 255;
const _mp4ChapterTicksPerMicrosecond = 10;
const _maxId3v2SyncedLyricEvents = 4096;
const _maxMp4TopLevelAtoms = 512;
const _maxMp4ChildAtoms = 1024;
const _maxAsfHeaderObjects = 512;
const _maxAsfExtendedProperties = 2048;
const _maxWavChunks = 2048;
const _maxAiffChunks = 2048;
const _maxOggPages = 128;
const _maxOggPackets = 8;
const _maxOggPacketBytes = 512 * 1024;
const _maxVorbisComments = 2048;
const _maxApev2Items = 2048;
const _maxApev2KeyBytes = 255;
const _apev2FooterBytes = 32;
const _apev2ItemTypeMask = 0x6;
const _apev2TextItemType = 0;
const _apev2BinaryItemType = 0x2;
const _flacVorbisCommentBlockType = 4;
const _flacPictureBlockType = 6;
const _asfHeaderPrefixBytes = 30;
const _asfObjectPrefixBytes = 24;
const _asfUnicodeValueType = 0;
const _asfByteArrayValueType = 1;
const _asfDwordValueType = 3;
const _asfQwordValueType = 4;
const _asfWordValueType = 5;
const _frontCoverPictureType = 3;
const _asfHeaderObjectGuid = <int>[
  0x30, 0x26, 0xb2, 0x75, 0x8e, 0x66, 0xcf, 0x11,
  0xa6, 0xd9, 0x00, 0xaa, 0x00, 0x62, 0xce, 0x6c,
];
const _asfContentDescriptionObjectGuid = <int>[
  0x33, 0x26, 0xb2, 0x75, 0x8e, 0x66, 0xcf, 0x11,
  0xa6, 0xd9, 0x00, 0xaa, 0x00, 0x62, 0xce, 0x6c,
];
const _asfExtendedContentDescriptionObjectGuid = <int>[
  0x40, 0xa4, 0xd0, 0xd2, 0x07, 0xe3, 0xd2, 0x11,
  0x97, 0xf0, 0x00, 0xa0, 0xc9, 0x5e, 0xa8, 0x50,
];
const _sidecarLyricsExtensionsByPreference = <String>[
  '.ttml',
  '.srt',
  '.lrc',
  '.txt',
];

Map<String, List<TrackChapter>> _parseCueSheet(String document) {
  final chaptersByFile = <String, List<TrackChapter>>{};
  String? currentFile;
  int? currentTrackNumber;
  String? currentTitle;
  Duration? currentStart;
  var chapterCount = 0;

  void commitCurrentTrack() {
    final file = currentFile;
    final trackNumber = currentTrackNumber;
    final start = currentStart;
    if (file == null || trackNumber == null || start == null) {
      return;
    }
    if (chapterCount >= _maxCueSheetChapters) {
      return;
    }
    final title = currentTitle?.trim();
    chaptersByFile.putIfAbsent(file, () => <TrackChapter>[]).add(
          TrackChapter(
            start: start,
            title: title == null || title.isEmpty
                ? 'Track ${trackNumber.toString().padLeft(2, '0')}'
                : title,
          ),
        );
    chapterCount += 1;
  }

  void resetCurrentTrack() {
    currentTrackNumber = null;
    currentTitle = null;
    currentStart = null;
  }

  for (final rawLine in document.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || chapterCount >= _maxCueSheetChapters) {
      continue;
    }

    final fileMatch = RegExp(r'^FILE\s+(.+)$', caseSensitive: false)
        .firstMatch(line);
    if (fileMatch != null) {
      commitCurrentTrack();
      resetCurrentTrack();
      currentFile = _cueFileName(fileMatch.group(1)!);
      continue;
    }

    final trackMatch = RegExp(
      r'^TRACK\s+(\d+)\s+\S+\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    if (trackMatch != null) {
      commitCurrentTrack();
      resetCurrentTrack();
      currentTrackNumber = int.tryParse(trackMatch.group(1)!);
      continue;
    }

    if (currentTrackNumber == null) {
      continue;
    }

    final titleMatch = RegExp(r'^TITLE\s+(.+)$', caseSensitive: false)
        .firstMatch(line);
    if (titleMatch != null) {
      currentTitle = _cueTextValue(titleMatch.group(1)!);
      continue;
    }

    final indexMatch = RegExp(
      r'^INDEX\s+01\s+(\d{1,3}):([0-5]\d):([0-7]\d)\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    if (indexMatch != null) {
      final minutes = int.parse(indexMatch.group(1)!);
      final seconds = int.parse(indexMatch.group(2)!);
      final frames = int.parse(indexMatch.group(3)!);
      currentStart = Duration(
        milliseconds: minutes * 60000 + seconds * 1000 + frames * 1000 ~/ 75,
      );
    }
  }
  commitCurrentTrack();
  return chaptersByFile;
}

String? _cueFileName(String source) {
  final quoted = RegExp(r'^"([^"]+)"(?:\s+.*)?$').firstMatch(source.trim());
  if (quoted != null) {
    return quoted.group(1)?.trim();
  }
  final parts = source.trim().split(RegExp(r'\s+'));
  final value = parts.isEmpty ? null : parts.first;
  return value == null || value.isEmpty ? null : value;
}

String _cueTextValue(String source) {
  final quoted = RegExp(r'^"([^"]*)"\s*$').firstMatch(source.trim());
  return quoted?.group(1)?.trim() ?? source.trim();
}
