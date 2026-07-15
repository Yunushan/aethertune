import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../domain/track.dart';
import 'playback_audio_effects.dart';

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

abstract interface class PitchPlaybackAudioEngine
    implements PlaybackAudioEngine {
  bool get supportsPitch;
  double get pitch;

  Future<void> setPitch(double pitch);
}

abstract interface class AudioEffectsPlaybackAudioEngine
    implements PlaybackAudioEngine {
  bool get supportsEqualizer;
  bool get supportsLoudnessEnhancer;

  Future<void> setEqualizerEnabled(bool enabled);
  Future<void> setEqualizerProfile(PlaybackEqualizerProfile profile);
  Future<List<PlaybackEqualizerBand>> loadEqualizerBands();
  Future<void> setLoudnessEnhancerEnabled(bool enabled);
  Future<void> setLoudnessEnhancerTargetGain(double gainDb);
}

class JustAudioPlaybackEngine
    implements
        CrossfadePlaybackAudioEngine,
        AudioEffectsPlaybackAudioEngine,
        PitchPlaybackAudioEngine {
  factory JustAudioPlaybackEngine({
    AudioPlayer? player,
    bool enableAndroidAudioEffects = false,
    bool enablePitch = false,
  }) {
    if (player != null || !enableAndroidAudioEffects) {
      return JustAudioPlaybackEngine._(
        player: player ?? AudioPlayer(),
        crossfadePlayer: AudioPlayer(),
        enablePitch: enablePitch,
      );
    }

    final equalizer = AndroidEqualizer();
    final loudnessEnhancer = AndroidLoudnessEnhancer();
    final crossfadeEqualizer = AndroidEqualizer();
    final crossfadeLoudnessEnhancer = AndroidLoudnessEnhancer();
    return JustAudioPlaybackEngine._(
      player: AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: <AndroidAudioEffect>[
            loudnessEnhancer,
            equalizer,
          ],
        ),
      ),
      crossfadePlayer: AudioPlayer(
        audioPipeline: AudioPipeline(
          androidAudioEffects: <AndroidAudioEffect>[
            crossfadeLoudnessEnhancer,
            crossfadeEqualizer,
          ],
        ),
      ),
      equalizer: equalizer,
      crossfadeEqualizer: crossfadeEqualizer,
      loudnessEnhancer: loudnessEnhancer,
      crossfadeLoudnessEnhancer: crossfadeLoudnessEnhancer,
      enablePitch: enablePitch,
    );
  }

  JustAudioPlaybackEngine._({
    required AudioPlayer player,
    required AudioPlayer crossfadePlayer,
    AndroidEqualizer? equalizer,
    AndroidEqualizer? crossfadeEqualizer,
    AndroidLoudnessEnhancer? loudnessEnhancer,
    AndroidLoudnessEnhancer? crossfadeLoudnessEnhancer,
    required bool enablePitch,
  })  : _player = player,
        _crossfadePlayer = crossfadePlayer,
        _equalizer = equalizer,
        _crossfadeEqualizer = crossfadeEqualizer,
        _loudnessEnhancer = loudnessEnhancer,
        _crossfadeLoudnessEnhancer = crossfadeLoudnessEnhancer,
        _pitchEnabled = enablePitch {
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
  final AndroidEqualizer? _equalizer;
  final AndroidEqualizer? _crossfadeEqualizer;
  final AndroidLoudnessEnhancer? _loudnessEnhancer;
  final AndroidLoudnessEnhancer? _crossfadeLoudnessEnhancer;
  final bool _pitchEnabled;
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
  bool _mainSourceLoaded = false;
  bool _crossfadeSourceLoaded = false;
  PlaybackEqualizerProfile _equalizerProfile =
      const PlaybackEqualizerProfile(preset: PlaybackEqualizerPreset.flat);
  Future<void> _equalizerApplyTail = Future<void>.value();

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
  bool get supportsPitch => _pitchEnabled;

  @override
  double get pitch => _player.pitch;

  @override
  double get volume => _player.volume;

  @override
  bool get hasNext => _player.hasNext;

  @override
  bool get hasPrevious => _player.hasPrevious;

  @override
  bool get supportsCrossfade => true;

  @override
  bool get supportsEqualizer => _equalizer != null;

  @override
  bool get supportsLoudnessEnhancer => _loudnessEnhancer != null;

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
    _mainSourceLoaded = false;
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
    _mainSourceLoaded = true;
    await _scheduleEqualizerProfileApply();
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
  Future<void> setPitch(double pitch) async {
    if (!_pitchEnabled) {
      throw UnsupportedError('Pitch control is unavailable for this backend.');
    }
    await _player.setPitch(pitch);
    await _crossfadePlayer.setPitch(pitch);
  }

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {
    final equalizer = _equalizer;
    final crossfadeEqualizer = _crossfadeEqualizer;
    if (equalizer == null || crossfadeEqualizer == null) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    await equalizer.setEnabled(enabled);
    await crossfadeEqualizer.setEnabled(enabled);
  }

  @override
  Future<void> setEqualizerProfile(PlaybackEqualizerProfile profile) {
    if (!supportsEqualizer) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    _equalizerProfile = profile;
    return _scheduleEqualizerProfileApply();
  }

  @override
  Future<List<PlaybackEqualizerBand>> loadEqualizerBands() async {
    final equalizer = _equalizer;
    if (equalizer == null) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    if (!_mainSourceLoaded) {
      return const <PlaybackEqualizerBand>[];
    }

    final parameters = await equalizer.parameters;
    return parameters.bands
        .map(
          (band) => PlaybackEqualizerBand(
            index: band.index,
            centerFrequencyHz: band.centerFrequency,
            gainDb: band.gain,
            minGainDb: parameters.minDecibels,
            maxGainDb: parameters.maxDecibels,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> setLoudnessEnhancerEnabled(bool enabled) async {
    final enhancer = _loudnessEnhancer;
    final crossfadeEnhancer = _crossfadeLoudnessEnhancer;
    if (enhancer == null || crossfadeEnhancer == null) {
      throw UnsupportedError(
        'Loudness enhancer is unavailable for this audio backend.',
      );
    }
    await enhancer.setEnabled(enabled);
    await crossfadeEnhancer.setEnabled(enabled);
  }

  @override
  Future<void> setLoudnessEnhancerTargetGain(double gainDb) async {
    final enhancer = _loudnessEnhancer;
    final crossfadeEnhancer = _crossfadeLoudnessEnhancer;
    if (enhancer == null || crossfadeEnhancer == null) {
      throw UnsupportedError(
        'Loudness enhancer is unavailable for this audio backend.',
      );
    }
    await enhancer.setTargetGain(gainDb);
    await crossfadeEnhancer.setTargetGain(gainDb);
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
      _crossfadeSourceLoaded = true;
      await _scheduleEqualizerProfileApply();
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

  Future<void> _scheduleEqualizerProfileApply() {
    final operation = _applyEqualizerProfileAfter(_equalizerApplyTail);
    _equalizerApplyTail = operation;
    return operation;
  }

  Future<void> _applyEqualizerProfileAfter(Future<void> previous) async {
    try {
      await previous;
    } on Object {
      // A later profile should still be applied after an earlier native error.
    }
    if (_mainSourceLoaded) {
      await _applyEqualizerProfileTo(_equalizer);
    }
    if (_crossfadeSourceLoaded) {
      await _applyEqualizerProfileTo(_crossfadeEqualizer);
    }
  }

  Future<void> _applyEqualizerProfileTo(AndroidEqualizer? equalizer) async {
    if (equalizer == null) {
      return;
    }
    final parameters = await equalizer.parameters;
    for (final band in parameters.bands) {
      final gain = equalizerGainForFrequency(
        _equalizerProfile,
        band.centerFrequency,
      ).clamp(parameters.minDecibels, parameters.maxDecibels).toDouble();
      await band.setGain(gain);
    }
  }
}
