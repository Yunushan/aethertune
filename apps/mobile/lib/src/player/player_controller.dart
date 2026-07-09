import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sleep_timer_duration.dart';
import '../domain/track.dart';
import '../domain/track_queue.dart';
import 'offline_playback_policy.dart';

class PlayerController extends ChangeNotifier {
  PlayerController() {
    _playerStateSub = _audio.playerStateStream.listen((_) => notifyListeners());
    _durationSub = _audio.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });
    _completedSub = _audio.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        unawaited(_handleTrackCompleted());
      }
    });
  }

  static const _queueSnapshotKey = 'aethertune.player_queue.v1';
  static const _playbackSettingsKey = 'aethertune.playback_settings.v1';

  final AudioPlayer _audio = AudioPlayer();
  final List<Track> _queue = <Track>[];

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<ProcessingState>? _completedSub;
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
      unawaited(_audio.stop());
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
    requireOfflineModePlaybackAllowed(
      track,
      offlineModeEnabled: _offlineModeEnabled,
    );

    if (queue != null) {
      _queue
        ..clear()
        ..addAll(queue);
    } else if (!_queue.any((queued) => queued.id == track.id)) {
      _queue.add(track);
    }

    _current = track;
    notifyListeners();
    await _saveQueueSnapshot();

    await _load(track);
    if (initialPosition != null && initialPosition > Duration.zero) {
      await _audio.seek(initialPosition);
    }
    await _audio.play();
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
      requireOfflineModePlaybackAllowed(
        _current!,
        offlineModeEnabled: _offlineModeEnabled,
      );

      final wasLoaded = _loadedTrackId == _current!.id;
      if (!wasLoaded) {
        await _load(_current!);
      }

      await _audio.play();
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

  Future<void> seek(Duration position) async {
    await _audio.seek(position);
  }

  Future<void> next() async {
    if (_queue.isEmpty || _current == null) {
      await stop();
      return;
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
    notifyListeners();
  }

  void stopAtEndOfTrack() {
    _cancelSleepTimerState(restoreVolume: true);
    _stopAtEndOfTrack = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _cancelSleepTimerState(restoreVolume: true);
    _stopAtEndOfTrack = false;
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

  Future<void> _load(Track track) async {
    if (track.hasLocalSource) {
      await _audio.setFilePath(track.localPath!);
      _loadedTrackId = track.id;
      return;
    }

    if (track.hasStreamSource) {
      await _audio.setUrl(track.streamUrl!);
      _loadedTrackId = track.id;
      return;
    }

    throw StateError('Track has no local path or stream URL: ${track.title}');
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
      if (offlineModeAllowsPlayback(
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
      if (offlineModeAllowsPlayback(
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
    _audio.dispose();
    super.dispose();
  }
}
