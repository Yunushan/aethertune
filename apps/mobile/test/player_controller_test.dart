import 'dart:async';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('loads one native queue and follows gapless index transitions',
      () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2'), _track('3')];

    await controller.playTrack(tracks.first, queue: tracks);

    expect(engine.setQueueCalls, 1);
    expect(engine.queue.map((track) => track.id), <String>['1', '2', '3']);
    expect(engine.initialIndex, 0);
    expect(controller.current?.id, '1');
    expect(controller.playbackStartSerial, 1);

    engine.emitAutomaticIndex(1);

    expect(controller.current?.id, '2');
    expect(controller.playbackStartSerial, 2);
    expect(engine.setQueueCalls, 1);
  });

  test('uses native next and previous without reloading the queue', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2'), _track('3')];
    await controller.playTrack(tracks.first, queue: tracks);

    await controller.next();
    expect(controller.current?.id, '2');
    expect(engine.seekToNextCalls, 1);
    expect(engine.setQueueCalls, 1);

    await controller.previous();
    expect(controller.current?.id, '1');
    expect(engine.seekToPreviousCalls, 1);
    expect(engine.setQueueCalls, 1);
  });

  test('filters network queue entries while offline', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[
      _track('local-1'),
      _track(
        'remote',
        localPath: '',
        streamUrl: 'https://media.example.test/remote.mp3',
      ),
      _track('local-2'),
    ];
    controller.setOfflineModeEnabled(true);

    await controller.playTrack(tracks.first, queue: tracks);

    expect(
      engine.queue.map((track) => track.id),
      <String>['local-1', 'local-2'],
    );
    engine.emitAutomaticIndex(1);
    expect(controller.current?.id, 'local-2');
  });

  test('rebuilds edited queues at the current track and position', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2'), _track('3')];
    await controller.playTrack(tracks[1], queue: tracks);
    engine.positionValue = const Duration(seconds: 37);

    controller.moveTrackInQueue(2, 0);
    await _flushAsyncWork();

    expect(engine.setQueueCalls, 2);
    expect(engine.queue.map((track) => track.id), <String>['3', '1', '2']);
    expect(engine.initialIndex, 2);
    expect(engine.initialPosition, const Duration(seconds: 37));

    controller.removeTrackFromQueue('1');
    await _flushAsyncWork();
    expect(engine.queue.map((track) => track.id), <String>['3', '2']);
    expect(engine.initialIndex, 1);
  });

  test('restores a persisted queue into the native gapless engine', () async {
    final firstEngine = _FakePlaybackAudioEngine();
    final firstController = PlayerController(audioEngine: firstEngine);
    final tracks = <Track>[_track('1'), _track('2'), _track('3')];
    await firstController.playTrack(tracks[1], queue: tracks);
    firstController.dispose();
    await _flushAsyncWork();

    final restoredEngine = _FakePlaybackAudioEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedQueue();

    expect(restoredController.queue.map((track) => track.id), <String>[
      '1',
      '2',
      '3',
    ]);
    expect(restoredController.current?.id, '2');

    await restoredController.togglePlayPause();
    expect(restoredEngine.setQueueCalls, 1);
    expect(restoredEngine.initialIndex, 1);
    expect(restoredEngine.playing, isTrue);
  });

  test(
    'resolves credentialed queues after restart without persisting secrets',
    () async {
      const secret = 'private-api-key';
      final metadataQueue = <Track>[
        Track(
          id: 'private-1',
          title: 'Private 1',
          sourceId: 'self-hosted',
          externalId: 'song-1',
        ),
        Track(
          id: 'private-2',
          title: 'Private 2',
          sourceId: 'self-hosted',
          externalId: 'song-2',
        ),
      ];
      Future<Track> resolve(Track track) async {
        return track.copyWith(
          streamUrl:
              'https://music.example.test/${track.externalId}?api_key=$secret',
          streamUrlIsEphemeral: true,
        );
      }

      final firstEngine = _FakePlaybackAudioEngine();
      final firstController = PlayerController(
        audioEngine: firstEngine,
        trackResolver: resolve,
      );
      await firstController.playTrack(
        metadataQueue.first,
        queue: metadataQueue,
      );

      expect(firstEngine.queue, hasLength(2));
      expect(
        firstEngine.queue.every((track) => track.streamUrl!.contains(secret)),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      final firstSnapshot = prefs.getString('aethertune.player_queue.v1')!;
      expect(firstSnapshot, isNot(contains(secret)));
      expect(firstSnapshot, isNot(contains('api_key')));
      firstController.dispose();
      await _flushAsyncWork();

      final restoredEngine = _FakePlaybackAudioEngine();
      final restoredController = PlayerController(
        audioEngine: restoredEngine,
        trackResolver: resolve,
      );
      addTearDown(restoredController.dispose);
      await restoredController.loadPersistedQueue();

      expect(restoredController.queue.every((track) => !track.isPlayable), isTrue);
      await restoredController.togglePlayPause();

      expect(restoredEngine.queue, hasLength(2));
      expect(
        restoredEngine.queue.every(
          (track) => track.streamUrl!.contains(secret),
        ),
        isTrue,
      );
      final restoredSnapshot = prefs.getString('aethertune.player_queue.v1')!;
      expect(restoredSnapshot, isNot(contains(secret)));
      expect(restoredSnapshot, isNot(contains('api_key')));
    },
  );

  test('removes every queued track for a deleted provider account', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final privateTrack = Track(
      id: 'private',
      title: 'Private',
      streamUrl: 'https://music.example.test/private',
      sourceId: 'self-hosted',
    );
    final localTrack = _track('local');
    await controller.playTrack(privateTrack, queue: <Track>[
      privateTrack,
      localTrack,
    ]);

    await controller.removeTracksFromSource('self-hosted');

    expect(controller.current, isNull);
    expect(controller.queue.map((track) => track.id), <String>['local']);
    expect(engine.stopCalls, 1);
    final prefs = await SharedPreferences.getInstance();
    final snapshot = prefs.getString('aethertune.player_queue.v1')!;
    expect(snapshot, isNot(contains('music.example.test')));
    expect(snapshot, contains('local'));
  });

  test('isolates the current source for stop-at-end behavior', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2')];
    await controller.playTrack(tracks.first, queue: tracks);
    engine.positionValue = const Duration(minutes: 1);

    controller.stopAtEndOfTrack();
    await _flushAsyncWork();

    expect(engine.queue.map((track) => track.id), <String>['1']);
    expect(engine.initialPosition, const Duration(minutes: 1));

    engine.emitCompleted();
    await _flushAsyncWork();
    expect(engine.stopCalls, 1);
    expect(controller.stopAtEndOfTrackEnabled, isFalse);
  });
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Track _track(
  String id, {
  String? localPath,
  String? streamUrl,
}) {
  return Track(
    id: id,
    title: 'Track $id',
    localPath: localPath ?? '/music/$id.mp3',
    streamUrl: streamUrl,
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

  List<Track> queue = <Track>[];
  int initialIndex = 0;
  Duration initialPosition = Duration.zero;
  Duration positionValue = Duration.zero;
  bool playingValue = false;
  bool shuffleValue = false;
  LoopMode loopModeValue = LoopMode.off;
  double volumeValue = 1;
  int currentIndex = 0;
  int setQueueCalls = 0;
  int seekToNextCalls = 0;
  int seekToPreviousCalls = 0;
  int stopCalls = 0;

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
  Duration get bufferedPosition => positionValue;

  @override
  double get speed => 1;

  @override
  double get volume => volumeValue;

  @override
  bool get hasNext => currentIndex + 1 < queue.length;

  @override
  bool get hasPrevious => currentIndex > 0;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    setQueueCalls += 1;
    queue = List<Track>.from(tracks);
    this.initialIndex = initialIndex;
    this.initialPosition = initialPosition;
    currentIndex = initialIndex;
    positionValue = initialPosition;
    _indexController.add(initialIndex);
  }

  void emitAutomaticIndex(int index) {
    currentIndex = index;
    positionValue = Duration.zero;
    _positionController.add(positionValue);
    _indexController.add(index);
  }

  void emitCompleted() {
    _processingController.add(ProcessingState.completed);
  }

  @override
  Future<void> play() async {
    playingValue = true;
    _stateController.add(null);
  }

  @override
  Future<void> pause() async {
    playingValue = false;
    _stateController.add(null);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    playingValue = false;
    _stateController.add(null);
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    positionValue = position;
    _positionController.add(positionValue);
    if (index != null) {
      currentIndex = index;
      _indexController.add(index);
    }
  }

  @override
  Future<void> seekToNext() async {
    seekToNextCalls += 1;
    emitAutomaticIndex(currentIndex + 1);
  }

  @override
  Future<void> seekToPrevious() async {
    seekToPreviousCalls += 1;
    emitAutomaticIndex(currentIndex - 1);
  }

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
