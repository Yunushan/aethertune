/// A user-managed list of tracks.
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<String> trackIds = const <String>[],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : trackIds = List.unmodifiable(trackIds),
        createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get trackCount => trackIds.length;
  bool containsTrack(String trackId) => trackIds.contains(trackId);

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'trackIds': trackIds,
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
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
