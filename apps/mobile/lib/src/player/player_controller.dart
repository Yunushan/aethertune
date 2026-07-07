import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/track.dart';
import '../domain/track_queue.dart';

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
  Duration _duration = Duration.zero;
  Track? _current;
  String? _loadedTrackId;
  bool _stopAtEndOfTrack = false;
  bool _queueSnapshotLoaded = false;
  bool _playbackSettingsLoaded = false;
  int _playbackStartSerial = 0;

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

    if (index + 1 < _queue.length) {
      await playTrack(_queue[index + 1]);
      return;
    }

    if (_audio.loopMode == LoopMode.all) {
      await playTrack(_queue.first);
      return;
    }

    await stop();
  }

  Future<void> previous() async {
    if (_queue.isEmpty || _current == null) {
      return;
    }

    final index = _queue.indexWhere((track) => track.id == _current!.id);
    if (index > 0) {
      await playTrack(_queue[index - 1]);
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

  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _stopAtEndOfTrack = false;
    _sleepTimer = Timer(duration, () async {
      await stop();
      _sleepTimer = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void stopAtEndOfTrack() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _stopAtEndOfTrack = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
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

  Future<void> _load(Track track) async {
    if (track.localPath != null) {
      await _audio.setFilePath(track.localPath!);
      _loadedTrackId = track.id;
      return;
    }

    if (track.streamUrl != null) {
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

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _playerStateSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _audio.dispose();
    super.dispose();
  }
}
