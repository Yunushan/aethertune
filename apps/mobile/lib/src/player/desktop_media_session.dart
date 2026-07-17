import '../domain/track.dart';
import 'playback_audio_engine.dart';

/// Commands a desktop operating-system media session can send to playback.
enum DesktopMediaSessionCommand {
  play,
  pause,
  previous,
  next,
  seekBackward,
  seekForward,
  stop,
}

/// A snapshot published to a native desktop media-control surface.
class DesktopMediaSessionState {
  const DesktopMediaSessionState({
    required this.track,
    required this.processingState,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.canGoPrevious,
    required this.canGoNext,
  });

  final Track? track;
  final ProcessingState processingState;
  final bool isPlaying;
  final Duration position;
  final Duration? duration;
  final bool canGoPrevious;
  final bool canGoNext;
}

/// Publishes playback state and receives transport actions from a desktop OS.
abstract interface class DesktopMediaSession {
  Future<void> start(
    Future<void> Function(DesktopMediaSessionCommand command) onCommand,
  );

  Future<void> publish(DesktopMediaSessionState state);

  Future<void> dispose();
}
