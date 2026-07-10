import 'dart:async';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/playback_audio_engine_factory.dart';
import 'package:aethertune/src/player/system_media_playback_engine.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  test('publishes queue metadata and current media item', () async {
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    final tracks = <Track>[
      _track('one', duration: const Duration(minutes: 3)),
      _track('two', artwork: Uri.parse('https://example.test/two.jpg')),
    ];

    await engine.setQueue(tracks, initialIndex: 1);

    expect(engine.queue.value.map((item) => item.id), <String>['one', 'two']);
    expect(engine.mediaItem.value?.id, 'two');
    expect(engine.mediaItem.value?.title, 'Track two');
    expect(engine.mediaItem.value?.artist, 'Artist two');
    expect(
      engine.mediaItem.value?.artUri,
      Uri.parse('https://example.test/two.jpg'),
    );
    expect(engine.mediaItem.value?.extras?['sourceId'], 'local');

    delegate.emitDuration(const Duration(minutes: 4));
    expect(engine.mediaItem.value?.duration, const Duration(minutes: 4));
  });

  test('does not publish authenticated stream URLs to system media metadata',
      () async {
    const secret = 'private-api-key';
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    final track = Track(
      id: 'private-track',
      title: 'Private Track',
      artist: 'Private Artist',
      streamUrl: 'https://media.example.test/audio?api_key=$secret',
      streamUrlIsEphemeral: true,
      sourceId: 'self-hosted-jellyfin',
      externalId: 'song-1',
    );

    await engine.setQueue(<Track>[track], initialIndex: 0);

    final item = engine.mediaItem.value!;
    expect(item.id, 'private-track');
    expect(item.artUri, isNull);
    expect(item.extras, isNot(contains('streamUrl')));
    expect(item.extras.toString(), isNot(contains(secret)));
    expect(item.extras?['sourceId'], 'self-hosted-jellyfin');
    expect(item.extras?['externalId'], 'song-1');
  });

  test('publishes playback state for notifications and control center',
      () async {
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    await engine.setQueue(
      <Track>[_track('one'), _track('two')],
      initialIndex: 0,
    );

    delegate
      ..positionValue = const Duration(seconds: 12)
      ..bufferedPositionValue = const Duration(seconds: 28)
      ..emitProcessingState(ProcessingState.ready)
      ..emitPlaying(true);

    final state = engine.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.updatePosition, const Duration(seconds: 12));
    expect(state.bufferedPosition, const Duration(seconds: 28));
    expect(state.queueIndex, 0);
    expect(state.controls, contains(MediaControl.pause));
    expect(state.controls, contains(MediaControl.skipToNext));
    expect(state.systemActions, contains(MediaAction.seek));
  });

  test('routes system transport, repeat, and shuffle commands', () async {
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    await engine.setQueue(
      <Track>[_track('one'), _track('two'), _track('three')],
      initialIndex: 1,
    );

    await engine.skipToNext();
    expect(delegate.currentIndex, 2);
    await engine.skipToPrevious();
    expect(delegate.currentIndex, 1);
    await engine.skipToQueueItem(0);
    expect(delegate.currentIndex, 0);
    await engine.seek(const Duration(seconds: 45));
    expect(delegate.positionValue, const Duration(seconds: 45));

    await engine.setRepeatMode(AudioServiceRepeatMode.all);
    await engine.setShuffleMode(AudioServiceShuffleMode.all);
    expect(delegate.loopModeValue, LoopMode.all);
    expect(delegate.shuffleValue, isTrue);
    expect(engine.playbackState.value.repeatMode, AudioServiceRepeatMode.all);
    expect(
      engine.playbackState.value.shuffleMode,
      AudioServiceShuffleMode.all,
    );
  });

  test('enables native media sessions only on supported platforms', () {
    expect(supportsSystemMediaSession(TargetPlatform.android), isTrue);
    expect(supportsSystemMediaSession(TargetPlatform.iOS), isTrue);
    expect(supportsSystemMediaSession(TargetPlatform.macOS), isTrue);
    expect(supportsSystemMediaSession(TargetPlatform.linux), isFalse);
    expect(supportsSystemMediaSession(TargetPlatform.windows), isFalse);
  });
}

Track _track(String id, {Duration duration = Duration.zero, Uri? artwork}) {
  return Track(
    id: id,
    title: 'Track $id',
    artist: 'Artist $id',
    album: 'Album $id',
    duration: duration,
    artworkUri: artwork,
    localPath: '/music/$id.mp3',
  );
}

class _FakePlaybackAudioEngine implements PlaybackAudioEngine {
  final _stateController = StreamController<Object?>.broadcast(sync: true);
  final _durationController =
      StreamController<Duration?>.broadcast(sync: true);
  final _positionController = StreamController<Duration>.broadcast(sync: true);
  final _processingController =
      StreamController<ProcessingState>.broadcast(sync: true);
  final _indexController = StreamController<int?>.broadcast(sync: true);

  List<Track> tracks = <Track>[];
  int currentIndex = 0;
  bool playingValue = false;
  bool shuffleValue = false;
  LoopMode loopModeValue = LoopMode.off;
  Duration positionValue = Duration.zero;
  Duration bufferedPositionValue = Duration.zero;
  double volumeValue = 1;

  @override
  Stream<Object?> get stateChanges => _stateController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _processingController.stream;

  @override
  Stream<int?> get currentIndexStream => _indexController.stream;

  @override
  bool get playing => playingValue;

  @override
  bool get shuffleModeEnabled => shuffleValue;

  @override
  LoopMode get loopMode => loopModeValue;

  @override
  Duration get position => positionValue;

  @override
  Duration get bufferedPosition => bufferedPositionValue;

  @override
  double get speed => 1;

  @override
  double get volume => volumeValue;

  @override
  bool get hasNext => currentIndex + 1 < tracks.length;

  @override
  bool get hasPrevious => currentIndex > 0;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    this.tracks = List<Track>.from(tracks);
    currentIndex = initialIndex;
    positionValue = initialPosition;
    _indexController.add(currentIndex);
  }

  void emitPlaying(bool playing) {
    playingValue = playing;
    _stateController.add(null);
  }

  void emitDuration(Duration duration) {
    _durationController.add(duration);
  }

  void emitProcessingState(ProcessingState state) {
    _processingController.add(state);
  }

  @override
  Future<void> play() async => emitPlaying(true);

  @override
  Future<void> pause() async => emitPlaying(false);

  @override
  Future<void> stop() async => emitPlaying(false);

  @override
  Future<void> seek(Duration position, {int? index}) async {
    positionValue = position;
    _positionController.add(position);
    if (index != null) {
      currentIndex = index;
      _indexController.add(index);
    }
  }

  @override
  Future<void> seekToNext() => seek(Duration.zero, index: currentIndex + 1);

  @override
  Future<void> seekToPrevious() =>
      seek(Duration.zero, index: currentIndex - 1);

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    shuffleValue = enabled;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopModeValue = mode;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeValue = volume;
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _durationController.close();
    await _positionController.close();
    await _processingController.close();
    await _indexController.close();
  }
}
