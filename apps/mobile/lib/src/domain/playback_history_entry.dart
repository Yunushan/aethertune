/// One local playback-history event for a library track.
class PlaybackHistoryEntry {
  PlaybackHistoryEntry({
    required this.trackId,
    DateTime? playedAt,
  }) : playedAt = playedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String trackId;
  final DateTime playedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'trackId': trackId,
      'playedAt': playedAt.toIso8601String(),
    };
  }

  factory PlaybackHistoryEntry.fromJson(Map<String, Object?> json) {
    return PlaybackHistoryEntry(
      trackId: json['trackId'] as String,
      playedAt: DateTime.tryParse(json['playedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
