import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sleep_timer_duration.dart';
import '../domain/playback_speed.dart';
import '../domain/replay_gain.dart';
import '../domain/track.dart';
import '../domain/track_queue.dart';
import 'offline_playback_policy.dart';
import 'playback_audio_effects.dart';
import 'playback_audio_engine.dart';

typedef TrackPlaybackResolver = Future<Track> Function(Track track);

class PlayerController extends ChangeNotifier {
  static const minVolume = 0.0;
  static const maxVolume = 1.0;
  static const supportedPlaybackSpeeds = supportedPlaybackSpeedValues;
  static const supportedSkipIntervals = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 45),
    Duration(seconds: 60),
  ];
  static const supportedCrossfadeDurations = <Duration>[
    Duration.zero,
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
  ];
  static const minLoudnessEnhancerGainDb = 0.0;
  static const maxLoudnessEnhancerGainDb = 12.0;

  PlayerController({
    PlaybackAudioEngine? audioEngine,
    TrackPlaybackResolver? trackResolver,
  })  : _audio = audioEngine ?? JustAudioPlaybackEngine(),
        _trackResolver = trackResolver {
    final crossfadeEngine = _audio;
    if (crossfadeEngine is CrossfadePlaybackAudioEngine &&
        crossfadeEngine.supportsCrossfade) {
      crossfadeEngine.setCrossfadeTrackVolumeResolver(_outputVolumeForTrack);
    }
    _playerStateSub = _audio.stateChanges.listen((_) => notifyListeners());
    _durationSub = _audio.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });
    _completedSub = _audio.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        unawaited(_handleTrackCompleted());
      }
    });
    _currentIndexSub = _audio.currentIndexStream.listen(
      _handleCurrentIndexChanged,
    );
  }

  static const _queueSnapshotKey = 'aethertune.player_queue.v1';
  static const _playbackSettingsKey = 'aethertune.playback_settings.v1';

  final PlaybackAudioEngine _audio;
  TrackPlaybackResolver? _trackResolver;
  final List<Track> _queue = <Track>[];
  final List<Track> _loadedPlaybackQueue = <Track>[];

  StreamSubscription<Object?>? _playerStateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<ProcessingState>? _completedSub;
  StreamSubscription<int?>? _currentIndexSub;
  Timer? _sleepTimer;
  Timer? _sleepFadeStartTimer;
  Timer? _sleepFadeStepTimer;
  Duration _duration = Duration.zero;
  Track? _current;
  String? _loadedTrackId;
  bool _stopAtEndOfTrack = false;
  bool _sleepTimerFadesOut = false;
  Duration _sleepTimerFadeDuration = defaultSleepTimerFadeDuration;
  bool _queueSnapshotLoaded = false;
  bool _playbackSettingsLoaded = false;
  bool _offlineModeEnabled = false;
  bool _isLoadingQueue = false;
  int _playbackStartSerial = 0;
  double? _sleepFadeStartVolume;
  double _volume = maxVolume;
  bool _loudnessNormalizationEnabled = false;
  ReplayGainMode _replayGainMode = ReplayGainMode.track;
  bool _equalizerEnabled = false;
  PlaybackEqualizerPreset _equalizerPreset = PlaybackEqualizerPreset.flat;
  List<PlaybackEqualizerPoint> _customEqualizerPoints =
      <PlaybackEqualizerPoint>[];
  List<PlaybackEqualizerBand> _equalizerBands = <PlaybackEqualizerBand>[];
  bool _equalizerBandsLoading = false;
  bool _loudnessEnhancerEnabled = false;
  double _loudnessEnhancerTargetGainDb = 0;
  double _defaultPlaybackSpeed = 1;
  Duration _skipBackwardInterval = const Duration(seconds: 10);
  Duration _skipForwardInterval = const Duration(seconds: 30);

  Track? get current => _current;
  List<Track> get queue => List.unmodifiable(_queue);
  int get playbackStartSerial => _playbackStartSerial;
  bool get isPlaying => _audio.playing;
  bool get shuffleEnabled => _audio.shuffleModeEnabled;
  LoopMode get loopMode => _audio.loopMode;
  double get playbackSpeed => _audio.speed;
  double get defaultPlaybackSpeed => _defaultPlaybackSpeed;
  Duration get skipBackwardInterval => _skipBackwardInterval;
  Duration get skipForwardInterval => _skipForwardInterval;
  double get volume => _volume;
  bool get loudnessNormalizationEnabled => _loudnessNormalizationEnabled;
  ReplayGainMode get replayGainMode => _replayGainMode;
  bool get supportsEqualizer =>
      _audio is AudioEffectsPlaybackAudioEngine && _audio.supportsEqualizer;
  bool get supportsLoudnessEnhancer =>
      _audio is AudioEffectsPlaybackAudioEngine &&
      _audio.supportsLoudnessEnhancer;
  bool get equalizerEnabled => _equalizerEnabled;
  PlaybackEqualizerPreset get equalizerPreset => _equalizerPreset;
  List<PlaybackEqualizerBand> get equalizerBands =>
      List<PlaybackEqualizerBand>.unmodifiable(_equalizerBands);
  bool get hasCustomEqualizerProfile => _customEqualizerPoints.isNotEmpty;
  bool get equalizerBandsLoading => _equalizerBandsLoading;
  bool get loudnessEnhancerEnabled => _loudnessEnhancerEnabled;
  double get loudnessEnhancerTargetGainDb => _loudnessEnhancerTargetGainDb;
  bool get supportsCrossfade =>
      _audio is CrossfadePlaybackAudioEngine &&
      _audio.supportsCrossfade;
  Duration get crossfadeDuration => _audio is CrossfadePlaybackAudioEngine
      ? _audio.crossfadeDuration
      : Duration.zero;
  Duration get duration => _duration;
  Duration get position => _audio.position;
  Stream<Duration> get positionStream => _audio.positionStream;
  Duration? get sleepTimerRemaining => _sleepTimer == null ? null : Duration.zero;
  bool get stopAtEndOfTrackEnabled => _stopAtEndOfTrack;
  bool get sleepTimerFadeOutEnabled => _sleepTimerFadesOut;
  Duration get sleepTimerFadeDuration => _sleepTimerFadeDuration;
  bool get isSleepFadeActive => _sleepFadeStepTimer != null;
  bool get offlineModeEnabled => _offlineModeEnabled;

  void setTrackResolver(TrackPlaybackResolver? resolver) {
    _trackResolver = resolver;
  }

  void setOfflineModeEnabled(bool enabled) {
    if (_offlineModeEnabled == enabled) {
      return;
    }

    _offlineModeEnabled = enabled;
    if (_offlineModeEnabled &&
        _current != null &&
        !offlineModeAllowsPlayback(
          _current!,
          offlineModeEnabled: _offlineModeEnabled,
        )) {
      _loadedTrackId = null;
      _loadedPlaybackQueue.clear();
      unawaited(_audio.stop());
    } else if (_current != null && _loadedPlaybackQueue.isNotEmpty) {
      unawaited(_reloadQueuePreservingPlayback());
    }
    notifyListeners();
  }

  Future<void> loadPersistedQueue() async {
    if (_queueSnapshotLoaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final rawSnapshot = prefs.getString(_queueSnapshotKey);
    if (rawSnapshot != null && rawSnapshot.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSnapshot) as Map;
        final snapshot = TrackQueueSnapshot.fromJson(
          Map<String, Object?>.from(decoded),
        );

        _queue
          ..clear()
          ..addAll(snapshot.tracks);
        _current = snapshot.currentTrack;
        _loadedTrackId = null;
        _loadedPlaybackQueue.clear();
      } catch (_) {
        await prefs.remove(_queueSnapshotKey);
      }
    }

    _queueSnapshotLoaded = true;
    notifyListeners();
  }

  Future<void> loadPersistedPlaybackSettings() async {
    if (_playbackSettingsLoaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final rawSettings = prefs.getString(_playbackSettingsKey);
    if (rawSettings != null && rawSettings.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSettings) as Map;
        final settings = Map<String, Object?>.from(decoded);
        await _audio.setShuffleModeEnabled(
          settings['shuffleEnabled'] as bool? ?? false,
        );
        await _audio.setLoopMode(
          _loopModeFromJson(settings['loopMode'] as String?),
        );
        _defaultPlaybackSpeed = _playbackSpeedFromJson(
          settings['playbackSpeed'],
        );
        await _audio.setSpeed(_defaultPlaybackSpeed);
        _skipBackwardInterval = _skipIntervalFromJson(
          settings['skipBackwardSeconds'],
          fallback: _skipBackwardInterval,
        );
        _skipForwardInterval = _skipIntervalFromJson(
          settings['skipForwardSeconds'],
          fallback: _skipForwardInterval,
        );
        _volume = _volumeFromJson(settings['volume']);
        _loudnessNormalizationEnabled =
            settings['loudnessNormalizationEnabled'] as bool? ?? false;
        _replayGainMode = _replayGainModeFromJson(settings['replayGainMode']);
        _equalizerEnabled = settings['equalizerEnabled'] as bool? ?? false;
        _equalizerPreset = _equalizerPresetFromJson(
          settings['equalizerPreset'],
        );
        _customEqualizerPoints = _equalizerPointsFromJson(
          settings['equalizerCustomPoints'],
        );
        if (_equalizerPreset == PlaybackEqualizerPreset.custom &&
            _customEqualizerPoints.isEmpty) {
          _equalizerPreset = PlaybackEqualizerPreset.flat;
        }
        _loudnessEnhancerEnabled =
            settings['loudnessEnhancerEnabled'] as bool? ?? false;
        _loudnessEnhancerTargetGainDb = _loudnessEnhancerGainFromJson(
          settings['loudnessEnhancerTargetGainDb'],
        );
        final crossfadeDuration = _crossfadeDurationFromJson(
          settings['crossfadeMilliseconds'],
        );
        if (supportsCrossfade) {
          await (_audio as CrossfadePlaybackAudioEngine)
              .setCrossfadeDuration(crossfadeDuration);
        }
        final audioEffectsEngine = _audioEffectsEngine;
        if (audioEffectsEngine != null &&
            audioEffectsEngine.supportsEqualizer) {
          await audioEffectsEngine.setEqualizerProfile(
            _currentEqualizerProfile,
          );
          await audioEffectsEngine.setEqualizerEnabled(_equalizerEnabled);
        }
        if (audioEffectsEngine != null &&
            audioEffectsEngine.supportsLoudnessEnhancer) {
          await audioEffectsEngine.setLoudnessEnhancerTargetGain(
            _loudnessEnhancerTargetGainDb,
          );
          await audioEffectsEngine.setLoudnessEnhancerEnabled(
            _loudnessEnhancerEnabled,
          );
        }
        await _applyOutputVolume();
      } catch (_) {
        await prefs.remove(_playbackSettingsKey);
      }
    }

    _playbackSettingsLoaded = true;
    notifyListeners();
  }

  Future<void> playTrack(
    Track track, {
    List<Track>? queue,
    Duration? initialPosition,
  }) async {
    if (_offlineModeEnabled) {
      requireOfflineModePlaybackAllowed(
        track,
        offlineModeEnabled: true,
      );
    }

    final preparedTrack = await _prepareQueueForPlayback(track, queue: queue);
    requireOfflineModePlaybackAllowed(
      preparedTrack,
      offlineModeEnabled: _offlineModeEnabled,
    );

    _current = preparedTrack;
    notifyListeners();
    await _saveQueueSnapshot();

    await _loadQueue(
      preparedTrack,
      initialPosition: initialPosition ?? Duration.zero,
    );
    await _applyOutputVolume();
    unawaited(_audio.play());
    _playbackStartSerial += 1;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_current == null) {
      return;
    }

    if (_audio.playing) {
      await _audio.pause();
    } else {
      if (_offlineModeEnabled) {
        requireOfflineModePlaybackAllowed(
          _current!,
          offlineModeEnabled: true,
        );
      }

      final preparedTrack = await _prepareQueueForPlayback(_current!);
      _current = preparedTrack;
      requireOfflineModePlaybackAllowed(
        preparedTrack,
        offlineModeEnabled: _offlineModeEnabled,
      );

      final wasLoaded = _loadedTrackId == preparedTrack.id;
      if (!wasLoaded) {
        await _saveQueueSnapshot();
        await _loadQueue(preparedTrack);
      }
      await _applyOutputVolume();

      unawaited(_audio.play());
      if (!wasLoaded) {
        _playbackStartSerial += 1;
      }
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _cancelSleepFadeSteps(restoreVolume: true);
    await _audio.stop();
    notifyListeners();
  }

  Future<void> removeTracksFromSource(String sourceId) async {
    final removesCurrent = _current?.sourceId == sourceId;
    _queue.removeWhere((track) => track.sourceId == sourceId);
    if (removesCurrent) {
      await _audio.stop();
      _current = null;
      _loadedTrackId = null;
      _loadedPlaybackQueue.clear();
    } else if (_current != null) {
      await _reloadQueuePreservingPlayback();
    }
    await _saveQueueSnapshot();
    notifyListeners();
  }

  Future<void> refreshTracksFromSource(String sourceId) async {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty ||
        !_queue.any((track) => track.sourceId == normalizedSourceId)) {
      return;
    }

    final currentTrackId = _current?.id;
    final hadLoadedQueue = _loadedPlaybackQueue.isNotEmpty;
    final wasPlaying = hadLoadedQueue && _audio.playing;
    final position = hadLoadedQueue ? _audio.position : Duration.zero;
    if (hadLoadedQueue) {
      await _audio.stop();
      _loadedTrackId = null;
      _loadedPlaybackQueue.clear();
    }
    final sanitized = _queue
        .map(
          (track) => track.sourceId == normalizedSourceId
              ? track.withoutEphemeralMediaUris()
              : track,
        )
        .toList(growable: false);
    final resolver = _trackResolver;
    final refreshed = resolver == null
        ? sanitized
        : await Future.wait(
            sanitized.map((track) async {
              if (track.sourceId != normalizedSourceId ||
                  track.hasLocalSource) {
                return track;
              }
              try {
                return await resolver(track);
              } on Object catch (error) {
                debugPrint(
                  'Could not refresh ${track.title} after credential rotation: '
                  '$error',
                );
                return track;
              }
            }),
          );

    _queue
      ..clear()
      ..addAll(refreshed);
    if (currentTrackId != null) {
      final currentIndex = _queue.indexWhere(
        (track) => track.id == currentTrackId,
      );
      _current = currentIndex == -1 ? null : _queue[currentIndex];
    }
    await _saveQueueSnapshot();

    final current = _current;
    if (current == null || !current.isPlayable) {
      if (!hadLoadedQueue) {
        await _audio.stop();
      }
      _loadedTrackId = null;
      _loadedPlaybackQueue.clear();
    } else if (hadLoadedQueue) {
      try {
        await _loadQueue(
          current,
          initialPosition: position,
          forceReload: true,
        );
        if (wasPlaying) {
          unawaited(_audio.play());
        }
      } on Object catch (error) {
        debugPrint(
          'Could not reload playback after credential rotation: $error',
        );
      }
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _audio.seek(position);
  }

  Future<void> seekBy(Duration offset) async {
    var target = position + offset;
    if (target.isNegative) {
      target = Duration.zero;
    }
    if (duration > Duration.zero && target > duration) {
      target = duration;
    }
    await seek(target);
  }

  Future<void> skipBackward() => seekBy(-_skipBackwardInterval);

  Future<void> skipForward() => seekBy(_skipForwardInterval);

  Future<void> next() async {
    if (_queue.isEmpty || _current == null) {
      await stop();
      return;
    }

    if (_loadedPlaybackQueue.isNotEmpty &&
        _loadedPlaybackQueue.any((track) => track.id == _current!.id)) {
      if (_audio.hasNext) {
        await _audio.seekToNext();
        unawaited(_audio.play());
        return;
      }
      if (_audio.loopMode == LoopMode.all) {
        await _audio.seek(Duration.zero, index: 0);
        unawaited(_audio.play());
        return;
      }
    }

    final index = _queue.indexWhere((track) => track.id == _current!.id);
    if (index == -1) {
      await stop();
      return;
    }

    final nextTrack = _nextPlayableTrack(
      index + 1,
      wrap: _audio.loopMode == LoopMode.all,
    );
    if (nextTrack != null) {
      await playTrack(nextTrack);
      return;
    }

    await stop();
  }

  Future<void> previous() async {
    if (_queue.isEmpty || _current == null) {
      return;
    }

    if (_loadedPlaybackQueue.isNotEmpty &&
        _loadedPlaybackQueue.any((track) => track.id == _current!.id) &&
        _audio.hasPrevious) {
      await _audio.seekToPrevious();
      unawaited(_audio.play());
      return;
    }

    final index = _queue.indexWhere((track) => track.id == _current!.id);
    final previousTrack = _previousPlayableTrack(index - 1);
    if (previousTrack != null) {
      await playTrack(previousTrack);
    }
  }

  void moveTrackInQueue(int fromIndex, int toIndex) {
    final reordered = moveQueueItem(_queue, fromIndex, toIndex);
    if (_sameQueueOrder(_queue, reordered)) {
      return;
    }

    _queue
      ..clear()
      ..addAll(reordered);
    unawaited(_saveQueueSnapshot());
    unawaited(_reloadQueuePreservingPlayback());
    notifyListeners();
  }

  void removeTrackFromQueue(String trackId) {
    if (_current?.id == trackId) {
      return;
    }

    final remaining = removeTrackFromQueueItems(_queue, trackId);
    if (_sameQueueOrder(_queue, remaining)) {
      return;
    }

    _queue
      ..clear()
      ..addAll(remaining);
    unawaited(_saveQueueSnapshot());
    unawaited(_reloadQueuePreservingPlayback());
    notifyListeners();
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    await _audio.setShuffleModeEnabled(enabled);
    await _savePlaybackSettings();
    notifyListeners();
  }

  Future<void> setLoopMode(LoopMode mode) async {
    await _audio.setLoopMode(mode);
    await _savePlaybackSettings();
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _requireSupportedPlaybackSpeed(speed);
    _defaultPlaybackSpeed = speed;
    await _audio.setSpeed(speed);
    await _savePlaybackSettings();
    notifyListeners();
  }

  Future<void> setTemporaryPlaybackSpeed(double speed) async {
    _requireSupportedPlaybackSpeed(speed);
    if (_audio.speed == speed) {
      return;
    }
    await _audio.setSpeed(speed);
    notifyListeners();
  }

  Future<void> setSkipBackwardInterval(Duration interval) async {
    _requireSupportedSkipInterval(interval);
    if (_skipBackwardInterval == interval) {
      return;
    }
    _skipBackwardInterval = interval;
    await _savePlaybackSettings();
    notifyListeners();
  }

  Future<void> setSkipForwardInterval(Duration interval) async {
    _requireSupportedSkipInterval(interval);
    if (_skipForwardInterval == interval) {
      return;
    }
    _skipForwardInterval = interval;
    await _savePlaybackSettings();
    notifyListeners();
  }

  Future<void> previewVolume(double volume) async {
    _validateVolume(volume);
    _volume = volume;
    await _applyOutputVolume();
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    await previewVolume(volume);
    await _savePlaybackSettings();
  }

  Future<void> setLoudnessNormalizationEnabled(bool enabled) async {
    _loudnessNormalizationEnabled = enabled;
    await _applyOutputVolume();
    await _savePlaybackSettings();
    notifyListeners();
  }

  Future<void> setReplayGainMode(ReplayGainMode mode) async {
    _replayGainMode = mode;
    await _applyOutputVolume();
    await _savePlaybackSettings();
    notifyListeners();
  }

  Future<void> setCrossfadeDuration(Duration duration) async {
    if (!supportedCrossfadeDurations.contains(duration)) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Crossfade duration is not supported.',
      );
    }
    if (!supportsCrossfade) {
      throw UnsupportedError('Crossfade is unavailable for this audio backend.');
    }
    await (_audio as CrossfadePlaybackAudioEngine).setCrossfadeDuration(
      duration,
    );
    await _savePlaybackSettings();
    notifyListeners();
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    final engine = _requireEqualizerEngine();
    if (_equalizerEnabled == enabled) {
      return;
    }
    final previous = _equalizerEnabled;
    _equalizerEnabled = enabled;
    notifyListeners();
    try {
      await engine.setEqualizerEnabled(enabled);
      await _savePlaybackSettings();
    } on Object {
      _equalizerEnabled = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setEqualizerPreset(PlaybackEqualizerPreset preset) async {
    final engine = _requireEqualizerEngine();
    if (preset == PlaybackEqualizerPreset.custom &&
        _customEqualizerPoints.isEmpty) {
      throw StateError('Custom equalizer bands are not available yet.');
    }
    if (_equalizerPreset == preset) {
      return;
    }
    final previous = _equalizerPreset;
    _equalizerPreset = preset;
    notifyListeners();
    try {
      await engine.setEqualizerProfile(_currentEqualizerProfile);
      await _refreshEqualizerBands(notify: false);
      await _savePlaybackSettings();
      notifyListeners();
    } on Object {
      _equalizerPreset = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> refreshEqualizerBands() {
    return _refreshEqualizerBands(notify: true);
  }

  Future<void> previewEqualizerBandGain(int bandIndex, double gainDb) async {
    final engine = _requireEqualizerEngine();
    final index = _equalizerBands.indexWhere((band) => band.index == bandIndex);
    if (index == -1) {
      throw RangeError.value(bandIndex, 'bandIndex', 'Unknown equalizer band.');
    }
    final band = _equalizerBands[index];
    if (!gainDb.isFinite ||
        gainDb < band.minGainDb ||
        gainDb > band.maxGainDb) {
      throw ArgumentError.value(
        gainDb,
        'gainDb',
        'Gain is outside the device band range.',
      );
    }

    final previousBands = List<PlaybackEqualizerBand>.from(_equalizerBands);
    final previousPreset = _equalizerPreset;
    final previousPoints = _customEqualizerPoints;
    _equalizerBands[index] = band.copyWith(gainDb: gainDb);
    _equalizerPreset = PlaybackEqualizerPreset.custom;
    _customEqualizerPoints = _equalizerBands
        .map(
          (item) => PlaybackEqualizerPoint(
            frequencyHz: item.centerFrequencyHz,
            gainDb: item.gainDb,
          ),
        )
        .toList(growable: false);
    notifyListeners();
    try {
      await engine.setEqualizerProfile(_currentEqualizerProfile);
    } on Object {
      _equalizerBands = previousBands;
      _equalizerPreset = previousPreset;
      _customEqualizerPoints = previousPoints;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> persistEqualizerBandGains() => _savePlaybackSettings();

  Future<void> setLoudnessEnhancerEnabled(bool enabled) async {
    final engine = _requireLoudnessEnhancerEngine();
    if (_loudnessEnhancerEnabled == enabled) {
      return;
    }
    final previous = _loudnessEnhancerEnabled;
    _loudnessEnhancerEnabled = enabled;
    notifyListeners();
    try {
      await engine.setLoudnessEnhancerEnabled(enabled);
      await _savePlaybackSettings();
    } on Object {
      _loudnessEnhancerEnabled = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> previewLoudnessEnhancerTargetGain(double gainDb) async {
    final engine = _requireLoudnessEnhancerEngine();
    _validateLoudnessEnhancerGain(gainDb);
    final previous = _loudnessEnhancerTargetGainDb;
    _loudnessEnhancerTargetGainDb = gainDb;
    notifyListeners();
    try {
      await engine.setLoudnessEnhancerTargetGain(gainDb);
    } on Object {
      _loudnessEnhancerTargetGainDb = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setLoudnessEnhancerTargetGain(double gainDb) async {
    await previewLoudnessEnhancerTargetGain(gainDb);
    await _savePlaybackSettings();
  }

  static String formatVolume(double volume) {
    final percent = (volume.clamp(minVolume, maxVolume) * 100).round();
    return '$percent%';
  }

  void startSleepTimer(
    Duration duration, {
    bool fadeOut = false,
    Duration fadeDuration = defaultSleepTimerFadeDuration,
  }) {
    final restoreGaplessQueue = _stopAtEndOfTrack;
    _cancelSleepTimerState(restoreVolume: true);
    _stopAtEndOfTrack = false;
    _sleepTimerFadesOut = fadeOut;
    _sleepTimerFadeDuration = fadeDuration;
    _sleepTimer = Timer(duration, () async {
      _sleepTimer = null;
      _sleepTimerFadesOut = false;
      await _stopForSleepTimer(restoreVolume: fadeOut);
    });

    if (fadeOut) {
      _sleepFadeStartTimer = Timer(
        sleepTimerFadeStartDelay(duration, fadeDuration: fadeDuration),
        () => _startSleepFade(fadeDuration),
      );
    }
    if (restoreGaplessQueue) {
      unawaited(_reloadQueuePreservingPlayback());
    }
    notifyListeners();
  }

  void stopAtEndOfTrack() {
    _cancelSleepTimerState(restoreVolume: true);
    _stopAtEndOfTrack = true;
    unawaited(_isolateCurrentTrackUntilCompletion());
    notifyListeners();
  }

  void cancelSleepTimer() {
    final restoreGaplessQueue = _stopAtEndOfTrack;
    _cancelSleepTimerState(restoreVolume: true);
    _stopAtEndOfTrack = false;
    if (restoreGaplessQueue) {
      unawaited(_reloadQueuePreservingPlayback());
    }
    notifyListeners();
  }

  Future<void> _handleTrackCompleted() async {
    if (_stopAtEndOfTrack) {
      _stopAtEndOfTrack = false;
      await stop();
      return;
    }

    await next();
  }

  void _handleCurrentIndexChanged(int? index) {
    if (_isLoadingQueue ||
        index == null ||
        index < 0 ||
        index >= _loadedPlaybackQueue.length) {
      return;
    }

    final track = _loadedPlaybackQueue[index];
    _loadedTrackId = track.id;
    if (_current?.id == track.id) {
      return;
    }

    _current = track;
    _playbackStartSerial += 1;
    unawaited(_applyOutputVolume());
    unawaited(_saveQueueSnapshot());
    notifyListeners();
  }

  void _startSleepFade(Duration fadeDuration) {
    _sleepFadeStartTimer = null;
    _sleepFadeStepTimer?.cancel();
    final stepInterval = sleepTimerFadeStepInterval(fadeDuration);
    if (stepInterval <= Duration.zero) {
      unawaited(_audio.setVolume(0));
      return;
    }

    var step = 0;
    _sleepFadeStartVolume = _volume;
    _sleepFadeStepTimer = Timer.periodic(stepInterval, (timer) {
      step += 1;
      unawaited(
        _applyOutputVolume(
          baseVolume: sleepTimerFadeVolume(
            startVolume: _sleepFadeStartVolume ?? _volume,
            step: step,
          ),
        ),
      );

      if (step >= sleepTimerFadeSteps) {
        timer.cancel();
        _sleepFadeStepTimer = null;
      }
    });
  }

  Future<void> _stopForSleepTimer({required bool restoreVolume}) async {
    final startVolume = _sleepFadeStartVolume;
    _cancelSleepFade(restoreVolume: false);
    await _audio.stop();
    if (restoreVolume && startVolume != null) {
      await _applyOutputVolume(baseVolume: startVolume);
    }
    notifyListeners();
  }

  void _cancelSleepTimerState({required bool restoreVolume}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerFadesOut = false;
    _sleepFadeStartTimer?.cancel();
    _sleepFadeStartTimer = null;
    _cancelSleepFade(restoreVolume: restoreVolume);
  }

  void _cancelSleepFade({required bool restoreVolume}) {
    _sleepFadeStartTimer?.cancel();
    _sleepFadeStartTimer = null;
    _cancelSleepFadeSteps(restoreVolume: restoreVolume);
  }

  void _cancelSleepFadeSteps({required bool restoreVolume}) {
    _sleepFadeStepTimer?.cancel();
    _sleepFadeStepTimer = null;
    final startVolume = _sleepFadeStartVolume;
    _sleepFadeStartVolume = null;
    if (restoreVolume && startVolume != null) {
      unawaited(_applyOutputVolume(baseVolume: startVolume));
    }
  }

  Future<void> _loadQueue(
    Track track, {
    Duration initialPosition = Duration.zero,
    bool forceReload = false,
  }) async {
    final playbackQueue = _playbackQueueForCurrentMode();
    final index = playbackQueue.indexWhere((item) => item.id == track.id);
    if (index == -1) {
      throw StateError('Track is not playable in the current mode: ${track.title}');
    }

    if (!forceReload && _sameQueueOrder(_loadedPlaybackQueue, playbackQueue)) {
      await _audio.seek(initialPosition, index: index);
      _loadedTrackId = track.id;
      return;
    }

    _loadedPlaybackQueue
      ..clear()
      ..addAll(playbackQueue);
    _isLoadingQueue = true;
    try {
      await _audio.setQueue(
        playbackQueue,
        initialIndex: index,
        initialPosition: initialPosition,
      );
      await _refreshEqualizerBands(notify: false);
      _loadedTrackId = track.id;
    } on Object {
      _loadedPlaybackQueue.clear();
      _loadedTrackId = null;
      rethrow;
    } finally {
      _isLoadingQueue = false;
    }
  }

  Future<Track> _prepareQueueForPlayback(
    Track track, {
    List<Track>? queue,
  }) async {
    final candidates = queue == null
        ? List<Track>.from(_queue)
        : List<Track>.from(queue);
    final existingIndex = candidates.indexWhere((item) => item.id == track.id);
    if (existingIndex == -1) {
      candidates.add(track);
    } else {
      candidates[existingIndex] = track;
    }

    final resolver = _trackResolver;
    final prepared = resolver == null
        ? candidates
        : await Future.wait(
            candidates.map(
              (item) =>
                  item.isPlayable ? Future<Track>.value(item) : resolver(item),
            ),
          );
    final preparedTrack = prepared.firstWhere(
      (item) => item.id == track.id,
      orElse: () => track,
    );
    _queue
      ..clear()
      ..addAll(prepared);
    return preparedTrack;
  }

  List<Track> _playbackQueueForCurrentMode() {
    return _queue
        .where(
          (track) =>
              (track.hasLocalSource || track.hasStreamSource) &&
              offlineModeAllowsPlayback(
                track,
                offlineModeEnabled: _offlineModeEnabled,
              ),
        )
        .toList(growable: false);
  }

  Future<void> _reloadQueuePreservingPlayback() async {
    final track = _current;
    if (track == null ||
        !offlineModeAllowsPlayback(
          track,
          offlineModeEnabled: _offlineModeEnabled,
        )) {
      return;
    }

    final wasPlaying = _audio.playing;
    final position = _audio.position;
    try {
      await _loadQueue(
        track,
        initialPosition: position,
        forceReload: true,
      );
      if (wasPlaying) {
        unawaited(_audio.play());
      }
    } on Object catch (error) {
      debugPrint('Could not rebuild gapless queue: $error');
    }
  }

  Future<void> _isolateCurrentTrackUntilCompletion() async {
    final track = _current;
    if (track == null || _loadedTrackId != track.id) {
      return;
    }

    final wasPlaying = _audio.playing;
    final position = _audio.position;
    _loadedPlaybackQueue
      ..clear()
      ..add(track);
    _isLoadingQueue = true;
    try {
      await _audio.setQueue(
        <Track>[track],
        initialIndex: 0,
        initialPosition: position,
      );
      await _refreshEqualizerBands(notify: false);
      if (wasPlaying) {
        unawaited(_audio.play());
      }
    } on Object catch (error) {
      debugPrint('Could not isolate sleep-timer track: $error');
    } finally {
      _isLoadingQueue = false;
    }
  }

  Future<void> _saveQueueSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    if (_queue.isEmpty) {
      await prefs.remove(_queueSnapshotKey);
      return;
    }

    final snapshot = TrackQueueSnapshot(
      tracks: _queue,
      currentTrackId: _current?.id,
    );
    await prefs.setString(_queueSnapshotKey, jsonEncode(snapshot.toJson()));
  }

  Future<void> _savePlaybackSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _playbackSettingsKey,
      jsonEncode(
        <String, Object?>{
          'shuffleEnabled': _audio.shuffleModeEnabled,
          'loopMode': _loopModeToJson(_audio.loopMode),
          'playbackSpeed': _defaultPlaybackSpeed,
          'skipBackwardSeconds': _skipBackwardInterval.inSeconds,
          'skipForwardSeconds': _skipForwardInterval.inSeconds,
          'volume': _volume,
          'loudnessNormalizationEnabled': _loudnessNormalizationEnabled,
          'replayGainMode': _replayGainMode.name,
          'crossfadeMilliseconds': crossfadeDuration.inMilliseconds,
          'equalizerEnabled': _equalizerEnabled,
          'equalizerPreset': _equalizerPreset.name,
          'equalizerCustomPoints': _customEqualizerPoints
              .map((point) => point.toJson())
              .toList(growable: false),
          'loudnessEnhancerEnabled': _loudnessEnhancerEnabled,
          'loudnessEnhancerTargetGainDb': _loudnessEnhancerTargetGainDb,
        },
      ),
    );
  }

  LoopMode _loopModeFromJson(String? value) {
    switch (value) {
      case 'one':
        return LoopMode.one;
      case 'all':
        return LoopMode.all;
      case 'off':
      default:
        return LoopMode.off;
    }
  }

  String _loopModeToJson(LoopMode mode) {
    switch (mode) {
      case LoopMode.one:
        return 'one';
      case LoopMode.all:
        return 'all';
      case LoopMode.off:
        return 'off';
    }
  }

  double _playbackSpeedFromJson(Object? value) {
    if (value is num) {
      final speed = value.toDouble();
      if (supportedPlaybackSpeeds.contains(speed)) {
        return speed;
      }
    }
    return 1;
  }

  void _requireSupportedPlaybackSpeed(double speed) {
    if (!isSupportedPlaybackSpeed(speed)) {
      throw ArgumentError.value(
        speed,
        'speed',
        'Playback speed must be one of the supported values.',
      );
    }
  }

  Duration _skipIntervalFromJson(
    Object? value, {
    required Duration fallback,
  }) {
    if (value is num) {
      final interval = Duration(seconds: value.round());
      if (supportedSkipIntervals.contains(interval)) {
        return interval;
      }
    }
    return fallback;
  }

  void _requireSupportedSkipInterval(Duration interval) {
    if (!supportedSkipIntervals.contains(interval)) {
      throw ArgumentError.value(
        interval,
        'interval',
        'Skip interval must be one of the supported values.',
      );
    }
  }

  double _volumeFromJson(Object? value) {
    if (value is num) {
      final volume = value.toDouble();
      if (volume >= minVolume && volume <= maxVolume) {
        return volume;
      }
    }
    return maxVolume;
  }

  Future<void> _applyOutputVolume({double? baseVolume}) {
    return _audio.setVolume(_outputVolumeForTrack(_current, baseVolume));
  }

  double _outputVolumeForTrack(Track? track, [double? baseVolume]) {
    return replayGainAdjustedVolume(
      baseVolume: baseVolume ?? _volume,
      enabled: _loudnessNormalizationEnabled,
      gainDb: replayGainForMode(
        mode: _replayGainMode,
        trackGainDb: track?.replayGainTrackDb,
        albumGainDb: track?.replayGainAlbumDb,
      ),
    );
  }

  ReplayGainMode _replayGainModeFromJson(Object? value) {
    return switch (value) {
      'album' => ReplayGainMode.album,
      _ => ReplayGainMode.track,
    };
  }

  Duration _crossfadeDurationFromJson(Object? value) {
    if (value is num) {
      final duration = Duration(milliseconds: value.round());
      if (supportedCrossfadeDurations.contains(duration)) {
        return duration;
      }
    }
    return Duration.zero;
  }

  AudioEffectsPlaybackAudioEngine? get _audioEffectsEngine {
    final engine = _audio;
    return engine is AudioEffectsPlaybackAudioEngine ? engine : null;
  }

  PlaybackEqualizerProfile get _currentEqualizerProfile =>
      PlaybackEqualizerProfile(
        preset: _equalizerPreset,
        customPoints: _customEqualizerPoints,
      );

  AudioEffectsPlaybackAudioEngine _requireEqualizerEngine() {
    final engine = _audioEffectsEngine;
    if (engine == null || !engine.supportsEqualizer) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    return engine;
  }

  AudioEffectsPlaybackAudioEngine _requireLoudnessEnhancerEngine() {
    final engine = _audioEffectsEngine;
    if (engine == null || !engine.supportsLoudnessEnhancer) {
      throw UnsupportedError(
        'Loudness enhancer is unavailable for this audio backend.',
      );
    }
    return engine;
  }

  Future<void> _refreshEqualizerBands({required bool notify}) async {
    final engine = _audioEffectsEngine;
    if (engine == null || !engine.supportsEqualizer) {
      if (_equalizerBands.isNotEmpty) {
        _equalizerBands = <PlaybackEqualizerBand>[];
        if (notify) {
          notifyListeners();
        }
      }
      return;
    }

    _equalizerBandsLoading = true;
    if (notify) {
      notifyListeners();
    }
    try {
      _equalizerBands = await engine.loadEqualizerBands();
    } finally {
      _equalizerBandsLoading = false;
      if (notify) {
        notifyListeners();
      }
    }
  }

  PlaybackEqualizerPreset _equalizerPresetFromJson(Object? value) {
    return switch (value) {
      'bassBoost' => PlaybackEqualizerPreset.bassBoost,
      'vocal' => PlaybackEqualizerPreset.vocal,
      'treble' => PlaybackEqualizerPreset.treble,
      'custom' => PlaybackEqualizerPreset.custom,
      _ => PlaybackEqualizerPreset.flat,
    };
  }

  List<PlaybackEqualizerPoint> _equalizerPointsFromJson(Object? value) {
    if (value is! List) {
      return <PlaybackEqualizerPoint>[];
    }
    final points = <PlaybackEqualizerPoint>[];
    for (final entry in value) {
      if (entry is! Map) {
        continue;
      }
      final frequency = entry['frequencyHz'];
      final gain = entry['gainDb'];
      if (frequency is! num || gain is! num) {
        continue;
      }
      final frequencyHz = frequency.toDouble();
      final gainDb = gain.toDouble();
      if (!frequencyHz.isFinite ||
          frequencyHz <= 0 ||
          !gainDb.isFinite ||
          gainDb < -24 ||
          gainDb > 24) {
        continue;
      }
      points.add(
        PlaybackEqualizerPoint(
          frequencyHz: frequencyHz,
          gainDb: gainDb,
        ),
      );
    }
    points.sort(
      (left, right) => left.frequencyHz.compareTo(right.frequencyHz),
    );
    return points;
  }

  double _loudnessEnhancerGainFromJson(Object? value) {
    if (value is num) {
      final gain = value.toDouble();
      if (gain.isFinite &&
          gain >= minLoudnessEnhancerGainDb &&
          gain <= maxLoudnessEnhancerGainDb) {
        return gain;
      }
    }
    return minLoudnessEnhancerGainDb;
  }

  void _validateLoudnessEnhancerGain(double gainDb) {
    if (!gainDb.isFinite ||
        gainDb < minLoudnessEnhancerGainDb ||
        gainDb > maxLoudnessEnhancerGainDb) {
      throw ArgumentError.value(
        gainDb,
        'gainDb',
        'Loudness enhancer gain must be between 0 and 12 dB.',
      );
    }
  }

  void _validateVolume(double volume) {
    if (!volume.isFinite || volume < minVolume || volume > maxVolume) {
      throw ArgumentError.value(
        volume,
        'volume',
        'Volume must be between 0 and 1.',
      );
    }
  }

  bool _sameQueueOrder(List<Track> left, List<Track> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index += 1) {
      if (left[index].id != right[index].id) {
        return false;
      }
    }

    return true;
  }

  Track? _nextPlayableTrack(int startIndex, {required bool wrap}) {
    if (_queue.isEmpty) {
      return null;
    }

    var index = startIndex;
    var checked = 0;
    while (checked < _queue.length) {
      if (index >= _queue.length) {
        if (!wrap) {
          return null;
        }
        index = 0;
      }

      final track = _queue[index];
      if ((track.hasLocalSource || track.hasStreamSource) &&
          offlineModeAllowsPlayback(
            track,
            offlineModeEnabled: _offlineModeEnabled,
          )) {
        return track;
      }

      index += 1;
      checked += 1;
    }

    return null;
  }

  Track? _previousPlayableTrack(int startIndex) {
    for (var index = startIndex; index >= 0; index -= 1) {
      final track = _queue[index];
      if ((track.hasLocalSource || track.hasStreamSource) &&
          offlineModeAllowsPlayback(
            track,
            offlineModeEnabled: _offlineModeEnabled,
          )) {
        return track;
      }
    }

    return null;
  }

  @override
  void dispose() {
    _cancelSleepTimerState(restoreVolume: false);
    _playerStateSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _currentIndexSub?.cancel();
    unawaited(_audio.dispose());
    super.dispose();
  }
}
