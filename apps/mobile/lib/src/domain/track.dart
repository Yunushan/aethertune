import 'dart:convert';

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
    this.localPath,
    this.streamUrl,
    this.sourceId = 'local',
    this.isFavorite = false,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final Duration duration;
  final Uri? artworkUri;
  final String? localPath;
  final String? streamUrl;
  final String sourceId;
  final bool isFavorite;
  final DateTime addedAt;

  bool get isPlayable => localPath != null || streamUrl != null;

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? genre,
    Duration? duration,
    Uri? artworkUri,
    String? localPath,
    String? streamUrl,
    String? sourceId,
    bool? isFavorite,
    DateTime? addedAt,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      duration: duration ?? this.duration,
      artworkUri: artworkUri ?? this.artworkUri,
      localPath: localPath ?? this.localPath,
      streamUrl: streamUrl ?? this.streamUrl,
      sourceId: sourceId ?? this.sourceId,
      isFavorite: isFavorite ?? this.isFavorite,
      addedAt: addedAt ?? this.addedAt,
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
      'artworkUri': artworkUri?.toString(),
      'localPath': localPath,
      'streamUrl': streamUrl,
      'sourceId': sourceId,
      'isFavorite': isFavorite,
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
      localPath: json['localPath'] as String?,
      streamUrl: json['streamUrl'] as String?,
      sourceId: json['sourceId'] as String? ?? 'local',
      isFavorite: json['isFavorite'] as bool? ?? false,
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static Uri? _parseUri(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return Uri.tryParse(value);
  }

  static String stableLocalId(String path) {
    return base64Url.encode(utf8.encode(path)).replaceAll('=', '');
  }
}
