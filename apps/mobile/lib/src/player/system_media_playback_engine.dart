import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/track.dart';
import 'android_playback_widget_bridge.dart';
import 'playback_audio_effects.dart';
import 'playback_audio_engine.dart';

/// Adds operating-system media controls around the app's playback engine.
class SystemMediaPlaybackEngine extends BaseAudioHandler
    with SeekHandler
    implements
        CrossfadePlaybackAudioEngine,
        AudioEffectsPlaybackAudioEngine,
        VirtualizerPlaybackAudioEngine,
        AudioVisualizationPlaybackAudioEngine,
        SkipSilencePlaybackAudioEngine,
        PitchPlaybackAudioEngine,
        PlaybackErrorAudioEngine {
  SystemMediaPlaybackEngine(
    this._engine, {
    PlaybackWidgetBridge? playbackWidgetBridge,
  }) : _playbackWidgetBridge =
           playbackWidgetBridge ?? const AndroidPlaybackWidgetBridge() {
    _stateSubscription = _engine.stateChanges.listen((_) => _publishState());
    _processingSubscription = _engine.processingStateStream.listen((state) {
      _processingState = state;
      _publishState();
    });
    _indexSubscription = _engine.currentIndexStream.listen((index) {
      _currentIndex = index;
      _runtimeDuration = null;
      _publishQueueAndCurrentItem();
      _publishState();
    });
    _durationSubscription = _engine.durationStream.listen((duration) {
      _runtimeDuration = duration;
      _publishQueueAndCurrentItem();
      _publishWidgetState();
    });
    _positionSubscription = _engine.positionStream.listen(
      _publishWidgetProgress,
    );
    _publishState();
  }

  static const _widgetProgressUpdateInterval = Duration(seconds: 1);
  static const _androidAutoQueueId = 'aethertune:android-auto:queue';

  final PlaybackAudioEngine _engine;
  final PlaybackWidgetBridge _playbackWidgetBridge;
  final List<Track> _tracks = <Track>[];
  StreamSubscription<Object?>? _stateSubscription;
  StreamSubscription<ProcessingState>? _processingSubscription;
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  int? _currentIndex;
  Duration? _runtimeDuration;
  Duration? _lastWidgetProgressPosition;
  ProcessingState _processingState = ProcessingState.idle;

  @override
  Stream<Object?> get stateChanges => _engine.stateChanges;

  @override
  Stream<Duration?> get durationStream => _engine.durationStream;

  @override
  Stream<Duration> get positionStream => _engine.positionStream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _engine.processingStateStream;

  @override
  Stream<int?> get currentIndexStream => _engine.currentIndexStream;

  @override
  Stream<Object> get errorStream {
    final engine = _engine;
    return engine is PlaybackErrorAudioEngine
        ? (engine as PlaybackErrorAudioEngine).errorStream
        : const Stream<Object>.empty();
  }

  @override
  bool get playing => _engine.playing;

  @override
  bool get shuffleModeEnabled => _engine.shuffleModeEnabled;

  @override
  LoopMode get loopMode => _engine.loopMode;

  @override
  Duration get position => _engine.position;

  @override
  Duration get bufferedPosition => _engine.bufferedPosition;

  @override
  double get speed => _engine.speed;

  @override
  bool get supportsPitch =>
      _engine is PitchPlaybackAudioEngine && _engine.supportsPitch;

  @override
  double get pitch => _engine is PitchPlaybackAudioEngine ? _engine.pitch : 1;

  @override
  double get volume => _engine.volume;

  @override
  bool get hasNext => _engine.hasNext;

  @override
  bool get hasPrevious => _engine.hasPrevious;

  @override
  bool get supportsCrossfade =>
      _engine is CrossfadePlaybackAudioEngine &&
      _engine.supportsCrossfade;

  @override
  Duration get crossfadeDuration => _engine is CrossfadePlaybackAudioEngine
      ? _engine.crossfadeDuration
      : Duration.zero;

  @override
  bool get supportsEqualizer =>
      _engine is AudioEffectsPlaybackAudioEngine && _engine.supportsEqualizer;

  @override
  bool get supportsLoudnessEnhancer =>
      _engine is AudioEffectsPlaybackAudioEngine &&
      _engine.supportsLoudnessEnhancer;

  @override
  bool get supportsVirtualizer =>
      _engine is VirtualizerPlaybackAudioEngine && _engine.supportsVirtualizer;

  @override
  bool get supportsSkipSilence =>
      _engine is SkipSilencePlaybackAudioEngine &&
      _engine.supportsSkipSilence;

  @override
  bool get supportsVisualizer =>
      _engine is AudioVisualizationPlaybackAudioEngine &&
      _engine.supportsVisualizer;

  @override
  Stream<List<double>> get visualizerBands =>
      _engine is AudioVisualizationPlaybackAudioEngine
      ? _engine.visualizerBands
      : const Stream<List<double>>.empty();

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    final previousTracks = List<Track>.from(_tracks);
    final previousIndex = _currentIndex;
    _tracks
      ..clear()
      ..addAll(tracks);
    _currentIndex = initialIndex;
    _runtimeDuration = null;
    _publishQueueAndCurrentItem();

    try {
      await _engine.setQueue(
        tracks,
        initialIndex: initialIndex,
        initialPosition: initialPosition,
      );
      _publishState();
    } on Object {
      _tracks
        ..clear()
        ..addAll(previousTracks);
      _currentIndex = previousIndex;
      _runtimeDuration = null;
      _publishQueueAndCurrentItem();
      rethrow;
    }
  }

  @override
  Future<void> play() => _engine.play();

  @override
  Future<void> pause() => _engine.pause();

  @override
  Future<void> stop() async {
    await _engine.stop();
    _publishState();
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    await _engine.seek(position, index: index);
    _publishState();
  }

  @override
  Future<void> seekToNext() => _engine.seekToNext();

  @override
  Future<void> seekToPrevious() => _engine.seekToPrevious();

  @override
  Future<void> skipToNext() async {
    if (_engine.hasNext) {
      await _engine.seekToNext();
    } else if (_engine.loopMode == LoopMode.all && _tracks.isNotEmpty) {
      await _engine.seek(Duration.zero, index: 0);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_engine.hasPrevious) {
      await _engine.seekToPrevious();
    } else if (_engine.loopMode == LoopMode.all && _tracks.isNotEmpty) {
      await _engine.seek(Duration.zero, index: _tracks.length - 1);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) {
      throw RangeError.index(index, _tracks, 'index');
    }
    await _engine.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    await _engine.setShuffleModeEnabled(enabled);
    _publishState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      setShuffleModeEnabled(shuffleMode != AudioServiceShuffleMode.none);

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    await _engine.setLoopMode(mode);
    _publishState();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _engine.setSpeed(speed);
    _publishState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      setLoopMode(_loopModeForRepeatMode(repeatMode));

  @override
  Future<void> setVolume(double volume) => _engine.setVolume(volume);

  @override
  void setCrossfadeTrackVolumeResolver(
    CrossfadeTrackVolumeResolver? resolver,
  ) {
    final engine = _engine;
    if (engine is CrossfadePlaybackAudioEngine) {
      engine.setCrossfadeTrackVolumeResolver(resolver);
    }
  }

  @override
  Future<void> setCrossfadeDuration(Duration duration) {
    final engine = _engine;
    if (engine is! CrossfadePlaybackAudioEngine || !engine.supportsCrossfade) {
      throw UnsupportedError('Crossfade is unavailable for this audio backend.');
    }
    return engine.setCrossfadeDuration(duration);
  }

  @override
  Future<void> setPitch(double pitch) {
    final engine = _engine;
    if (engine is! PitchPlaybackAudioEngine || !engine.supportsPitch) {
      throw UnsupportedError('Pitch control is unavailable for this backend.');
    }
    return engine.setPitch(pitch);
  }

  @override
  Future<void> setEqualizerEnabled(bool enabled) {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsEqualizer) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    return engine.setEqualizerEnabled(enabled);
  }

  @override
  Future<void> setEqualizerProfile(PlaybackEqualizerProfile profile) {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsEqualizer) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    return engine.setEqualizerProfile(profile);
  }

  @override
  Future<List<PlaybackEqualizerBand>> loadEqualizerBands() {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsEqualizer) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    return engine.loadEqualizerBands();
  }

  @override
  Future<void> setLoudnessEnhancerEnabled(bool enabled) {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsLoudnessEnhancer) {
      throw UnsupportedError(
        'Loudness enhancer is unavailable for this audio backend.',
      );
    }
    return engine.setLoudnessEnhancerEnabled(enabled);
  }

  @override
  Future<void> setLoudnessEnhancerTargetGain(double gainDb) {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsLoudnessEnhancer) {
      throw UnsupportedError(
        'Loudness enhancer is unavailable for this audio backend.',
      );
    }
    return engine.setLoudnessEnhancerTargetGain(gainDb);
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        return <MediaItem>[_androidAutoQueueFolder()];
      case AudioService.recentRootId:
        final currentItem = _currentQueueMediaItem();
        return currentItem == null
            ? const <MediaItem>[]
            : <MediaItem>[currentItem];
      case _androidAutoQueueId:
        return _queueMediaItems();
      default:
        return const <MediaItem>[];
    }
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (mediaId == _androidAutoQueueId) {
      return _androidAutoQueueFolder();
    }
    for (var index = 0; index < _tracks.length; index += 1) {
      if (_tracks[index].id == mediaId) {
        final runtimeDuration = index == _currentIndex
            ? _runtimeDuration
            : null;
        return _mediaItemForTrack(_tracks[index], runtimeDuration);
      }
    }
    return null;
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final index = _tracks.indexWhere((track) => track.id == mediaId);
    if (index < 0) {
      return;
    }
    await _engine.seek(Duration.zero, index: index);
    await _engine.play();
  }

  @override
  Future<void> setVirtualizerEnabled(bool enabled) {
    final engine = _engine;
    if (engine is! VirtualizerPlaybackAudioEngine ||
        !engine.supportsVirtualizer) {
      throw UnsupportedError('Virtualizer is unavailable for this audio backend.');
    }
    return engine.setVirtualizerEnabled(enabled);
  }

  @override
  Future<void> setVirtualizerStrength(int strength) {
    final engine = _engine;
    if (engine is! VirtualizerPlaybackAudioEngine ||
        !engine.supportsVirtualizer) {
      throw UnsupportedError('Virtualizer is unavailable for this audio backend.');
    }
    return engine.setVirtualizerStrength(strength);
  }

  @override
  Future<void> setSkipSilenceEnabled(bool enabled) {
    final engine = _engine;
    if (engine is! SkipSilencePlaybackAudioEngine ||
        !engine.supportsSkipSilence) {
      throw UnsupportedError(
        'Skip silence is unavailable for this audio backend.',
      );
    }
    return engine.setSkipSilenceEnabled(enabled);
  }

  @override
  Future<bool> startVisualizer() {
    final engine = _engine;
    if (engine is! AudioVisualizationPlaybackAudioEngine ||
        !engine.supportsVisualizer) {
      return Future<bool>.value(false);
    }
    return engine.startVisualizer();
  }

  @override
  Future<void> stopVisualizer() {
    final engine = _engine;
    if (engine is! AudioVisualizationPlaybackAudioEngine ||
        !engine.supportsVisualizer) {
      return Future<void>.value();
    }
    return engine.stopVisualizer();
  }

  @override
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _processingSubscription?.cancel();
    await _indexSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _engine.dispose();
  }

  void _publishQueueAndCurrentItem() {
    final items = _queueMediaItems();
    queue.add(List<MediaItem>.unmodifiable(items));

    final index = _currentIndex;
    if (index == null || index < 0 || index >= items.length) {
      mediaItem.add(null);
      return;
    }
    mediaItem.add(items[index]);
  }

  List<MediaItem> _queueMediaItems() {
    return List<MediaItem>.generate(_tracks.length, (index) {
      final runtimeDuration = index == _currentIndex ? _runtimeDuration : null;
      return _mediaItemForTrack(_tracks[index], runtimeDuration);
    }, growable: false);
  }

  MediaItem? _currentQueueMediaItem() {
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _tracks.length) {
      return null;
    }
    return _mediaItemForTrack(_tracks[index], _runtimeDuration);
  }

  MediaItem _androidAutoQueueFolder() {
    return const MediaItem(
      id: _androidAutoQueueId,
      title: 'Current queue',
      displaySubtitle: 'AetherTune',
      playable: false,
    );
  }

  void _publishState() {
    playbackState.add(
      PlaybackState(
        controls: <MediaControl>[
          if (_engine.hasPrevious || _engine.loopMode == LoopMode.all)
            MediaControl.skipToPrevious,
          if (_engine.playing) MediaControl.pause else MediaControl.play,
          if (_engine.hasNext || _engine.loopMode == LoopMode.all)
            MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: _audioProcessingState(_processingState),
        playing: _engine.playing,
        updatePosition: _engine.position,
        bufferedPosition: _engine.bufferedPosition,
        speed: _engine.speed,
        queueIndex: _currentIndex,
        repeatMode: _repeatModeForLoopMode(_engine.loopMode),
        shuffleMode: _engine.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
    _publishWidgetState();
  }

  void _publishWidgetProgress(Duration position) {
    final lastPosition = _lastWidgetProgressPosition;
    if (!_engine.playing ||
        (lastPosition != null &&
            (position - lastPosition).abs() <
                _widgetProgressUpdateInterval)) {
      return;
    }
    _publishWidgetState(position: position);
  }

  void _publishWidgetState({Duration? position}) {
    final index = _currentIndex;
    final currentTrack = index != null && index >= 0 && index < _tracks.length
        ? _tracks[index]
        : null;
    final runtimeDuration = _runtimeDuration;
    final trackDuration = currentTrack?.duration ?? Duration.zero;
    final duration = runtimeDuration != null && runtimeDuration > Duration.zero
        ? runtimeDuration
        : trackDuration > Duration.zero
        ? trackDuration
        : null;
    final currentPosition = position ?? _engine.position;
    _lastWidgetProgressPosition = currentPosition;
    unawaited(
      _playbackWidgetBridge.update(
        track: currentTrack,
        isPlaying: _engine.playing,
        position: currentPosition,
        duration: duration,
      ),
    );
  }
}

MediaItem _mediaItemForTrack(Track track, Duration? runtimeDuration) {
  final knownDuration = runtimeDuration ?? track.duration;
  return MediaItem(
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    genre: track.genre,
    duration: knownDuration > Duration.zero ? knownDuration : null,
    artUri: track.artworkUri,
    extras: <String, Object>{
      'sourceId': track.sourceId,
      if (track.externalId != null) 'externalId': track.externalId!,
    },
  );
}

AudioProcessingState _audioProcessingState(ProcessingState state) {
  switch (state) {
    case ProcessingState.idle:
      return AudioProcessingState.idle;
    case ProcessingState.loading:
      return AudioProcessingState.loading;
    case ProcessingState.buffering:
      return AudioProcessingState.buffering;
    case ProcessingState.ready:
      return AudioProcessingState.ready;
    case ProcessingState.completed:
      return AudioProcessingState.completed;
  }
}

AudioServiceRepeatMode _repeatModeForLoopMode(LoopMode mode) {
  switch (mode) {
    case LoopMode.off:
      return AudioServiceRepeatMode.none;
    case LoopMode.one:
      return AudioServiceRepeatMode.one;
    case LoopMode.all:
      return AudioServiceRepeatMode.all;
  }
}

LoopMode _loopModeForRepeatMode(AudioServiceRepeatMode mode) {
  switch (mode) {
    case AudioServiceRepeatMode.one:
      return LoopMode.one;
    case AudioServiceRepeatMode.all:
    case AudioServiceRepeatMode.group:
      return LoopMode.all;
    case AudioServiceRepeatMode.none:
      return LoopMode.off;
  }
}
