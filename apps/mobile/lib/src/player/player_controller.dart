import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sleep_timer_duration.dart';
import '../domain/track.dart';
import '../domain/track_queue.dart';
import 'offline_playback_policy.dart';
import 'playback_audio_engine.dart';

typedef TrackPlaybackResolver = Future<Track> Function(Track track);

class PlayerController extends ChangeNotifier {
  PlayerController({
    PlaybackAudioEngine? audioEngine,
    TrackPlaybackResolver? trackResolver,
  })  : _audio = audioEngine ?? JustAudioPlaybackEngine(),
        _trackResolver = trackResolver {
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

  Track? get current => _current;
  List<Track> get queue => List.unmodifiable(_queue);
  int get playbackStartSerial => _playbackStartSerial;
  bool get isPlaying => _audio.playing;
  bool get shuffleEnabled => _audio.shuffleModeEnabled;
  LoopMode get loopMode => _audio.loopMode;
  Duration get duration => _duration;
  Duration get position => _audio.position;
  Stream<Duration> get positionStream => _audio.positionStream;
  Duration? get sleepTimerRemaining => _sleepTimer == null ? null : Duration.zero;
  bool get stopAtEndOfTrackEnabled => _stopAtEndOfTrack;
  bool get sleepTimerFadeOutEnabled => _sleepTimerFadesOut;
  Duration get sleepTimerFadeDuration => _sleepTimerFadeDuration;
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

  Future<void> seek(Duration position) async {
    await _audio.seek(position);
  }

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
    _sleepFadeStartVolume = _audio.volume;
    _sleepFadeStepTimer = Timer.periodic(stepInterval, (timer) {
      step += 1;
      unawaited(
        _audio.setVolume(
          sleepTimerFadeVolume(
            startVolume: _sleepFadeStartVolume ?? _audio.volume,
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
      await _audio.setVolume(startVolume);
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
      unawaited(_audio.setVolume(startVolume));
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
