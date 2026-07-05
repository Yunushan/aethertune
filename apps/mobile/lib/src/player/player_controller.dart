import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/track.dart';

class PlayerController extends ChangeNotifier {
  PlayerController() {
    _playerStateSub = _audio.playerStateStream.listen((_) => notifyListeners());
    _durationSub = _audio.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });
    _completedSub = _audio.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        next();
      }
    });
  }

  final AudioPlayer _audio = AudioPlayer();
  final List<Track> _queue = <Track>[];

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<ProcessingState>? _completedSub;
  Timer? _sleepTimer;
  Duration _duration = Duration.zero;
  Track? _current;

  Track? get current => _current;
  List<Track> get queue => List.unmodifiable(_queue);
  bool get isPlaying => _audio.playing;
  bool get shuffleEnabled => _audio.shuffleModeEnabled;
  LoopMode get loopMode => _audio.loopMode;
  Duration get duration => _duration;
  Stream<Duration> get positionStream => _audio.positionStream;
  Duration? get sleepTimerRemaining => _sleepTimer == null ? null : Duration.zero;

  Future<void> playTrack(Track track, {List<Track>? queue}) async {
    if (queue != null) {
      _queue
        ..clear()
        ..addAll(queue);
    } else if (!_queue.any((queued) => queued.id == track.id)) {
      _queue.add(track);
    }

    _current = track;
    notifyListeners();

    await _load(track);
    await _audio.play();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_current == null) {
      return;
    }

    if (_audio.playing) {
      await _audio.pause();
    } else {
      await _audio.play();
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

  Future<void> setShuffleEnabled(bool enabled) async {
    await _audio.setShuffleModeEnabled(enabled);
    notifyListeners();
  }

  Future<void> setLoopMode(LoopMode mode) async {
    await _audio.setLoopMode(mode);
    notifyListeners();
  }

  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, () async {
      await stop();
      _sleepTimer = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    notifyListeners();
  }

  Future<void> _load(Track track) async {
    if (track.localPath != null) {
      await _audio.setFilePath(track.localPath!);
      return;
    }

    if (track.streamUrl != null) {
      await _audio.setUrl(track.streamUrl!);
      return;
    }

    throw StateError('Track has no local path or stream URL: ${track.title}');
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
