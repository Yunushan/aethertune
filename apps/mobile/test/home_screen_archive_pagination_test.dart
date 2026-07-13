import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/internet_archive_provider.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_store.dart';
import 'package:aethertune/src/data/local_folder_watch_store.dart';
import 'package:aethertune/src/data/self_hosted_provider_store.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/home_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('retains Archive results after a failed continuation and retries', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final selfHosted = SelfHostedProviderStore();
    await selfHosted.load();
    addTearDown(selfHosted.dispose);
    final sync = LibrarySyncStore();
    await sync.load();
    addTearDown(sync.dispose);
    final folderWatch = LocalFolderWatchStore()..updateLibrary(library);
    addTearDown(folderWatch.dispose);
    final player = PlayerController(audioEngine: _TestPlaybackAudioEngine());
    addTearDown(player.dispose);

    var pageTwoAttempts = 0;
    final provider = InternetArchiveProvider(
      limit: 1,
      searchLoader: (uri) async {
        switch (uri.queryParameters['page']) {
          case '1':
            return _searchJson(<String>['first']);
          case '2':
            pageTwoAttempts += 1;
            if (pageTwoAttempts == 1) {
              throw StateError('Archive temporarily unavailable.');
            }
            return _searchJson(<String>['second']);
          default:
            throw StateError('Unexpected archive page.');
        }
      },
      metadataLoader: (uri) async => _metadataJson(uri.pathSegments.last),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: library),
          ChangeNotifierProvider<SelfHostedProviderStore>.value(
            value: selfHosted,
          ),
          ChangeNotifierProvider<LibrarySyncStore>.value(value: sync),
          ChangeNotifierProvider<LocalFolderWatchStore>.value(
            value: folderWatch,
          ),
          ChangeNotifierProvider<PlayerController>.value(value: player),
        ],
        child: MaterialApp(
          home: HomeScreen(
            initialTab: 4,
            internetArchiveProvider: provider,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final archiveSearch = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Archive search',
    );
    await tester.scrollUntilVisible(archiveSearch, 300);
    await tester.enterText(archiveSearch, 'ambient');
    await tester.tap(find.byTooltip('Search archive audio'));
    await tester.pumpAndSettle();

    expect(find.text('Archive first'), findsOneWidget);
    final loadMore = find.textContaining('Load more archive results');
    await tester.scrollUntilVisible(loadMore, 300);
    await tester.tap(loadMore);
    await tester.pumpAndSettle();

    expect(find.text('Archive first'), findsOneWidget);
    expect(find.text('Could not load more archive audio'), findsOneWidget);

    await tester.tap(find.byTooltip('Retry loading archive results'));
    await tester.pumpAndSettle();

    expect(find.text('Archive first'), findsOneWidget);
    expect(find.text('Archive second'), findsOneWidget);
    expect(find.text('All 2 archive results loaded.'), findsOneWidget);
    expect(pageTwoAttempts, 2);
  });
}

String _searchJson(List<String> identifiers) {
  return jsonEncode(<String, Object?>{
    'response': <String, Object?>{
      'numFound': 2,
      'docs': identifiers
          .map(
            (identifier) => <String, Object?>{
              'identifier': identifier,
              'title': 'Archive $identifier',
            },
          )
          .toList(growable: false),
    },
  });
}

String _metadataJson(String identifier) {
  return jsonEncode(<String, Object?>{
    'metadata': <String, Object?>{
      'identifier': identifier,
      'title': 'Archive $identifier',
      'creator': 'AetherTune test archive',
    },
    'files': <Object?>[
      <String, Object?>{
        'name': '$identifier.mp3',
        'format': 'VBR MP3',
        'length': '30',
      },
    ],
  });
}

class _TestPlaybackAudioEngine implements PlaybackAudioEngine {
  @override
  Stream<Object?> get stateChanges => const Stream<Object?>.empty();

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<ProcessingState> get processingStateStream =>
      const Stream<ProcessingState>.empty();

  @override
  Stream<int?> get currentIndexStream => const Stream<int?>.empty();

  @override
  bool get playing => false;

  @override
  bool get shuffleModeEnabled => false;

  @override
  LoopMode get loopMode => LoopMode.off;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  double get speed => 1;

  @override
  double get volume => 1;

  @override
  bool get hasNext => false;

  @override
  bool get hasPrevious => false;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position, {int? index}) async {}

  @override
  Future<void> seekToNext() async {}

  @override
  Future<void> seekToPrevious() async {}

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}
