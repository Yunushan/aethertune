import '../domain/track.dart';

class OfflinePlaybackBlockedException implements Exception {
  const OfflinePlaybackBlockedException(this.track);

  final Track track;

  @override
  String toString() {
    return 'Offline mode blocks network playback for ${track.title}.';
  }
}

String offlinePlaybackBlockedMessage(Track track) {
  return 'Offline mode is on. ${track.title} needs a network stream.';
}

bool offlineModeAllowsPlayback(Track track, {required bool offlineModeEnabled}) {
  if (!track.isPlayable) {
    return false;
  }

  return !offlineModeEnabled || track.hasLocalSource;
}

void requireOfflineModePlaybackAllowed(
  Track track, {
  required bool offlineModeEnabled,
}) {
  if (offlineModeAllowsPlayback(
    track,
    offlineModeEnabled: offlineModeEnabled,
  )) {
    return;
  }

  if (offlineModeEnabled && !track.hasLocalSource) {
    throw OfflinePlaybackBlockedException(track);
  }

  throw StateError('Track has no local path or stream URL: ${track.title}');
}
