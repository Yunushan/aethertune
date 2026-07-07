final class PlaybackProgressEntry {
  const PlaybackProgressEntry({
    required this.trackId,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String trackId;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  double get fraction {
    if (duration == Duration.zero) {
      return 0;
    }

    return (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'trackId': trackId,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PlaybackProgressEntry.fromJson(Map<String, Object?> json) {
    return PlaybackProgressEntry(
      trackId: json['trackId'] as String,
      position: Duration(milliseconds: json['positionMs'] as int? ?? 0),
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
