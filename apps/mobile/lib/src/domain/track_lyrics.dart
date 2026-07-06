/// User-managed plain-text lyrics attached to one library track.
class TrackLyrics {
  TrackLyrics({
    required this.trackId,
    required this.plainText,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String trackId;
  final String plainText;
  final DateTime updatedAt;

  bool get isEmpty => plainText.trim().isEmpty;

  TrackLyrics copyWith({
    String? trackId,
    String? plainText,
    DateTime? updatedAt,
  }) {
    return TrackLyrics(
      trackId: trackId ?? this.trackId,
      plainText: plainText ?? this.plainText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'trackId': trackId,
      'plainText': plainText,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory TrackLyrics.fromJson(Map<String, Object?> json) {
    return TrackLyrics(
      trackId: json['trackId'] as String,
      plainText: json['plainText'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
