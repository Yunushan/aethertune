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
  static const supportedPlaybackPitches = <double>[
    0.5,
    0.75,
    1,
    1.25,
    1.5,
    2,
  ];
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
  static const minABRepeatDuration = Duration(milliseconds: 500);
  static const minLoudnessEnhancerGainDb = 0.0;
  static const maxLoudnessEnhancerGainDb = 12.0;
  static const minVirtualizerStrength = 0;
  static const maxVirtualizerStrength = 1000;

  PlayerController({
    PlaybackAudioEngine? audioEngine,
    TrackPlaybackResolver? trackResolver,
    DateTime Function()? clock,
  })  : _audio = audioEngine ?? JustAudioPlaybackEngine(),
        _trackResolver = trackResolver,
        _clock = clock ?? DateTime.now {
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
    _positionSub = _audio.positionStream.listen(_handleABRepeatPosition);
    _completedSub = _audio.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        unawaited(_handleTrackCompleted());
      }
    });
    _currentIndexSub = _audio.currentIndexStream.listen(
      _handleCurrentIndexChanged,
    );
    final errorEngine = _audio;
    if (errorEngine is PlaybackErrorAudioEngine) {
      final playbackErrorEngine = errorEngine as PlaybackErrorAudioEngine;
      _errorSub = playbackErrorEngine.errorStream.listen((_) {
        unawaited(_handlePlaybackError());
      });
    }
    _savedQueues.add(_emptySavedQueue());
  }

  static const _queueSnapshotKey = 'aethertune.player_queue.v1';
  static const _savedQueuesSnapshotKey = 'aethertune.player_queues.v2';
  static const _playbackSettingsKey = 'aethertune.playback_settings.v1';
  static const _defaultQueueId = 'default';
  static const _defaultQueueName = 'Queue 1';

  final PlaybackAudioEngine _audio;
  TrackPlaybackResolver? _trackResolver;
  final DateTime Function() _clock;
  final List<Track> _queue = <Track>[];
  final List<Track> _loadedPlaybackQueue = <Track>[];
  final List<SavedTrackQueue> _savedQueues = <SavedTrackQueue>[];

  StreamSubscription<Object?>? _playerStateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<ProcessingState>? _completedSub;
  StreamSubscription<int?>? _currentIndexSub;
  StreamSubscription<Object>? _errorSub;
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
  DateTime? _queueUpdatedAt;
  String _activeQueueId = _defaultQueueId;
  int _nextSavedQueueSerial = 0;
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
  bool _virtualizerEnabled = false;
  int _virtualizerStrength = 500;
  bool _skipSilenceEnabled = false;
  bool _skipFailedTracksEnabled = true;
  final Set<String> _failedTrackIds = <String>{};
  bool _handlingPlaybackError = false;
  double _defaultPlaybackSpeed = 1;
  double _defaultPlaybackPitch = 1;
  final Map<String, double> _trackPlaybackPitchOverrides = <String, double>{};
  Duration _skipBackwardInterval = const Duration(seconds: 10);
  Duration _skipForwardInterval = const Duration(seconds: 30);
  Duration? _aBRepeatStart;
  Duration? _aBRepeatEnd;
  bool _aBRepeatSeeking = false;

  Track? get current => _current;
  List<Track> get queue => List.unmodifiable(_queue);
  List<SavedTrackQueue> get savedQueues =>
      List<SavedTrackQueue>.unmodifiable(_savedQueues);
  String get activeQueueId => _activeQueueId;
  String get activeQueueName => _activeSavedQueue.name;
  int get playbackStartSerial => _playbackStartSerial;
  bool get isPlaying => _audio.playing;
  bool get shuffleEnabled => _audio.shuffleModeEnabled;
  LoopMode get loopMode => _audio.loopMode;
  double get playbackSpeed => _audio.speed;
  double get defaultPlaybackSpeed => _defaultPlaybackSpeed;
  bool get supportsPitch =>
      _audio is PitchPlaybackAudioEngine && _audio.supportsPitch;
  double get playbackPitch => _audio is PitchPlaybackAudioEngine
      ? _audio.pitch
      : _defaultPlaybackPitch;
  double get defaultPlaybackPitch => _defaultPlaybackPitch;
  Map<String, double> get trackPlaybackPitchOverrides =>
      Map<String, double>.unmodifiable(_trackPlaybackPitchOverrides);
  Duration get skipBackwardInterval => _skipBackwardInterval;
  Duration get skipForwardInterval => _skipForwardInterval;
  Duration? get aBRepeatStart => _aBRepeatStart;
  Duration? get aBRepeatEnd => _aBRepeatEnd;
  bool get hasABRepeatStart => _aBRepeatStart != null;
  bool get isABRepeatActive =>
      _aBRepeatStart != null && _aBRepeatEnd != null;
  double get volume => _volume;
  bool get loudnessNormalizationEnabled => _loudnessNormalizationEnabled;
  ReplayGainMode get replayGainMode => _replayGainMode;
  bool get supportsEqualizer =>
      _audio is AudioEffectsPlaybackAudioEngine && _audio.supportsEqualizer;
  bool get supportsLoudnessEnhancer =>
      _audio is AudioEffectsPlaybackAudioEngine &&
      _audio.supportsLoudnessEnhancer;
  bool get supportsVirtualizer =>
      _audio is VirtualizerPlaybackAudioEngine && _audio.supportsVirtualizer;
  bool get supportsSkipSilence =>
      _audio is SkipSilencePlaybackAudioEngine && _audio.supportsSkipSilence;
  bool get skipSilenceEnabled => _skipSilenceEnabled;
  bool get skipFailedTracksEnabled => _skipFailedTracksEnabled;
  bool get supportsVisualizer =>
      _audio is AudioVisualizationPlaybackAudioEngine &&
      _audio.supportsVisualizer;
  Stream<List<double>> get visualizerBands =>
      _audio is AudioVisualizationPlaybackAudioEngine
      ? _audio.visualizerBands
      : const Stream<List<double>>.empty();
  bool get equalizerEnabled => _equalizerEnabled;
  PlaybackEqualizerPreset get equalizerPreset => _equalizerPreset;
  List<PlaybackEqualizerBand> get equalizerBands =>
      List<PlaybackEqualizerBand>.unmodifiable(_equalizerBands);
  bool get hasCustomEqualizerProfile => _customEqualizerPoints.isNotEmpty;
  bool get equalizerBandsLoading => _equalizerBandsLoading;
  bool get loudnessEnhancerEnabled => _loudnessEnhancerEnabled;
  double get loudnessEnhancerTargetGainDb => _loudnessEnhancerTargetGainDb;
  bool get virtualizerEnabled => _virtualizerEnabled;
  int get virtualizerStrength => _virtualizerStrength;
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

  /// Publishes the current app library to supported system-media browsers.
  ///
  /// Browsing is intentionally delegated back to [playTrack] so a selection
  /// obeys the same offline policy, provider resolution, queue persistence,
  /// and output settings as a selection made inside the app.
  void setMediaLibraryBrowseTracks(Iterable<Track> tracks) {
    final engine = _audio;
    if (engine is! MediaLibraryBrowsePlaybackAudioEngine) {
      return;
    }
    final browseTracks = List<Track>.unmodifiable(tracks);
    engine.setMediaLibraryBrowseTracks(
      browseTracks,
      onTrackSelected: (track) => playTrack(track, queue: browseTracks),
    );
  }

  /// Exports only queue references that can be resolved from a synced library.
  ///
  /// Search-only and credential-backed items are intentionally omitted rather
  /// than sending their media URLs to the sync server.
  TrackQueueReferenceSnapshot exportQueueSyncSnapshot(
    Iterable<Track> libraryTracks,
  ) {
    final libraryTrackIds = libraryTracks.map((track) => track.id).toSet();
    final trackIds = _queue
        .map((track) => track.id)
        .where(libraryTrackIds.contains)
        .take(TrackQueueReferenceSnapshot.maxTrackIds)
        .toList(growable: false);
    final currentTrackId = _current?.id;
    return TrackQueueReferenceSnapshot(
      trackIds: trackIds,
      currentTrackId:
          currentTrackId != null && trackIds.contains(currentTrackId)
          ? currentTrackId
          : null,
      updatedAt: _queueUpdatedAt?.toUtc() ?? _clock().toUtc(),
    );
  }

  /// Rehydrates an opt-in synced queue from the local synced library.
  ///
  /// Receiving a queue never begins playback. A device keeps its own playable
  /// local paths and resolves provider items only when the user presses play.
  Future<int> restoreQueueSyncSnapshot(
    TrackQueueReferenceSnapshot snapshot,
    Iterable<Track> libraryTracks,
  ) async {
    final tracksById = <String, Track>{
      for (final track in libraryTracks) track.id: track,
    };
    final restoredQueue = snapshot.trackIds
        .map((id) => tracksById[id])
        .whereType<Track>()
        .toList(growable: false);
    final restoredCurrent = snapshot.currentTrackId == null
        ? null
        : tracksById[snapshot.currentTrackId];

    if (_loadedPlaybackQueue.isNotEmpty || _current != null) {
      await _audio.stop();
    }
    _queue
      ..clear()
      ..addAll(restoredQueue);
    _current = restoredCurrent ??
        (restoredQueue.isEmpty ? null : restoredQueue.first);
    _queueUpdatedAt = snapshot.updatedAt.toUtc();
    _loadedTrackId = null;
    _loadedPlaybackQueue.clear();
    _duration = Duration.zero;
    await _saveQueueSnapshot();
    notifyListeners();
    return restoredQueue.length;
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
    final rawCollection = prefs.getString(_savedQueuesSnapshotKey);
    if (rawCollection != null && rawCollection.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCollection) as Map;
        final collection = SavedTrackQueueCollection.fromJson(
          Map<String, Object?>.from(decoded),
        );
        _savedQueues
          ..clear()
          ..addAll(collection.queues);
        _activeQueueId = collection.activeQueueId;
        _restoreActiveSavedQueue();
      } catch (_) {
        await prefs.remove(_savedQueuesSnapshotKey);
        _resetSavedQueues();
      }
    } else {
      final rawSnapshot = prefs.getString(_queueSnapshotKey);
      if (rawSnapshot != null && rawSnapshot.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawSnapshot) as Map;
          final snapshot = TrackQueueSnapshot.fromJson(
            Map<String, Object?>.from(decoded),
          );
          _savedQueues
            ..clear()
            ..add(
              SavedTrackQueue(
                id: _defaultQueueId,
                name: _defaultQueueName,
                snapshot: snapshot,
              ),
            );
          _activeQueueId = _defaultQueueId;
          _restoreActiveSavedQueue();
        } catch (_) {
          await prefs.remove(_queueSnapshotKey);
          _resetSavedQueues();
        }
      }
    }

    _queueSnapshotLoaded = true;
    notifyListeners();
  }

  Future<SavedTrackQueue?> createSavedQueue(String name) async {
    final normalizedName = _normalizeSavedQueueName(name);
    if (normalizedName == null ||
        _savedQueues.length >= SavedTrackQueueCollection.maxQueues) {
      return null;
    }
    if (_savedQueues.any(
      (queue) => queue.name.toLowerCase() == normalizedName.toLowerCase(),
    )) {
      return null;
    }

    _captureActiveSavedQueue();
    final created = SavedTrackQueue(
      id: '${_clock().toUtc().microsecondsSinceEpoch}-${_nextSavedQueueSerial += 1}',
      name: normalizedName,
      snapshot: const TrackQueueSnapshot(tracks: <Track>[]),
    );
    _savedQueues.add(created);
    await _saveQueueSnapshot();
    notifyListeners();
    return created;
  }

  Future<bool> renameSavedQueue(String queueId, String name) async {
    final normalizedName = _normalizeSavedQueueName(name);
    if (normalizedName == null ||
        _savedQueues.any(
          (queue) =>
              queue.id != queueId &&
              queue.name.toLowerCase() == normalizedName.toLowerCase(),
        )) {
      return false;
    }
    final index = _savedQueues.indexWhere((queue) => queue.id == queueId);
    if (index == -1 || _savedQueues[index].name == normalizedName) {
      return false;
    }
    _captureActiveSavedQueue();
    _savedQueues[index] = _savedQueues[index].copyWith(name: normalizedName);
    await _saveQueueSnapshot();
    notifyListeners();
    return true;
  }

  Future<bool> switchSavedQueue(String queueId) async {
    if (queueId == _activeQueueId ||
        !_savedQueues.any((queue) => queue.id == queueId)) {
      return false;
    }
    _captureActiveSavedQueue();
    await _audio.stop();
    _activeQueueId = queueId;
    _restoreActiveSavedQueue();
    _duration = Duration.zero;
    await _saveQueueSnapshot();
    notifyListeners();
    return true;
  }

  Future<bool> deleteSavedQueue(String queueId) async {
    if (_savedQueues.length <= 1) {
      return false;
    }
    final index = _savedQueues.indexWhere((queue) => queue.id == queueId);
    if (index == -1) {
      return false;
    }
    _captureActiveSavedQueue();
    if (queueId == _activeQueueId) {
      final replacement = _savedQueues[index == 0 ? 1 : index - 1];
      await _audio.stop();
      _activeQueueId = replacement.id;
      _savedQueues.removeAt(index);
      _restoreActiveSavedQueue();
      _duration = Duration.zero;
    } else {
      _savedQueues.removeAt(index);
    }
    await _saveQueueSnapshot();
    notifyListeners();
    return true;
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
        _defaultPlaybackPitch = _playbackPitchFromJson(
          settings['playbackPitch'],
        );
        _trackPlaybackPitchOverrides
          ..clear()
          ..addAll(
            _trackPlaybackPitchOverridesFromJson(
              settings['trackPlaybackPitchOverrides'],
            ),
          );
        if (supportsPitch) {
          await (_audio as PitchPlaybackAudioEngine).setPitch(
            _defaultPlaybackPitch,
          );
        }
        _skipBackwardInterval = _skipIntervalFromJson(
          settings['skipBackwardSeconds'],
          fallback: _skipBackwardInterval,
        );
        _skipForwardInterval = _skipIntervalFromJson(
          settings['skipForwardSeconds'],
          fallback: _skipForwardInterval,
        );
        _skipSilenceEnabled = settings['skipSilenceEnabled'] as bool? ?? false;
        _skipFailedTracksEnabled =
            settings['skipFailedTracksEnabled'] as bool? ?? true;
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
        _virtualizerEnabled = settings['virtualizerEnabled'] as bool? ?? false;
        _virtualizerStrength = _virtualizerStrengthFromJson(
          settings['virtualizerStrength'],
        );
        final crossfadeDuration = _crossfadeDurationFromJson(
          settings['crossfadeMilliseconds'],
        );
        if (supportsCrossfade) {
          await (_audio as CrossfadePlaybackAudioEngine)
              .setCrossfadeDuration(crossfadeDuration);
        }
        if (supportsSkipSilence) {
          await (_audio as SkipSilencePlaybackAudioEngine).setSkipSilenceEnabled(
            _skipSilenceEnabled,
          );
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
        final virtualizerEngine = _virtualizerEngine;
        if (virtualizerEngine != null && virtualizerEngine.supportsVirtualizer) {
          await virtualizerEngine.setVirtualizerStrength(_virtualizerStrength);
          await virtualizerEngine.setVirtualizerEnabled(_virtualizerEnabled);
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
    _failedTrackIds.clear();
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

    if (_current?.id != preparedTrack.id) {
      _clearABRepeat(notify: false);
    }
    _current = preparedTrack;
    notifyListeners();
    await _saveQueueSnapshot(touch: true);

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
    _removeTracksFromInactiveSavedQueues(sourceId);
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
    await _saveQueueSnapshot(touch: true);
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

  void setABRepeatStart([Duration? position]) {
    final start = _clampABRepeatPosition(position ?? _audio.position);
    _aBRepeatStart = start;
    final end = _aBRepeatEnd;
    if (end != null && end - start < minABRepeatDuration) {
      _aBRepeatEnd = null;
    }
    _aBRepeatSeeking = false;
    notifyListeners();
  }

  bool setABRepeatEnd([Duration? position]) {
    final start = _aBRepeatStart;
    if (start == null) {
      return false;
    }
    final end = _clampABRepeatPosition(position ?? _audio.position);
    if (end - start < minABRepeatDuration) {
      return false;
    }
    _aBRepeatEnd = end;
    _aBRepeatSeeking = false;
    notifyListeners();
    return true;
  }

  void clearABRepeat() {
    if (_aBRepeatStart == null && _aBRepeatEnd == null) {
      return;
    }
    _clearABRepeat(notify: true);
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
    unawaited(_saveQueueSnapshot(touch: true));
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
    unawaited(_saveQueueSnapshot(touch: true));
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

  Future<void> setSkipSilenceEnabled(bool enabled) async {
    final engine = _audio;
    if (engine is! SkipSilencePlaybackAudioEngine ||
        !engine.supportsSkipSilence) {
      throw UnsupportedError(
        'Skip silence is unavailable for this audio backend.',
      );
    }
    if (_skipSilenceEnabled == enabled) {
      return;
    }
    final previous = _skipSilenceEnabled;
    _skipSilenceEnabled = enabled;
    notifyListeners();
    try {
      await engine.setSkipSilenceEnabled(enabled);
      await _savePlaybackSettings();
    } on Object {
      _skipSilenceEnabled = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setSkipFailedTracksEnabled(bool enabled) async {
    if (_skipFailedTracksEnabled == enabled) {
      return;
    }
    _skipFailedTracksEnabled = enabled;
    if (!enabled) {
      _failedTrackIds.clear();
    }
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

  Future<void> setPlaybackPitch(double pitch) async {
    _requireSupportedPlaybackPitch(pitch);
    final audio = _requirePitchEngine();
    _defaultPlaybackPitch = pitch;
    await audio.setPitch(pitch);
    await _savePlaybackSettings();
    notifyListeners();
  }

  double? playbackPitchForTrack(String trackId) {
    return _trackPlaybackPitchOverrides[trackId.trim()];
  }

  Future<void> setTrackPlaybackPitch(String trackId, double pitch) async {
    final normalizedTrackId = trackId.trim();
    if (normalizedTrackId.isEmpty) {
      throw ArgumentError.value(trackId, 'trackId', 'Track ID cannot be empty.');
    }
    _requireSupportedPlaybackPitch(pitch);
    final audio = _requirePitchEngine();
    final previous = _trackPlaybackPitchOverrides[normalizedTrackId];
    if (previous == pitch) {
      return;
    }
    _trackPlaybackPitchOverrides[normalizedTrackId] = pitch;
    try {
      if (_current?.id == normalizedTrackId) {
        await audio.setPitch(pitch);
      }
      await _savePlaybackSettings();
      notifyListeners();
    } on Object {
      if (previous == null) {
        _trackPlaybackPitchOverrides.remove(normalizedTrackId);
      } else {
        _trackPlaybackPitchOverrides[normalizedTrackId] = previous;
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> clearTrackPlaybackPitch(String trackId) async {
    final normalizedTrackId = trackId.trim();
    final previous = _trackPlaybackPitchOverrides.remove(normalizedTrackId);
    if (previous == null) {
      return;
    }
    final audio = _requirePitchEngine();
    try {
      if (_current?.id == normalizedTrackId) {
        await audio.setPitch(_defaultPlaybackPitch);
      }
      await _savePlaybackSettings();
      notifyListeners();
    } on Object {
      _trackPlaybackPitchOverrides[normalizedTrackId] = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setTemporaryPlaybackPitch(double pitch) async {
    _requireSupportedPlaybackPitch(pitch);
    final audio = _requirePitchEngine();
    if (audio.pitch == pitch) {
      return;
    }
    await audio.setPitch(pitch);
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

  Future<void> setVirtualizerEnabled(bool enabled) async {
    final engine = _requireVirtualizerEngine();
    if (_virtualizerEnabled == enabled) {
      return;
    }
    final previous = _virtualizerEnabled;
    _virtualizerEnabled = enabled;
    notifyListeners();
    try {
      await engine.setVirtualizerEnabled(enabled);
      await _savePlaybackSettings();
    } on Object {
      _virtualizerEnabled = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> previewVirtualizerStrength(int strength) async {
    final engine = _requireVirtualizerEngine();
    _validateVirtualizerStrength(strength);
    final previous = _virtualizerStrength;
    _virtualizerStrength = strength;
    notifyListeners();
    try {
      await engine.setVirtualizerStrength(strength);
    } on Object {
      _virtualizerStrength = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setVirtualizerStrength(int strength) async {
    await previewVirtualizerStrength(strength);
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

  Future<void> _handlePlaybackError() async {
    if (_handlingPlaybackError) {
      return;
    }
    final failedTrack = _current;
    if (!_skipFailedTracksEnabled || failedTrack == null) {
      notifyListeners();
      return;
    }

    _handlingPlaybackError = true;
    try {
      _failedTrackIds.add(failedTrack.id);
      final nextIndex = _nextRecoverableLoadedTrackIndex();
      if (nextIndex == null) {
        await stop();
        return;
      }
      await _audio.seek(Duration.zero, index: nextIndex);
      unawaited(_audio.play());
    } on Object catch (error) {
      debugPrint('Could not recover from playback failure: $error');
      await stop();
    } finally {
      _handlingPlaybackError = false;
    }
  }

  Future<void> _applyPitchForCurrentTrack() async {
    final track = _current;
    if (track == null || !supportsPitch) {
      return;
    }
    final pitch =
        playbackPitchForTrack(track.id) ?? _defaultPlaybackPitch;
    final audio = _audio as PitchPlaybackAudioEngine;
    if (audio.pitch == pitch) {
      return;
    }
    await audio.setPitch(pitch);
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

    _clearABRepeat(notify: false);
    _current = track;
    _playbackStartSerial += 1;
    unawaited(_applyPitchForCurrentTrack());
    unawaited(_applyOutputVolume());
    unawaited(_saveQueueSnapshot(touch: true));
    notifyListeners();
  }

  Duration _clampABRepeatPosition(Duration position) {
    if (position.isNegative) {
      return Duration.zero;
    }
    if (_duration > Duration.zero && position > _duration) {
      return _duration;
    }
    return position;
  }

  void _handleABRepeatPosition(Duration position) {
    final start = _aBRepeatStart;
    final end = _aBRepeatEnd;
    if (start == null || end == null ||
        !_audio.playing || position < end || _aBRepeatSeeking) {
      return;
    }
    unawaited(_seekABRepeat(start));
  }

  Future<void> _seekABRepeat(Duration start) async {
    _aBRepeatSeeking = true;
    try {
      await _audio.seek(start);
    } finally {
      _aBRepeatSeeking = false;
    }
  }

  void _clearABRepeat({required bool notify}) {
    _aBRepeatStart = null;
    _aBRepeatEnd = null;
    _aBRepeatSeeking = false;
    if (notify) {
      notifyListeners();
    }
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
      await _applyPitchForCurrentTrack();
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

  Future<void> _saveQueueSnapshot({bool touch = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (touch || _queueUpdatedAt == null) {
      _queueUpdatedAt = _clock().toUtc();
    }
    _captureActiveSavedQueue();
    final collection = SavedTrackQueueCollection(
      activeQueueId: _activeQueueId,
      queues: _savedQueues,
    );
    await prefs.setString(
      _savedQueuesSnapshotKey,
      jsonEncode(collection.toJson()),
    );
    if (_queue.isEmpty) {
      await prefs.remove(_queueSnapshotKey);
      return;
    }

    final snapshot = TrackQueueSnapshot(
      tracks: _queue,
      currentTrackId: _current?.id,
      updatedAt: _queueUpdatedAt,
    );
    await prefs.setString(_queueSnapshotKey, jsonEncode(snapshot.toJson()));
  }

  SavedTrackQueue get _activeSavedQueue {
    return _savedQueues.firstWhere(
      (queue) => queue.id == _activeQueueId,
      orElse: _emptySavedQueue,
    );
  }

  SavedTrackQueue _emptySavedQueue() {
    return const SavedTrackQueue(
      id: _defaultQueueId,
      name: _defaultQueueName,
      snapshot: TrackQueueSnapshot(tracks: <Track>[]),
    );
  }

  void _resetSavedQueues() {
    _savedQueues
      ..clear()
      ..add(_emptySavedQueue());
    _activeQueueId = _defaultQueueId;
    _restoreActiveSavedQueue();
  }

  void _captureActiveSavedQueue() {
    final index = _savedQueues.indexWhere(
      (queue) => queue.id == _activeQueueId,
    );
    if (index == -1) {
      _savedQueues.add(
        SavedTrackQueue(
          id: _defaultQueueId,
          name: _defaultQueueName,
          snapshot: _activeQueueSnapshot(),
        ),
      );
      _activeQueueId = _defaultQueueId;
      return;
    }
    _savedQueues[index] = _savedQueues[index].copyWith(
      snapshot: _activeQueueSnapshot(),
    );
  }

  void _removeTracksFromInactiveSavedQueues(String sourceId) {
    for (var index = 0; index < _savedQueues.length; index += 1) {
      final savedQueue = _savedQueues[index];
      if (savedQueue.id == _activeQueueId) {
        continue;
      }
      final remaining = savedQueue.snapshot.tracks
          .where((track) => track.sourceId != sourceId)
          .toList(growable: false);
      if (remaining.length == savedQueue.snapshot.tracks.length) {
        continue;
      }
      final currentTrackId = savedQueue.snapshot.currentTrackId;
      _savedQueues[index] = savedQueue.copyWith(
        snapshot: TrackQueueSnapshot(
          tracks: remaining,
          currentTrackId: remaining.any((track) => track.id == currentTrackId)
              ? currentTrackId
              : remaining.isEmpty
              ? null
              : remaining.first.id,
          updatedAt: _clock().toUtc(),
        ),
      );
    }
  }

  TrackQueueSnapshot _activeQueueSnapshot() {
    return TrackQueueSnapshot(
      tracks: List<Track>.from(_queue),
      currentTrackId: _current?.id,
      updatedAt: _queueUpdatedAt,
    );
  }

  void _restoreActiveSavedQueue() {
    final snapshot = _activeSavedQueue.snapshot;
    _queue
      ..clear()
      ..addAll(snapshot.tracks);
    _current = snapshot.currentTrack;
    _queueUpdatedAt = snapshot.updatedAt;
    _loadedTrackId = null;
    _loadedPlaybackQueue.clear();
  }

  String? _normalizeSavedQueueName(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty || normalized.length > 80) {
      return null;
    }
    return normalized;
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
          'playbackPitch': _defaultPlaybackPitch,
          'trackPlaybackPitchOverrides': _trackPlaybackPitchOverrides,
          'skipBackwardSeconds': _skipBackwardInterval.inSeconds,
          'skipForwardSeconds': _skipForwardInterval.inSeconds,
          'skipSilenceEnabled': _skipSilenceEnabled,
          'skipFailedTracksEnabled': _skipFailedTracksEnabled,
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
          'virtualizerEnabled': _virtualizerEnabled,
          'virtualizerStrength': _virtualizerStrength,
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

  double _playbackPitchFromJson(Object? value) {
    if (value is num) {
      final pitch = value.toDouble();
      if (supportedPlaybackPitches.contains(pitch)) {
        return pitch;
      }
    }
    return 1;
  }

  Map<String, double> _trackPlaybackPitchOverridesFromJson(Object? value) {
    if (value is! Map) {
      return <String, double>{};
    }
    final overrides = <String, double>{};
    for (final entry in value.entries) {
      final trackId = entry.key is String ? (entry.key as String).trim() : '';
      final pitch = entry.value is num ? (entry.value as num).toDouble() : null;
      if (trackId.isEmpty ||
          pitch == null ||
          !supportedPlaybackPitches.contains(pitch)) {
        continue;
      }
      overrides[trackId] = pitch;
    }
    return overrides;
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

  void _requireSupportedPlaybackPitch(double pitch) {
    if (!supportedPlaybackPitches.contains(pitch)) {
      throw ArgumentError.value(
        pitch,
        'pitch',
        'Playback pitch must be one of the supported values.',
      );
    }
  }

  PitchPlaybackAudioEngine _requirePitchEngine() {
    final audio = _audio;
    if (audio is! PitchPlaybackAudioEngine || !audio.supportsPitch) {
      throw UnsupportedError('Pitch control is unavailable for this backend.');
    }
    return audio;
  }

  AudioEffectsPlaybackAudioEngine? get _audioEffectsEngine {
    final engine = _audio;
    return engine is AudioEffectsPlaybackAudioEngine ? engine : null;
  }

  VirtualizerPlaybackAudioEngine? get _virtualizerEngine {
    final engine = _audio;
    return engine is VirtualizerPlaybackAudioEngine ? engine : null;
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

  VirtualizerPlaybackAudioEngine _requireVirtualizerEngine() {
    final engine = _virtualizerEngine;
    if (engine == null || !engine.supportsVirtualizer) {
      throw UnsupportedError('Virtualizer is unavailable for this audio backend.');
    }
    return engine;
  }

  Future<bool> startVisualizer() {
    final engine = _audio;
    if (engine is! AudioVisualizationPlaybackAudioEngine ||
        !engine.supportsVisualizer) {
      return Future<bool>.value(false);
    }
    return engine.startVisualizer();
  }

  Future<void> stopVisualizer() {
    final engine = _audio;
    if (engine is! AudioVisualizationPlaybackAudioEngine ||
        !engine.supportsVisualizer) {
      return Future<void>.value();
    }
    return engine.stopVisualizer();
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

  int _virtualizerStrengthFromJson(Object? value) {
    if (value is num) {
      final strength = value.toInt();
      if (strength >= minVirtualizerStrength &&
          strength <= maxVirtualizerStrength) {
        return strength;
      }
    }
    return 500;
  }

  void _validateVirtualizerStrength(int strength) {
    if (strength < minVirtualizerStrength ||
        strength > maxVirtualizerStrength) {
      throw ArgumentError.value(
        strength,
        'strength',
        'Virtualizer strength must be between 0 and 1000.',
      );
    }
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

  int? _nextRecoverableLoadedTrackIndex() {
    if (_loadedPlaybackQueue.isEmpty) {
      return null;
    }
    final currentIndex = _loadedPlaybackQueue.indexWhere(
      (track) => track.id == _current?.id,
    );
    if (currentIndex == -1) {
      return null;
    }

    for (var offset = 1; offset < _loadedPlaybackQueue.length; offset += 1) {
      final candidateIndex = currentIndex + offset;
      if (candidateIndex >= _loadedPlaybackQueue.length &&
          _audio.loopMode != LoopMode.all) {
        return null;
      }
      final normalizedIndex = candidateIndex % _loadedPlaybackQueue.length;
      final candidate = _loadedPlaybackQueue[normalizedIndex];
      if (!_failedTrackIds.contains(candidate.id)) {
        return normalizedIndex;
      }
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
    _positionSub?.cancel();
    _completedSub?.cancel();
    _currentIndexSub?.cancel();
    _errorSub?.cancel();
    unawaited(_audio.dispose());
    super.dispose();
  }
}
