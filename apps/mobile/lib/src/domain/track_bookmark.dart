final class TrackBookmark {
  const TrackBookmark({
    required this.id,
    required this.trackId,
    required this.position,
    required this.createdAt,
  });

  final String id;
  final String trackId;
  final Duration position;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'trackId': trackId,
    'positionMs': position.inMilliseconds,
    'createdAt': createdAt.toIso8601String(),
  };

  static TrackBookmark? tryFromJson(Map<String, Object?> json) {
    final id = json['id'];
    final trackId = json['trackId'];
    final positionMs = json['positionMs'];
    if (id is! String ||
        id.trim().isEmpty ||
        trackId is! String ||
        trackId.trim().isEmpty ||
        positionMs is! int ||
        positionMs < 0) {
      return null;
    }
    return TrackBookmark(
      id: id,
      trackId: trackId,
      position: Duration(milliseconds: positionMs),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
