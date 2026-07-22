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
    this.expectedMediaChecksum,
    this.audioFingerprint,
    this.replayGainTrackDb,
    this.replayGainAlbumDb,
    this.replayGainTrackPeak,
    this.replayGainAlbumPeak,
    this.streamUrl,
    this.streamUrlIsEphemeral = false,
    this.sourceId = 'local',
    this.externalId,
    this.isFavorite = false,
    int rating = 0,
    List<TrackChapter>? chapters,
    List<TrackSkipSegment>? skipSegments,
    this.transcriptUri,
    this.transcriptType,
    this.transcriptLanguage,
    DateTime? addedAt,
  }) : chapters = TrackChapter.normalize(
         chapters ?? const <TrackChapter>[],
         maximum: duration,
       ),
       skipSegments = TrackSkipSegment.normalize(
         skipSegments ?? const <TrackSkipSegment>[],
         maximum: duration,
       ),
       addedAt = addedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
       rating = _normalizeRating(rating);

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
  final String? expectedMediaChecksum;
  final String? audioFingerprint;
  final double? replayGainTrackDb;
  final double? replayGainAlbumDb;
  final double? replayGainTrackPeak;
  final double? replayGainAlbumPeak;
  final String? streamUrl;
  final bool streamUrlIsEphemeral;
  final String sourceId;
  final String? externalId;
  final bool isFavorite;
  final int rating;
  final List<TrackChapter> chapters;
  final List<TrackSkipSegment> skipSegments;
  final Uri? transcriptUri;
  final String? transcriptType;
  final String? transcriptLanguage;
  final DateTime addedAt;

  bool get hasLocalSource => localPath?.trim().isNotEmpty == true;
  bool get hasStreamSource => streamUrl?.trim().isNotEmpty == true;
  bool get isPlayable => hasLocalSource || hasStreamSource;
  bool get hasTranscript =>
      transcriptUri != null &&
      transcriptUri!.host.isNotEmpty &&
      (transcriptUri!.scheme.toLowerCase() == 'http' ||
          transcriptUri!.scheme.toLowerCase() == 'https');

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
    String? expectedMediaChecksum,
    String? audioFingerprint,
    double? replayGainTrackDb,
    double? replayGainAlbumDb,
    double? replayGainTrackPeak,
    double? replayGainAlbumPeak,
    String? streamUrl,
    bool? streamUrlIsEphemeral,
    String? sourceId,
    String? externalId,
    bool? isFavorite,
    int? rating,
    List<TrackChapter>? chapters,
    List<TrackSkipSegment>? skipSegments,
    Uri? transcriptUri,
    bool clearTranscriptUri = false,
    String? transcriptType,
    String? transcriptLanguage,
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
      expectedMediaChecksum:
          expectedMediaChecksum ?? this.expectedMediaChecksum,
      audioFingerprint: audioFingerprint ?? this.audioFingerprint,
      replayGainTrackDb: replayGainTrackDb ?? this.replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb ?? this.replayGainAlbumDb,
      replayGainTrackPeak: replayGainTrackPeak ?? this.replayGainTrackPeak,
      replayGainAlbumPeak: replayGainAlbumPeak ?? this.replayGainAlbumPeak,
      streamUrl: streamUrl ?? this.streamUrl,
      streamUrlIsEphemeral: streamUrlIsEphemeral ?? this.streamUrlIsEphemeral,
      sourceId: sourceId ?? this.sourceId,
      externalId: externalId ?? this.externalId,
      isFavorite: isFavorite ?? this.isFavorite,
      rating: rating ?? this.rating,
      chapters: chapters ?? this.chapters,
      skipSegments: skipSegments ?? this.skipSegments,
      transcriptUri:
          clearTranscriptUri ? null : transcriptUri ?? this.transcriptUri,
      transcriptType: transcriptType ?? this.transcriptType,
      transcriptLanguage: transcriptLanguage ?? this.transcriptLanguage,
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
      expectedMediaChecksum: expectedMediaChecksum,
      audioFingerprint: audioFingerprint,
      replayGainTrackDb: replayGainTrackDb,
      replayGainAlbumDb: replayGainAlbumDb,
      replayGainTrackPeak: replayGainTrackPeak,
      replayGainAlbumPeak: replayGainAlbumPeak,
      streamUrl: streamUrlIsEphemeral ? null : streamUrl,
      sourceId: sourceId,
      externalId: externalId,
      isFavorite: isFavorite,
      rating: rating,
      chapters: chapters,
      skipSegments: skipSegments,
      transcriptUri: transcriptUri,
      transcriptType: transcriptType,
      transcriptLanguage: transcriptLanguage,
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
      if (expectedMediaChecksum != null)
        'expectedMediaChecksum': expectedMediaChecksum,
      if (audioFingerprint != null) 'audioFingerprint': audioFingerprint,
      if (replayGainTrackDb != null) 'replayGainTrackDb': replayGainTrackDb,
      if (replayGainAlbumDb != null) 'replayGainAlbumDb': replayGainAlbumDb,
      if (replayGainTrackPeak != null)
        'replayGainTrackPeak': replayGainTrackPeak,
      if (replayGainAlbumPeak != null)
        'replayGainAlbumPeak': replayGainAlbumPeak,
      'streamUrl': streamUrlIsEphemeral ? null : streamUrl,
      'sourceId': sourceId,
      'externalId': externalId,
      'isFavorite': isFavorite,
      if (rating > 0) 'rating': rating,
      if (chapters.isNotEmpty)
        'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
      if (skipSegments.isNotEmpty)
        'skipSegments': skipSegments
            .map((segment) => segment.toJson())
            .toList(),
      if (hasTranscript) 'transcriptUri': transcriptUri.toString(),
      if (hasTranscript && transcriptType != null)
        'transcriptType': transcriptType,
      if (hasTranscript && transcriptLanguage != null)
        'transcriptLanguage': transcriptLanguage,
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
      expectedMediaChecksum: _parseExpectedMediaChecksum(
        json['expectedMediaChecksum'] as String?,
      ),
      audioFingerprint: json['audioFingerprint'] as String?,
      replayGainTrackDb: sanitizeReplayGainDb(
        (json['replayGainTrackDb'] as num?)?.toDouble(),
      ),
      replayGainAlbumDb: sanitizeReplayGainDb(
        (json['replayGainAlbumDb'] as num?)?.toDouble(),
      ),
      replayGainTrackPeak: sanitizeReplayGainPeak(
        (json['replayGainTrackPeak'] as num?)?.toDouble(),
      ),
      replayGainAlbumPeak: sanitizeReplayGainPeak(
        (json['replayGainAlbumPeak'] as num?)?.toDouble(),
      ),
      streamUrl: json['streamUrl'] as String?,
      sourceId: json['sourceId'] as String? ?? 'local',
      externalId: json['externalId'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      rating: _jsonRating(json['rating']),
      chapters: _parseChapters(json['chapters']),
      skipSegments: _parseSkipSegments(json['skipSegments']),
      transcriptUri: _parseHttpUri(json['transcriptUri'] as String?),
      transcriptType: json['transcriptType'] as String?,
      transcriptLanguage: json['transcriptLanguage'] as String?,
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

  static String? _parseExpectedMediaChecksum(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (RegExp(r'^md5:[a-f0-9]{32}$').hasMatch(normalized) ||
        RegExp(r'^sha1:[a-f0-9]{40}$').hasMatch(normalized) ||
        RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(normalized)) {
      return normalized;
    }
    return null;
  }

  static int _normalizeRating(int value) => value.clamp(0, 5).toInt();

  static int _jsonRating(Object? value) {
    return value is num ? _normalizeRating(value.toInt()) : 0;
  }

  static Uri? _parseHttpUri(String? value) {
    final uri = _parseUri(value);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme.toLowerCase() != 'http' &&
            uri.scheme.toLowerCase() != 'https')) {
      return null;
    }
    return uri;
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
