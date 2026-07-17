final class TrackBookmark {
  static const maxLabelLength = 80;

  const TrackBookmark({
    required this.id,
    required this.trackId,
    required this.position,
    required this.createdAt,
    this.label = '',
  });

  final String id;
  final String trackId;
  final Duration position;
  final DateTime createdAt;
  final String label;

  TrackBookmark copyWith({String? trackId, String? label}) {
    return TrackBookmark(
      id: id,
      trackId: trackId ?? this.trackId,
      position: position,
      createdAt: createdAt,
      label: label ?? this.label,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'trackId': trackId,
    'positionMs': position.inMilliseconds,
    'createdAt': createdAt.toIso8601String(),
    'label': label,
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
      label: normalizeLabel(json['label'] is String ? json['label'] as String : ''),
    );
  }

  static String normalizeLabel(String value) {
    final normalized = value.trim();
    return normalized.length <= maxLabelLength
        ? normalized
        : normalized.substring(0, maxLabelLength);
  }
}
