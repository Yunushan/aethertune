import 'dart:convert';

import 'artwork_crop.dart';
import 'replay_gain.dart';
import 'track_chapter.dart';
import 'track_skip_segment.dart';

/// A provider-independent music item.
///
/// A track can be backed by a local file, a resolved stream URL from a legal
/// provider adapter, or metadata only while a provider resolves the stream.
class Track {
  Track({
    required this.id,
    required this.title,
    this.artist = 'Unknown Artist',
    this.album = 'Unknown Album',
    this.albumArtist,
    this.year,
    this.trackNumber,
    this.genre = 'Unknown Genre',
    this.duration = Duration.zero,
    this.artworkUri,
    this.artworkSourceUri,
    this.artworkCrop = ArtworkCrop.centered,
    this.artworkIsUserManaged = false,
    this.artworkUriIsEphemeral = false,
    this.providerArtworkId,
    this.providerArtworkVersion,
    this.localPath,
    this.contentHash,
    this.replayGainTrackDb,
    this.replayGainAlbumDb,
    this.streamUrl,
    this.streamUrlIsEphemeral = false,
    this.sourceId = 'local',
    this.externalId,
    this.isFavorite = false,
    List<TrackChapter>? chapters,
    List<TrackSkipSegment>? skipSegments,
    DateTime? addedAt,
  }) : chapters = TrackChapter.normalize(
         chapters ?? const <TrackChapter>[],
         maximum: duration,
       ),
       skipSegments = TrackSkipSegment.normalize(
         skipSegments ?? const <TrackSkipSegment>[],
         maximum: duration,
       ),
       addedAt = addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String title;
  final String artist;
  final String album;
  final String? albumArtist;
  final int? year;
  final int? trackNumber;
  final String genre;
  final Duration duration;
  final Uri? artworkUri;
  final Uri? artworkSourceUri;
  final ArtworkCrop artworkCrop;
  final bool artworkIsUserManaged;
  final bool artworkUriIsEphemeral;
  final String? providerArtworkId;
  final String? providerArtworkVersion;
  final String? localPath;
  final String? contentHash;
  final double? replayGainTrackDb;
  final double? replayGainAlbumDb;
  final String? streamUrl;
  final bool streamUrlIsEphemeral;
  final String sourceId;
  final String? externalId;
  final bool isFavorite;
  final List<TrackChapter> chapters;
  final List<TrackSkipSegment> skipSegments;
  final DateTime addedAt;

  bool get hasLocalSource => localPath?.trim().isNotEmpty == true;
  bool get hasStreamSource => streamUrl?.trim().isNotEmpty == true;
  bool get isPlayable => hasLocalSource || hasStreamSource;

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    bool clearAlbumArtist = false,
    int? year,
    bool clearYear = false,
    int? trackNumber,
    bool clearTrackNumber = false,
    String? genre,
    Duration? duration,
    Uri? artworkUri,
    bool clearArtworkUri = false,
    Uri? artworkSourceUri,
    bool clearArtworkSourceUri = false,
    ArtworkCrop? artworkCrop,
    bool? artworkIsUserManaged,
    bool? artworkUriIsEphemeral,
    String? providerArtworkId,
    String? providerArtworkVersion,
    String? localPath,
    String? contentHash,
    double? replayGainTrackDb,
    double? replayGainAlbumDb,
    String? streamUrl,
    bool? streamUrlIsEphemeral,
    String? sourceId,
    String? externalId,
    bool? isFavorite,
    List<TrackChapter>? chapters,
    List<TrackSkipSegment>? skipSegments,
    DateTime? addedAt,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      albumArtist: clearAlbumArtist ? null : albumArtist ?? this.albumArtist,
      year: clearYear ? null : year ?? this.year,
      trackNumber: clearTrackNumber ? null : trackNumber ?? this.trackNumber,
      genre: genre ?? this.genre,
      duration: duration ?? this.duration,
      artworkUri: clearArtworkUri ? null : artworkUri ?? this.artworkUri,
      artworkSourceUri: clearArtworkSourceUri
          ? null
          : artworkSourceUri ?? this.artworkSourceUri,
      artworkCrop: artworkCrop ?? this.artworkCrop,
      artworkIsUserManaged: artworkIsUserManaged ?? this.artworkIsUserManaged,
      artworkUriIsEphemeral:
          artworkUriIsEphemeral ?? this.artworkUriIsEphemeral,
      providerArtworkId: providerArtworkId ?? this.providerArtworkId,
      providerArtworkVersion:
          providerArtworkVersion ?? this.providerArtworkVersion,
      localPath: localPath ?? this.localPath,
      contentHash: contentHash ?? this.contentHash,
      replayGainTrackDb: replayGainTrackDb ?? this.replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb ?? this.replayGainAlbumDb,
      streamUrl: streamUrl ?? this.streamUrl,
      streamUrlIsEphemeral: streamUrlIsEphemeral ?? this.streamUrlIsEphemeral,
      sourceId: sourceId ?? this.sourceId,
      externalId: externalId ?? this.externalId,
      isFavorite: isFavorite ?? this.isFavorite,
      chapters: chapters ?? this.chapters,
      skipSegments: skipSegments ?? this.skipSegments,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Track withoutEphemeralMediaUris() {
    if (!streamUrlIsEphemeral && !artworkUriIsEphemeral) {
      return this;
    }
    return Track(
      id: id,
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      year: year,
      trackNumber: trackNumber,
      genre: genre,
      duration: duration,
      artworkUri: artworkUriIsEphemeral ? null : artworkUri,
      artworkSourceUri: artworkSourceUri,
      artworkCrop: artworkCrop,
      artworkIsUserManaged: artworkIsUserManaged,
      providerArtworkId: providerArtworkId,
      providerArtworkVersion: providerArtworkVersion,
      localPath: localPath,
      contentHash: contentHash,
      replayGainTrackDb: replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb,
      streamUrl: streamUrlIsEphemeral ? null : streamUrl,
      sourceId: sourceId,
      externalId: externalId,
      isFavorite: isFavorite,
      chapters: chapters,
      skipSegments: skipSegments,
      addedAt: addedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      if (albumArtist != null) 'albumArtist': albumArtist,
      if (year != null) 'year': year,
      if (trackNumber != null) 'trackNumber': trackNumber,
      'genre': genre,
      'durationMs': duration.inMilliseconds,
      'artworkUri': artworkUriIsEphemeral ? null : artworkUri?.toString(),
      'artworkSourceUri': artworkSourceUri?.toString(),
      if (!artworkCrop.isCentered) 'artworkCrop': artworkCrop.toJson(),
      'artworkIsUserManaged': artworkIsUserManaged,
      'providerArtworkId': providerArtworkId,
      'providerArtworkVersion': providerArtworkVersion,
      'localPath': localPath,
      'contentHash': contentHash,
      if (replayGainTrackDb != null) 'replayGainTrackDb': replayGainTrackDb,
      if (replayGainAlbumDb != null) 'replayGainAlbumDb': replayGainAlbumDb,
      'streamUrl': streamUrlIsEphemeral ? null : streamUrl,
      'sourceId': sourceId,
      'externalId': externalId,
      'isFavorite': isFavorite,
      if (chapters.isNotEmpty)
        'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
      if (skipSegments.isNotEmpty)
        'skipSegments': skipSegments
            .map((segment) => segment.toJson())
            .toList(),
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory Track.fromJson(Map<String, Object?> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? 'Unknown Album',
      albumArtist: json['albumArtist'] as String?,
      year: _positiveJsonInt(json['year']),
      trackNumber: _positiveJsonInt(json['trackNumber']),
      genre: json['genre'] as String? ?? 'Unknown Genre',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      artworkUri: _parseUri(json['artworkUri'] as String?),
      artworkSourceUri: _parseUri(json['artworkSourceUri'] as String?),
      artworkCrop: ArtworkCrop.fromJson(json['artworkCrop']),
      artworkIsUserManaged: json['artworkIsUserManaged'] as bool? ?? false,
      providerArtworkId: json['providerArtworkId'] as String?,
      providerArtworkVersion: json['providerArtworkVersion'] as String?,
      localPath: json['localPath'] as String?,
      contentHash: json['contentHash'] as String?,
      replayGainTrackDb: sanitizeReplayGainDb(
        (json['replayGainTrackDb'] as num?)?.toDouble(),
      ),
      replayGainAlbumDb: sanitizeReplayGainDb(
        (json['replayGainAlbumDb'] as num?)?.toDouble(),
      ),
      streamUrl: json['streamUrl'] as String?,
      sourceId: json['sourceId'] as String? ?? 'local',
      externalId: json['externalId'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      chapters: _parseChapters(json['chapters']),
      skipSegments: _parseSkipSegments(json['skipSegments']),
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static Uri? _parseUri(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return Uri.tryParse(value);
  }

  static List<TrackChapter> _parseChapters(Object? value) {
    if (value is! List) {
      return const <TrackChapter>[];
    }
    return value
        .map(TrackChapter.tryFromJson)
        .whereType<TrackChapter>()
        .toList(growable: false);
  }

  static List<TrackSkipSegment> _parseSkipSegments(Object? value) {
    if (value is! List) {
      return const <TrackSkipSegment>[];
    }
    return value
        .map(TrackSkipSegment.tryFromJson)
        .whereType<TrackSkipSegment>()
        .toList(growable: false);
  }

  static int? _positiveJsonInt(Object? value) {
    final number = value is num ? value.toInt() : null;
    return number == null || number <= 0 ? null : number;
  }

  static String stableLocalId(String path) {
    return base64Url.encode(utf8.encode(path)).replaceAll('=', '');
  }
}
