class ListenTogetherSession {
  const ListenTogetherSession({
    required this.trackIds,
    required this.position,
    required this.playing,
    this.currentTrackId,
  });

  static const version = 1;
  static const maxTrackIds = 500;

  final List<String> trackIds;
  final String? currentTrackId;
  final Duration position;
  final bool playing;

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'trackIds': trackIds,
        'currentTrackId': currentTrackId,
        'positionMilliseconds': position.inMilliseconds,
        'playing': playing,
      };

  factory ListenTogetherSession.fromJson(Map<String, Object?> json) {
    if (json['version'] != version) {
      throw const FormatException('Unsupported listen-together session version.');
    }
    final rawTrackIds = json['trackIds'];
    if (rawTrackIds is! List || rawTrackIds.length > maxTrackIds) {
      throw const FormatException('Listen-together track IDs are invalid.');
    }
    final trackIds = <String>[];
    for (final value in rawTrackIds) {
      if (value is! String ||
          value != value.trim() ||
          value.isEmpty ||
          value.length > 256) {
        throw const FormatException('Listen-together track IDs are invalid.');
      }
      trackIds.add(value.trim());
    }
    if (trackIds.toSet().length != trackIds.length) {
      throw const FormatException('Listen-together track IDs must not repeat.');
    }
    final currentTrackId = json['currentTrackId'];
    if (currentTrackId != null &&
        (currentTrackId is! String ||
            currentTrackId != currentTrackId.trim() ||
            !trackIds.contains(currentTrackId))) {
      throw const FormatException(
        'Listen-together current track must belong to the queue.',
      );
    }
    final positionMilliseconds = json['positionMilliseconds'];
    if (positionMilliseconds is! int ||
        positionMilliseconds < 0 ||
        positionMilliseconds > 7 * 24 * 60 * 60 * 1000) {
      throw const FormatException('Listen-together position is invalid.');
    }
    if (json['playing'] is! bool) {
      throw const FormatException('Listen-together playing state is invalid.');
    }
    return ListenTogetherSession(
      trackIds: List<String>.unmodifiable(trackIds),
      currentTrackId: currentTrackId as String?,
      position: Duration(milliseconds: positionMilliseconds),
      playing: json['playing'] as bool,
    );
  }
}
