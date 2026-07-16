import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/l10n/app_localizations.dart';
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

  testWidgets('opens and saves a generated mood mix', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[
      Track(
        id: 'focus-one',
        title: 'Piano Focus',
        artist: 'Mira',
        album: 'Study Room',
        genre: 'Classical',
        localPath: '/music/focus-one.mp3',
      ),
      Track(
        id: 'focus-two',
        title: 'Deep Work',
        artist: 'Ari',
        album: 'Quiet Hours',
        genre: 'Lo-Fi',
        localPath: '/music/focus-two.mp3',
      ),
    ]);
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
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(initialTab: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Because of a recent addition'),
      findsNWidgets(2),
    );

    await tester.tap(find.text('Focus mix').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Play mix'), findsOneWidget);
    expect(find.byTooltip('Save mix as playlist'), findsOneWidget);
    expect(find.textContaining('2 generated track(s)'), findsOneWidget);

    await tester.tap(find.byTooltip('Save mix as playlist'));
    await tester.pumpAndSettle();

    expect(library.playlists, hasLength(1));
    expect(library.playlists.single.name, 'Focus mix');
    expect(
      library.playlists.single.trackIds,
      <String>['focus-one', 'focus-two'],
    );
    expect(find.text('Saved 2 tracks as Focus mix.'), findsOneWidget);
  });

  testWidgets('changes recommendation taste signals from Options', (
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
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(initialTab: 5),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final favoritesTile = find.widgetWithText(
      SwitchListTile,
      'Use favorites in For you',
    );
    await Scrollable.ensureVisible(
      tester.element(favoritesTile),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(favoritesTile).value, isTrue);

    await tester.tap(favoritesTile);
    await tester.pumpAndSettle();
    expect(library.recommendationFavoriteSignalsEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(favoritesTile).value, isFalse);

    final historyTile = find.widgetWithText(
      SwitchListTile,
      'Use listening history in For you',
    );
    await Scrollable.ensureVisible(
      tester.element(historyTile),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(historyTile).value, isTrue);

    await tester.tap(historyTile);
    await tester.pumpAndSettle();
    expect(library.recommendationHistorySignalsEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(historyTile).value, isFalse);
  });

  testWidgets('opens full artist and album pages with collection actions', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[
      Track(
        id: 'ari-dawn',
        title: 'Morning Signal',
        artist: 'Ari',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 3),
        localPath: '/music/Ari/Dawn/morning.mp3',
      ),
      Track(
        id: 'ari-dusk',
        title: 'Evening Signal',
        artist: 'Ari',
        album: 'Dusk',
        genre: 'Ambient',
        duration: const Duration(minutes: 4),
        localPath: '/music/Ari/Dusk/evening.mp3',
      ),
      Track(
        id: 'mia-dawn',
        title: 'Blue Dawn',
        artist: 'Mia',
        album: 'Dawn',
        genre: 'Jazz',
        duration: const Duration(minutes: 5),
        localPath: '/music/Mia/Dawn/blue.mp3',
      ),
    ]);
    addTearDown(library.dispose);

    final selfHosted = SelfHostedProviderStore();
    await selfHosted.load();
    addTearDown(selfHosted.dispose);
    final sync = LibrarySyncStore();
    await sync.load();
    addTearDown(sync.dispose);
    final folderWatch = LocalFolderWatchStore()..updateLibrary(library);
    addTearDown(folderWatch.dispose);
    final audioEngine = _TestPlaybackAudioEngine();
    final player = PlayerController(audioEngine: audioEngine);
    addTearDown(player.dispose);

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
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(initialTab: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Artists'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('browse-artist-ari')));
    await tester.pumpAndSettle();

    expect(find.text('Artist'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Shuffle'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Radio'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Save playlist'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pumpAndSettle();
    expect(player.current?.id, 'ari-dawn');
    expect(player.queue.map((track) => track.id), <String>[
      'ari-dawn',
      'ari-dusk',
    ]);
    expect(audioEngine.playCalled, isTrue);
    expect(player.shuffleEnabled, isFalse);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Shuffle'));
    await tester.pumpAndSettle();
    expect(player.shuffleEnabled, isTrue);
    expect(player.queue.map((track) => track.id), <String>[
      'ari-dawn',
      'ari-dusk',
    ]);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Radio'));
    await tester.pumpAndSettle();
    expect(player.current?.id, 'ari-dawn');
    expect(player.queue.map((track) => track.id), <String>[
      'ari-dawn',
      'ari-dusk',
      'mia-dawn',
    ]);
    expect(find.text('Started 3-track Ari radio.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Save playlist'));
    await tester.pumpAndSettle();
    expect(library.playlists, hasLength(1));
    expect(library.playlists.single.name, 'Ari');

    final relatedArtist = find.byKey(
      const ValueKey<String>('related-artist-mia'),
    );
    await tester.scrollUntilVisible(
      relatedArtist,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Related artists'), findsOneWidget);
    expect(relatedArtist, findsOneWidget);
    expect(find.textContaining('Shared album'), findsOneWidget);

    final duskAlbum = find.byKey(const ValueKey<String>('artist-album-dusk'));
    await tester.scrollUntilVisible(
      duskAlbum,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(duskAlbum);
    await tester.pumpAndSettle();

    expect(find.text('Album'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('view-album-artist')),
      findsOneWidget,
    );
    final relatedAlbum = find.byKey(
      const ValueKey<String>('related-album-dawn'),
    );
    await tester.scrollUntilVisible(
      relatedAlbum,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(relatedAlbum, findsOneWidget);
    expect(find.textContaining('Shared artist, genre'), findsOneWidget);

    final albumPlayButton = find.widgetWithText(FilledButton, 'Play');
    await tester.scrollUntilVisible(
      albumPlayButton,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    tester.view.physicalSize = const Size(1100, 800);
    await tester.pumpAndSettle();
    expect(albumPlayButton, findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Radio'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Save playlist'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('previews and persists a listening recap visual theme', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[
      Track(
        id: 'recap-track',
        title: 'Recap Track',
        artist: 'Mira',
        album: 'Signals',
        genre: 'Rock',
        duration: const Duration(minutes: 4),
        localPath: '/music/recap-track.mp3',
      ),
    ]);
    await library.recordPlayback('recap-track');
    final monthlyRecap = library.listeningRecaps(
      period: LibraryRecapPeriod.month,
      limit: 1,
    ).single;
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
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(initialTab: 3),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final recapButton = find.byKey(
      ValueKey<String>(
        'listening-recap-preview-month-'
        '${monthlyRecap.start.year}-'
        '${monthlyRecap.start.month}',
      ),
    );
    await tester.scrollUntilVisible(
      recapButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(recapButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('listening-recap-preview-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('listening-recap-card-midnight'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('listening-recap-theme-signal')),
    );
    await tester.pumpAndSettle();

    expect(
      library.listeningRecapVisualTheme,
      ListeningRecapVisualTheme.signal,
    );
    expect(
      find.byKey(const ValueKey<String>('listening-recap-card-signal')),
      findsOneWidget,
    );
    final restored = LibraryStore();
    await restored.load();
    addTearDown(restored.dispose);
    expect(
      restored.listeningRecapVisualTheme,
      ListeningRecapVisualTheme.signal,
    );
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('listening-recap-card-signal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('listening-recap-save-png')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestPlaybackAudioEngine implements PlaybackAudioEngine {
  bool playCalled = false;
  bool _shuffleModeEnabled = false;

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
  bool get shuffleModeEnabled => _shuffleModeEnabled;

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
  Future<void> play() async {
    playCalled = true;
  }

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
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _shuffleModeEnabled = enabled;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}
