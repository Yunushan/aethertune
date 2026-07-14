import 'artwork_crop.dart';

/// A user-managed list of tracks.
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<String> trackIds = const <String>[],
    this.folder = '',
    this.artworkUri,
    this.artworkCrop = ArtworkCrop.centered,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : trackIds = List.unmodifiable(trackIds),
        createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final List<String> trackIds;
  final String folder;
  final Uri? artworkUri;
  final ArtworkCrop artworkCrop;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get trackCount => trackIds.length;
  bool containsTrack(String trackId) => trackIds.contains(trackId);

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    String? folder,
    Uri? artworkUri,
    bool clearArtworkUri = false,
    ArtworkCrop? artworkCrop,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      folder: folder ?? this.folder,
      artworkUri: clearArtworkUri ? null : artworkUri ?? this.artworkUri,
      artworkCrop: artworkCrop ?? this.artworkCrop,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'trackIds': trackIds,
      'folder': folder,
      'artworkUri': artworkUri?.toString(),
      if (!artworkCrop.isCentered) 'artworkCrop': artworkCrop.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Playlist.fromJson(Map<String, Object?> json) {
    final rawTrackIds = json['trackIds'] as List<dynamic>? ?? <dynamic>[];

    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled playlist',
      trackIds: rawTrackIds.whereType<String>().toList(growable: false),
      folder: json['folder'] as String? ?? '',
      artworkUri: _parseUri(json['artworkUri'] as String?),
      artworkCrop: ArtworkCrop.fromJson(json['artworkCrop']),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static Uri? _parseUri(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return Uri.tryParse(value.trim());
  }
}
