import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../domain/track.dart';

typedef CrossfadeTrackVolumeResolver = double Function(Track track);

abstract interface class PlaybackAudioEngine {
  Stream<Object?> get stateChanges;
  Stream<Duration?> get durationStream;
  Stream<Duration> get positionStream;
  Stream<ProcessingState> get processingStateStream;
  Stream<int?> get currentIndexStream;

  bool get playing;
  bool get shuffleModeEnabled;
  LoopMode get loopMode;
  Duration get position;
  Duration get bufferedPosition;
  double get speed;
  double get volume;
  bool get hasNext;
  bool get hasPrevious;

  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position, {int? index});
  Future<void> seekToNext();
  Future<void> seekToPrevious();
  Future<void> setShuffleModeEnabled(bool enabled);
  Future<void> setLoopMode(LoopMode mode);
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

abstract interface class CrossfadePlaybackAudioEngine
    implements PlaybackAudioEngine {
  bool get supportsCrossfade;
  Duration get crossfadeDuration;

  void setCrossfadeTrackVolumeResolver(
    CrossfadeTrackVolumeResolver? resolver,
  );
  Future<void> setCrossfadeDuration(Duration duration);
}

class JustAudioPlaybackEngine implements CrossfadePlaybackAudioEngine {
  JustAudioPlaybackEngine({AudioPlayer? player})
      : _player = player ?? AudioPlayer(),
        _crossfadePlayer = AudioPlayer() {
    _durationSubscription = _player.durationStream.listen(
      (_) => _scheduleCrossfade(),
    );
    _indexSubscription = _player.currentIndexStream.listen(
      (_) => _scheduleCrossfade(),
    );
    _stateSubscription = _player.playerStateStream.listen((_) {
      _scheduleCrossfade();
    });
  }

  final AudioPlayer _player;
  final AudioPlayer _crossfadePlayer;
  final List<Track> _queue = <Track>[];
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;
  Timer? _crossfadeStartTimer;
  Timer? _crossfadeStepTimer;
  Duration _crossfadeDuration = Duration.zero;
  double _requestedVolume = 1;
  CrossfadeTrackVolumeResolver? _crossfadeTrackVolumeResolver;
  bool _crossfadeActive = false;

  static const _crossfadeStepInterval = Duration(milliseconds: 50);

  @override
  Stream<Object?> get stateChanges => _player.playerStateStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  @override
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  @override
  bool get playing => _player.playing;

  @override
  bool get shuffleModeEnabled => _player.shuffleModeEnabled;

  @override
  LoopMode get loopMode => _player.loopMode;

  @override
  Duration get position => _player.position;

  @override
  Duration get bufferedPosition => _player.bufferedPosition;

  @override
  double get speed => _player.speed;

  @override
  double get volume => _player.volume;

  @override
  bool get hasNext => _player.hasNext;

  @override
  bool get hasPrevious => _player.hasPrevious;

  @override
  bool get supportsCrossfade => true;

  @override
  Duration get crossfadeDuration => _crossfadeDuration;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    if (tracks.isEmpty) {
      throw ArgumentError.value(tracks, 'tracks', 'Queue cannot be empty.');
    }
    if (initialIndex < 0 || initialIndex >= tracks.length) {
      throw RangeError.index(initialIndex, tracks, 'initialIndex');
    }

    _cancelCrossfade();
    await _crossfadePlayer.stop();
    _queue
      ..clear()
      ..addAll(tracks);
    final playlist = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: tracks.map(_audioSourceForTrack).toList(growable: false),
    );
    await _player.setAudioSource(
      playlist,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
    _scheduleCrossfade();
  }

  AudioSource _audioSourceForTrack(Track track) {
    if (track.hasLocalSource) {
      return AudioSource.file(track.localPath!, tag: track.id);
    }
    if (track.hasStreamSource) {
      return AudioSource.uri(Uri.parse(track.streamUrl!), tag: track.id);
    }
    throw StateError('Track has no local path or stream URL: ${track.title}');
  }

  @override
  Future<void> play() {
    unawaited(_player.play());
    _scheduleCrossfade();
    return Future<void>.value();
  }

  @override
  Future<void> pause() async {
    _cancelCrossfade();
    await _crossfadePlayer.stop();
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    _cancelCrossfade();
    await _crossfadePlayer.stop();
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    _cancelCrossfade();
    await _crossfadePlayer.stop();
    await _player.seek(position, index: index);
    _scheduleCrossfade();
  }

  @override
  Future<void> seekToNext() async {
    _cancelCrossfade();
    await _crossfadePlayer.stop();
    await _player.seekToNext();
    _scheduleCrossfade();
  }

  @override
  Future<void> seekToPrevious() async {
    _cancelCrossfade();
    await _crossfadePlayer.stop();
    await _player.seekToPrevious();
    _scheduleCrossfade();
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _cancelCrossfade();
    await _crossfadePlayer.stop();
    await _player.setShuffleModeEnabled(enabled);
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
    _scheduleCrossfade();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    await _crossfadePlayer.setSpeed(speed);
    _scheduleCrossfade();
  }

  @override
  Future<void> setVolume(double volume) async {
    _requestedVolume = volume;
    if (_crossfadeActive) {
      return;
    }
    await _player.setVolume(volume);
    await _crossfadePlayer.setVolume(volume);
  }

  @override
  void setCrossfadeTrackVolumeResolver(
    CrossfadeTrackVolumeResolver? resolver,
  ) {
    _crossfadeTrackVolumeResolver = resolver;
  }

  @override
  Future<void> setCrossfadeDuration(Duration duration) async {
    if (duration < Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
    }
    _crossfadeDuration = duration;
    _cancelCrossfade();
    await _crossfadePlayer.stop();
    await _player.setVolume(_requestedVolume);
    _scheduleCrossfade();
  }

  @override
  Future<void> dispose() async {
    _cancelCrossfade();
    await _durationSubscription?.cancel();
    await _indexSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _crossfadePlayer.dispose();
    await _player.dispose();
  }

  void _scheduleCrossfade() {
    _crossfadeStartTimer?.cancel();
    _crossfadeStartTimer = null;
    if (_crossfadeActive ||
        _crossfadeDuration <= Duration.zero ||
        !_player.playing ||
        _player.shuffleModeEnabled ||
        _player.loopMode == LoopMode.one) {
      return;
    }

    final currentIndex = _player.currentIndex;
    final duration = _player.duration;
    if (currentIndex == null || duration == null || duration <= Duration.zero) {
      return;
    }
    final nextIndex = _nextIndex(currentIndex);
    if (nextIndex == null) {
      return;
    }

    final fadeAudioDuration = Duration(
      microseconds: (_crossfadeDuration.inMicroseconds * _player.speed).round(),
    );
    final remainingAudio = duration - _player.position;
    if (remainingAudio <= fadeAudioDuration) {
      return;
    }
    final delay = Duration(
      microseconds:
          ((remainingAudio - fadeAudioDuration).inMicroseconds / _player.speed)
              .round(),
    );
    _crossfadeStartTimer = Timer(delay, () {
      unawaited(_beginCrossfade(currentIndex, nextIndex));
    });
  }

  int? _nextIndex(int currentIndex) {
    if (currentIndex + 1 < _queue.length) {
      return currentIndex + 1;
    }
    if (_player.loopMode == LoopMode.all && _queue.isNotEmpty) {
      return 0;
    }
    return null;
  }

  Future<void> _beginCrossfade(int expectedIndex, int nextIndex) async {
    _crossfadeStartTimer = null;
    if (_crossfadeActive ||
        !_player.playing ||
        _player.currentIndex != expectedIndex ||
        nextIndex < 0 ||
        nextIndex >= _queue.length) {
      return;
    }

    _crossfadeActive = true;
    final startedAt = DateTime.now();
    final outgoingTrack = _queue[expectedIndex];
    final incomingTrack = _queue[nextIndex];
    try {
      await _crossfadePlayer.stop();
      await _crossfadePlayer.setAudioSource(_audioSourceForTrack(incomingTrack));
      await _crossfadePlayer.setSpeed(_player.speed);
      await _crossfadePlayer.setVolume(0);
      unawaited(_crossfadePlayer.play());

      _crossfadeStepTimer = Timer.periodic(_crossfadeStepInterval, (timer) {
        final ratio = (DateTime.now().difference(startedAt).inMicroseconds /
                _crossfadeDuration.inMicroseconds)
            .clamp(0, 1)
            .toDouble();
        unawaited(
          _player.setVolume(_crossfadeVolumeFor(outgoingTrack) * (1 - ratio)),
        );
        unawaited(
          _crossfadePlayer.setVolume(
            _crossfadeVolumeFor(incomingTrack) * ratio,
          ),
        );
        if (ratio >= 1) {
          timer.cancel();
          _crossfadeStepTimer = null;
          unawaited(_completeCrossfade(nextIndex, incomingTrack));
        }
      });
    } on Object {
      _cancelCrossfade();
      await _crossfadePlayer.stop();
      await _player.setVolume(_crossfadeVolumeFor(outgoingTrack));
      _scheduleCrossfade();
    }
  }

  Future<void> _completeCrossfade(int nextIndex, Track incomingTrack) async {
    final position = Duration(
      microseconds: (_crossfadeDuration.inMicroseconds * _player.speed).round(),
    );
    _crossfadeActive = false;
    try {
      await _player.seek(position, index: nextIndex);
      await _player.setVolume(_crossfadeVolumeFor(incomingTrack));
      if (!_player.playing) {
        unawaited(_player.play());
      }
    } finally {
      await _crossfadePlayer.stop();
      await _crossfadePlayer.setVolume(_requestedVolume);
      _scheduleCrossfade();
    }
  }

  double _crossfadeVolumeFor(Track track) =>
      _crossfadeTrackVolumeResolver?.call(track) ?? _requestedVolume;

  void _cancelCrossfade() {
    _crossfadeStartTimer?.cancel();
    _crossfadeStartTimer = null;
    _crossfadeStepTimer?.cancel();
    _crossfadeStepTimer = null;
    _crossfadeActive = false;
  }
}
