import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../domain/track.dart';
import 'desktop_media_session.dart';

/// Bridges AetherTune playback to Windows System Media Transport Controls.
class WindowsSystemMediaSession implements DesktopMediaSession {
  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _buttonSubscription;
  Future<void> Function(DesktopMediaSessionCommand command)? _onCommand;

  @override
  Future<void> start(
    Future<void> Function(DesktopMediaSessionCommand command) onCommand,
  ) async {
    if (_smtc != null) {
      return;
    }
    _onCommand = onCommand;
    await SMTCWindows.initialize();
    final smtc = SMTCWindows();
    _smtc = smtc;
    _buttonSubscription = smtc.buttonPressStream
        .cast<PressedButton>()
        .listen((button) => unawaited(_dispatch(button)));
  }

  @override
  Future<void> publish(DesktopMediaSessionState state) async {
    final smtc = _smtc;
    if (smtc == null) {
      return;
    }
    final duration = state.duration ?? Duration.zero;
    final position = state.position < Duration.zero
        ? Duration.zero
        : state.position > duration && duration > Duration.zero
        ? duration
        : state.position;
    await smtc.updateConfig(
      SMTCConfig(
        playEnabled: !state.isPlaying,
        pauseEnabled: state.isPlaying,
        prevEnabled: state.canGoPrevious,
        nextEnabled: state.canGoNext,
        rewindEnabled: duration > Duration.zero,
        fastForwardEnabled: duration > Duration.zero,
        stopEnabled: true,
      ),
    );
    await smtc.updateMetadata(
      MusicMetadata(
        title: state.track?.title ?? 'AetherTune',
        artist: state.track?.artist,
        album: state.track?.album,
        albumArtist: state.track?.artist,
        thumbnail: _safeThumbnail(state.track),
      ),
    );
    await smtc.updateTimeline(
      PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: duration.inMilliseconds,
        positionMs: position.inMilliseconds,
        minSeekTimeMs: 0,
        maxSeekTimeMs: duration.inMilliseconds,
      ),
    );
    await smtc.setPlaybackStatus(_statusFor(state));
  }

  @override
  Future<void> dispose() async {
    await _buttonSubscription?.cancel();
    _buttonSubscription = null;
    final smtc = _smtc;
    _smtc = null;
    _onCommand = null;
    if (smtc != null) {
      await smtc.dispose();
    }
  }

  Future<void> _dispatch(PressedButton button) async {
    final onCommand = _onCommand;
    if (onCommand == null) {
      return;
    }
    switch (button) {
      case PressedButton.play:
        return onCommand(DesktopMediaSessionCommand.play);
      case PressedButton.pause:
        return onCommand(DesktopMediaSessionCommand.pause);
      case PressedButton.previous:
        return onCommand(DesktopMediaSessionCommand.previous);
      case PressedButton.next:
        return onCommand(DesktopMediaSessionCommand.next);
      case PressedButton.rewind:
        return onCommand(DesktopMediaSessionCommand.seekBackward);
      case PressedButton.fastForward:
        return onCommand(DesktopMediaSessionCommand.seekForward);
      case PressedButton.stop:
        return onCommand(DesktopMediaSessionCommand.stop);
      case PressedButton.record:
      case PressedButton.channelUp:
      case PressedButton.channelDown:
        return;
    }
  }

  PlaybackStatus _statusFor(DesktopMediaSessionState state) {
    if (state.isPlaying) {
      return PlaybackStatus.playing;
    }
    switch (state.processingState) {
      case ProcessingState.idle:
      case ProcessingState.completed:
        return PlaybackStatus.stopped;
      case ProcessingState.loading:
      case ProcessingState.buffering:
        return PlaybackStatus.changing;
      case ProcessingState.ready:
        return PlaybackStatus.paused;
    }
  }
}

String? _safeThumbnail(Track? track) {
  if (track == null || track.artworkUriIsEphemeral) {
    return null;
  }
  final artworkUri = track.artworkUri;
  if (artworkUri == null) {
    return null;
  }
  switch (artworkUri.scheme) {
    case 'file':
    case 'http':
    case 'https':
      return artworkUri.toString();
    default:
      return null;
  }
}
