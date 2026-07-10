import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/now_playing_screen.dart';
import 'package:aethertune/src/ui/widgets/player_bar.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('full player exposes playback, queue, and library actions', (
    tester,
  ) async {
    final engine = _FakePlaybackAudioEngine();
    final player = PlayerController(audioEngine: engine);
    final library = LibraryStore();
    final first = _track('first', title: 'First Song', durationSeconds: 240);
    final second = _track('second', title: 'Second Song', durationSeconds: 180);
    await library.addTracks(<Track>[first, second]);
    await player.playTrack(first, queue: <Track>[first, second]);

    var queueOpens = 0;
    var lyricsOpens = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: library),
          ChangeNotifierProvider<PlayerController>.value(value: player),
        ],
        child: MaterialApp(
          home: NowPlayingScreen(
            onOpenQueue: () => queueOpens += 1,
            onOpenLyrics: () => lyricsOpens += 1,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('First Song'), findsOneWidget);
    expect(find.text('Track 1 of 2'), findsOneWidget);
    expect(find.byKey(const Key('now-playing-seek')), findsOneWidget);
    expect(find.byTooltip('Add to favorites'), findsOneWidget);

    await tester.tap(find.byKey(const Key('now-playing-shuffle')));
    await tester.tap(find.byKey(const Key('now-playing-repeat')));
    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.tap(find.widgetWithText(TextButton, 'Lyrics'));
    await tester.tap(find.widgetWithText(TextButton, 'Queue'));
    await tester.pump();

    expect(engine.shuffleValue, isTrue);
    expect(engine.loopModeValue, LoopMode.all);
    expect(library.tracks.first.isFavorite, isTrue);
    expect(queueOpens, 1);
    expect(lyricsOpens, 1);

    await tester.drag(
      find.byKey(const Key('now-playing-artwork')),
      const Offset(-120, 0),
    );
    await tester.pump();

    expect(engine.seekToNextCalls, 1);
    expect(find.text('Second Song'), findsOneWidget);
    expect(find.text('Track 2 of 2'), findsOneWidget);
  });

  testWidgets('compact player fits a phone and opens the full player', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final engine = _FakePlaybackAudioEngine();
    final player = PlayerController(audioEngine: engine);
    final track = _track(
      'compact',
      title: 'A deliberately long title for a narrow phone player',
      durationSeconds: 200,
    );
    await player.playTrack(track, queue: <Track>[track]);
    var nowPlayingOpens = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerController>.value(
        value: player,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const Spacer(),
                PlayerBar(
                  onOpenNowPlaying: () => nowPlayingOpens += 1,
                  onOpenQueue: () {},
                  onSaveQueue: () {},
                  onOpenLyrics: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Lyrics'), findsNothing);
    expect(find.byTooltip('Play'), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Next'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-now-playing')));
    expect(nowPlayingOpens, 1);
  });
}

Track _track(
  String id, {
  required String title,
  required int durationSeconds,
}) {
  return Track(
    id: id,
    title: title,
    artist: 'Test Artist',
    album: 'Test Album',
    duration: Duration(seconds: durationSeconds),
    localPath: '/music/$id.mp3',
  );
}

class _FakePlaybackAudioEngine implements PlaybackAudioEngine {
  final _stateController = StreamController<Object?>.broadcast(sync: true);
  final _durationController = StreamController<Duration?>.broadcast(sync: true);
  final _positionController = StreamController<Duration>.broadcast(sync: true);
  final _processingController =
      StreamController<ProcessingState>.broadcast(sync: true);
  final _indexController = StreamController<int?>.broadcast(sync: true);

  List<Track> queue = <Track>[];
  Duration positionValue = Duration.zero;
  Duration durationValue = Duration.zero;
  bool playingValue = false;
  bool shuffleValue = false;
  LoopMode loopModeValue = LoopMode.off;
  int currentIndex = 0;
  int seekToNextCalls = 0;

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
  double get volume => 1;

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
    queue = List<Track>.from(tracks);
    currentIndex = initialIndex;
    positionValue = initialPosition;
    durationValue = tracks[initialIndex].duration;
    _durationController.add(durationValue);
    _indexController.add(initialIndex);
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
    playingValue = false;
    _stateController.add(null);
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    positionValue = position;
    _positionController.add(position);
    if (index != null) {
      currentIndex = index;
      durationValue = queue[index].duration;
      _durationController.add(durationValue);
      _indexController.add(index);
    }
  }

  @override
  Future<void> seekToNext() async {
    seekToNextCalls += 1;
    currentIndex += 1;
    durationValue = queue[currentIndex].duration;
    positionValue = Duration.zero;
    _durationController.add(durationValue);
    _positionController.add(positionValue);
    _indexController.add(currentIndex);
  }

  @override
  Future<void> seekToPrevious() async {
    currentIndex -= 1;
    _indexController.add(currentIndex);
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
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _durationController.close();
    await _positionController.close();
    await _processingController.close();
    await _indexController.close();
  }
}
