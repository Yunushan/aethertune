import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/podcast_transcript_loader.dart';
import 'package:aethertune/src/data/sponsorblock_segment_provider.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_chapter.dart';
import 'package:aethertune/src/domain/track_skip_segment.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/now_playing_screen.dart';
import 'package:aethertune/src/ui/widgets/desktop_queue_pane.dart';
import 'package:aethertune/src/ui/widgets/player_bar.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('full player exposes playback, queue, and library actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);

    final engine = _FakePlaybackAudioEngine()..supportsPitchValue = true;
    final player = PlayerController(audioEngine: engine);
    final library = LibraryStore();
    final first = _track('first', title: 'First Song', durationSeconds: 240)
        .copyWith(
          chapters: <TrackChapter>[
            TrackChapter(start: Duration.zero, title: 'Introduction'),
            TrackChapter(
              start: const Duration(minutes: 1),
              title: 'Main section',
            ),
          ],
          skipSegments: <TrackSkipSegment>[
            TrackSkipSegment(
              start: const Duration(seconds: 30),
              end: const Duration(seconds: 45),
              label: 'Intro',
            ),
          ],
          transcriptUri: Uri.parse('https://example.test/episode.vtt'),
          transcriptType: 'text/vtt',
          transcriptLanguage: 'en',
          sourceId: 'youtube-data-metadata',
          externalId: 'video-123',
        );
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
            podcastTranscriptLoader: (_) async => const PodcastTranscriptDocument(
              text: 'Podcast transcript text',
              contentType: 'text/plain',
            ),
            sponsorBlockSegmentLoader: (_, {required maximum, categories = sponsorBlockCategories}) async => <TrackSkipSegment>[
              TrackSkipSegment(
                start: const Duration(seconds: 90),
                end: const Duration(seconds: 100),
                label: 'SponsorBlock: sponsor',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('First Song'), findsOneWidget);
    expect(
      find.byKey(const Key('now-playing-artwork-palette')),
      findsOneWidget,
    );
    expect(find.text('Track 1 of 2'), findsOneWidget);
    expect(find.byKey(const Key('now-playing-seek')), findsOneWidget);
    expect(find.byKey(const Key('now-playing-volume')), findsOneWidget);
    expect(find.byKey(const Key('now-playing-skip-backward')), findsOneWidget);
    expect(find.byKey(const Key('now-playing-skip-forward')), findsOneWidget);
    expect(find.byKey(const Key('now-playing-pitch')), findsOneWidget);
    expect(find.byKey(const Key('now-playing-chapters')), findsOneWidget);
    expect(
      find.byKey(const Key('now-playing-chapter-marker-60000')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('now-playing-skip-segments')), findsOneWidget);
    expect(
      find.byKey(const Key('now-playing-podcast-transcript')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('now-playing-import-sponsorblock-segments')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('now-playing-podcast-transcript')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('podcast-transcript-reader')), findsOneWidget);
    expect(find.text('Podcast transcript text'), findsOneWidget);
    await tester.tap(find.byKey(const Key('podcast-transcript-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('podcast-transcript-reader')), findsNothing);
    await tester.tap(
      find.byKey(const Key('now-playing-import-sponsorblock-segments')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Import SponsorBlock segments?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    expect(
      library.tracks.first.skipSegments.map((segment) => segment.label),
      contains('SponsorBlock: sponsor'),
    );
    expect(find.byTooltip('Add to favorites'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    final artworkSemantics = tester.getSemantics(
      find.byKey(const Key('now-playing-artwork-semantics')),
    );
    expect(
      artworkSemantics.getSemanticsData().hasAction(SemanticsAction.increase),
      isTrue,
    );
    expect(
      artworkSemantics.getSemanticsData().hasAction(SemanticsAction.decrease),
      isFalse,
    );
    await tester.tap(find.byKey(const Key('now-playing-chapters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('now-playing-chapter-60000')));
    await tester.pump();
    expect(engine.positionValue, const Duration(minutes: 1));

    await tester.tap(find.byKey(const Key('now-playing-chapters-editor')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('now-playing-chapters-input')),
      '0:00 Opening\n2:00 Deep dive',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      library.tracks.first.chapters.map((chapter) => chapter.title),
      <String>['Opening', 'Deep dive'],
    );

    await tester.tap(find.byKey(const Key('now-playing-skip-segments-editor')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('now-playing-skip-segments-import')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('now-playing-skip-segments-export')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('now-playing-skip-segments-input')),
      '0:30-0:45 Intro\n2:30-2:45 Credits',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      library.tracks.first.skipSegments.map((segment) => segment.label),
      <String>['Intro', 'Credits'],
    );

    final volumeSlider = tester.widget<Slider>(
      find.byKey(const Key('now-playing-volume')),
    );
    volumeSlider.onChanged!(0.4);
    volumeSlider.onChangeEnd!(0.4);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('now-playing-shuffle')));
    await tester.tap(find.byKey(const Key('now-playing-repeat')));
    await tester.tap(find.byKey(const Key('now-playing-ab-repeat')));
    await tester.pump();
    expect(player.aBRepeatStart, const Duration(minutes: 1));
    expect(find.text('Set B'), findsOneWidget);
    await engine.seek(const Duration(minutes: 1, seconds: 12));
    await tester.pump();
    await tester.tap(find.byKey(const Key('now-playing-ab-repeat')));
    await tester.pump();
    expect(player.isABRepeatActive, isTrue);
    expect(find.text('Clear A-B'), findsOneWidget);
    final bookmarkPosition = player.position;
    await tester.tap(find.byKey(const Key('now-playing-add-bookmark')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('now-playing-bookmark-label')),
      'Chorus',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    final bookmark = library.bookmarksForTrack(first.id).single;
    expect(bookmark.position, bookmarkPosition);
    expect(bookmark.label, 'Chorus');
    expect(find.text('Chorus'), findsOneWidget);
    await engine.seek(const Duration(seconds: 5));
    await tester.pump();
    await tester.tap(find.byKey(Key('now-playing-bookmark-${bookmark.id}')));
    await tester.pump();
    expect(engine.positionValue, bookmark.position);
    final manageBookmarks = find.byKey(
      const Key('now-playing-manage-bookmarks'),
    );
    await tester.ensureVisible(manageBookmarks);
    await tester.tap(manageBookmarks);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rename bookmark'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('now-playing-bookmark-label')),
      'Bridge',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(library.bookmarksForTrack(first.id).single.label, 'Bridge');
    expect(find.text('Bridge'), findsWidgets);
    final secondBookmark = await library.addTrackBookmark(
      first.id,
      const Duration(minutes: 2),
      label: 'Verse',
    );
    expect(secondBookmark, isNotNull);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('bookmark-manager-select-${bookmark.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('bookmark-manager-select-${secondBookmark!.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Move selected bookmarks'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('now-playing-bookmark-folder')),
      'Song sections',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();
    expect(
      library.bookmarksForTrack(first.id).map((entry) => entry.folder),
      everyElement('Song sections'),
    );
    expect(find.text('Song sections'), findsOneWidget);
    await tester.tap(
      find.byKey(Key('bookmark-manager-select-${bookmark.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('bookmark-manager-select-${secondBookmark.id}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove selected bookmarks'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(library.bookmarksForTrack(first.id), isEmpty);
    await tester.tap(find.byTooltip('Close bookmarks'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('now-playing-speed')));
    await tester.pumpAndSettle();
    final speedItem = find.widgetWithText(CheckedPopupMenuItem<double>, '1.5x');
    await tester.ensureVisible(speedItem);
    await tester.tap(speedItem);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('now-playing-pitch')));
    await tester.pumpAndSettle();
    final pitchItem = find.widgetWithText(
      CheckedPopupMenuItem<double>,
      '1.25x',
    );
    await tester.ensureVisible(pitchItem);
    await tester.tap(pitchItem);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('now-playing-track-pitch')));
    await tester.pumpAndSettle();
    final trackPitchItem = find.byKey(
      const Key('now-playing-track-pitch-0.75'),
    );
    await tester.ensureVisible(trackPitchItem);
    await tester.tap(trackPitchItem);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('now-playing-track-speed')));
    await tester.pumpAndSettle();
    final trackSpeedItem = find.byKey(
      const Key('now-playing-track-speed-2.0'),
    );
    await tester.ensureVisible(trackSpeedItem);
    await tester.tap(trackSpeedItem);
    await tester.pumpAndSettle();
    final favoriteButton = find.byTooltip('Add to favorites');
    final lyricsButton = find.widgetWithText(TextButton, 'Lyrics');
    final queueButton = find.widgetWithText(TextButton, 'Queue');
    await tester.ensureVisible(favoriteButton);
    await tester.tap(favoriteButton);
    await tester.ensureVisible(lyricsButton);
    await tester.tap(lyricsButton);
    await tester.ensureVisible(queueButton);
    await tester.tap(queueButton);
    await tester.pump();

    expect(engine.shuffleValue, isTrue);
    expect(engine.loopModeValue, LoopMode.all);
    expect(engine.speedValue, 2);
    expect(engine.pitchValue, 0.75);
    expect(player.defaultPlaybackPitch, 1.25);
    expect(player.playbackPitchForTrack(first.id), 0.75);
    expect(library.playbackSpeedForTrack(first.id), 2);
    expect(engine.volumeValue, 0.4);
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
    final secondArtworkSemantics = tester.getSemantics(
      find.byKey(const Key('now-playing-artwork-semantics')),
    );
    expect(
      secondArtworkSemantics.getSemanticsData().hasAction(
        SemanticsAction.increase,
      ),
      isFalse,
    );
    expect(
      secondArtworkSemantics.getSemanticsData().hasAction(
        SemanticsAction.decrease,
      ),
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('podcast transcript reader retries a failed user request', (
    tester,
  ) async {
    final engine = _FakePlaybackAudioEngine();
    final player = PlayerController(audioEngine: engine);
    final library = LibraryStore();
    final track = _track(
      'transcript',
      title: 'Transcript episode',
      durationSeconds: 300,
    ).copyWith(transcriptUri: Uri.parse('https://example.test/episode.vtt'));
    await library.addTracks(<Track>[track]);
    await player.playTrack(track, queue: <Track>[track]);
    var requests = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: library),
          ChangeNotifierProvider<PlayerController>.value(value: player),
        ],
        child: MaterialApp(
          home: NowPlayingScreen(
            onOpenQueue: () {},
            onOpenLyrics: () {},
            podcastTranscriptLoader: (_) async {
              requests += 1;
              if (requests == 1) {
                throw const FormatException('Malformed transcript');
              }
              return const PodcastTranscriptDocument(
                text: '''
WEBVTT

00:00:03.000 --> 00:00:05.000
Recovered transcript
''',
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('now-playing-podcast-transcript')));
    await tester.pumpAndSettle();
    expect(find.text('Could not load the podcast transcript.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('Recovered transcript'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('podcast-transcript-cue-3000')),
    );
    await tester.pump();
    expect(engine.positionValue, const Duration(seconds: 3));
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

    final seekSlider = tester.widget<Slider>(
      find.byKey(const Key('player-bar-seek')),
    );
    expect(
      seekSlider.semanticFormatterCallback!(0),
      'Playback position 0:00 of 3:20',
    );

    await tester.tap(find.byKey(const Key('open-now-playing')));
    expect(nowPlayingOpens, 1);
  });

  testWidgets('desktop queue pane selects removes and opens queue actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final player = PlayerController(audioEngine: _FakePlaybackAudioEngine());
    final first = _track('first', title: 'First Song', durationSeconds: 240);
    final second = _track('second', title: 'Second Song', durationSeconds: 180);
    await player.playTrack(first, queue: <Track>[first, second]);
    var nowPlayingOpens = 0;
    var queueOpens = 0;

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerController>.value(
        value: player,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: DesktopQueuePane(
                onOpenNowPlaying: () => nowPlayingOpens += 1,
                onOpenQueue: () => queueOpens += 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('2 tracks'), findsOneWidget);
    await tester.tap(find.byTooltip('Open queue editor'));
    await tester.tap(find.text('Second Song').last);
    await tester.pump();

    expect(player.current?.id, 'second');
    expect(queueOpens, 1);
    await tester.tap(find.byTooltip('Remove from queue').first);
    await tester.pump();

    expect(player.queue.map((track) => track.id), <String>['second']);
    await tester.tap(find.text('Second Song').first);
    expect(nowPlayingOpens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop queue pane clears upcoming tracks and the active queue', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final player = PlayerController(audioEngine: _FakePlaybackAudioEngine());
    final first = _track('first', title: 'First Song', durationSeconds: 240);
    final second = _track('second', title: 'Second Song', durationSeconds: 180);
    await player.playTrack(first, queue: <Track>[first, second]);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerController>.value(
        value: player,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: DesktopQueuePane(
                onOpenNowPlaying: () {},
                onOpenQueue: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Clear upcoming tracks'));
    await tester.pumpAndSettle();
    expect(find.text('Clear upcoming tracks?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(player.queue, <Track>[first]);
    expect(player.current, first);

    await tester.tap(find.byTooltip('Clear queue'));
    await tester.pumpAndSettle();
    expect(find.text('Clear queue?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(player.queue, isEmpty);
    expect(player.current, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop queue resize handle reports drag changes and completion', (
    tester,
  ) async {
    var accumulatedDelta = 0.0;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopQueuePaneResizeHandle(
            onDragUpdate: (delta) => accumulatedDelta += delta,
            onDragEnd: () => completed = true,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('desktop-queue-pane-resize'))),
    );
    await gesture.moveBy(const Offset(-36, 0));
    await gesture.up();

    expect(accumulatedDelta, lessThan(0));
    expect(completed, isTrue);
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

class _FakePlaybackAudioEngine
    implements PlaybackAudioEngine, PitchPlaybackAudioEngine {
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
  double speedValue = 1;
  double pitchValue = 1;
  bool supportsPitchValue = false;
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
  Duration get bufferedPosition => positionValue;

  @override
  double get speed => speedValue;

  @override
  bool get supportsPitch => supportsPitchValue;

  @override
  double get pitch => pitchValue;

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
  Future<void> setSpeed(double speed) async {
    speedValue = speed;
  }

  @override
  Future<void> setPitch(double pitch) async {
    if (!supportsPitchValue) {
      throw UnsupportedError('Pitch control is unavailable for this backend.');
    }
    pitchValue = pitch;
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
