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
