import 'dart:convert';

import 'replay_gain.dart';
import 'track_chapter.dart';

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
    this.genre = 'Unknown Genre',
    this.duration = Duration.zero,
    this.artworkUri,
    this.artworkSourceUri,
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
    DateTime? addedAt,
  }) : chapters = TrackChapter.normalize(
         chapters ?? const <TrackChapter>[],
         maximum: duration,
       ),
       addedAt = addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final Duration duration;
  final Uri? artworkUri;
  final Uri? artworkSourceUri;
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
  final DateTime addedAt;

  bool get hasLocalSource => localPath?.trim().isNotEmpty == true;
  bool get hasStreamSource => streamUrl?.trim().isNotEmpty == true;
  bool get isPlayable => hasLocalSource || hasStreamSource;

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? genre,
    Duration? duration,
    Uri? artworkUri,
    bool clearArtworkUri = false,
    Uri? artworkSourceUri,
    bool clearArtworkSourceUri = false,
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
    DateTime? addedAt,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      duration: duration ?? this.duration,
      artworkUri: clearArtworkUri ? null : artworkUri ?? this.artworkUri,
      artworkSourceUri: clearArtworkSourceUri
          ? null
          : artworkSourceUri ?? this.artworkSourceUri,
      artworkIsUserManaged:
          artworkIsUserManaged ?? this.artworkIsUserManaged,
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
      genre: genre,
      duration: duration,
      artworkUri: artworkUriIsEphemeral ? null : artworkUri,
      artworkSourceUri: artworkSourceUri,
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
      addedAt: addedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'genre': genre,
      'durationMs': duration.inMilliseconds,
      'artworkUri': artworkUriIsEphemeral ? null : artworkUri?.toString(),
      'artworkSourceUri': artworkSourceUri?.toString(),
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
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory Track.fromJson(Map<String, Object?> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      album: json['album'] as String? ?? 'Unknown Album',
      genre: json['genre'] as String? ?? 'Unknown Genre',
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      artworkUri: _parseUri(json['artworkUri'] as String?),
      artworkSourceUri: _parseUri(json['artworkSourceUri'] as String?),
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

  static String stableLocalId(String path) {
    return base64Url.encode(utf8.encode(path)).replaceAll('=', '');
  }
}
