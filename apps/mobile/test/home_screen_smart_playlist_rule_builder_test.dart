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

  testWidgets('creates and persists nested smart playlist rule groups', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[
      Track(
        id: 'rock-track',
        title: 'Rock Track',
        artist: 'Mira',
        album: 'Signals',
        genre: 'Rock',
        localPath: '/music/rock.mp3',
      ),
      Track(
        id: 'played-jazz-track',
        title: 'Played Jazz Track',
        artist: 'Ari',
        album: 'Late Set',
        genre: 'Jazz',
        localPath: '/music/jazz.mp3',
      ),
      Track(
        id: 'unplayed-jazz-track',
        title: 'Unplayed Jazz Track',
        artist: 'Ari',
        album: 'Early Set',
        genre: 'Jazz',
        localPath: '/music/unplayed-jazz.mp3',
      ),
      Track(
        id: 'pop-track',
        title: 'Pop Track',
        artist: 'Noor',
        album: 'Daylight',
        genre: 'Pop',
        localPath: '/music/pop.mp3',
      ),
    ]);
    await library.recordPlayback('played-jazz-track');
    await library.recordPlayback('played-jazz-track');
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
          home: HomeScreen(initialTab: 2),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('smart-playlist-create'));
    await tester.enterText(
      find.byKey(const Key('smart-playlist-name')),
      'Rock or played jazz',
    );
    await _tapKey(tester, const Key('smart-playlist-add-rule-group'));

    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('smart-playlist-rule-group-match-mode-0'),
        ),
        matching: find.text('Match any'),
      ),
    );
    await tester.pumpAndSettle();
    await _addRule(tester, depth: 0, field: 'Exact genre', value: 'Rock');

    await _tapKey(
      tester,
      const ValueKey<String>('smart-playlist-add-nested-group-0'),
    );
    await _addRule(tester, depth: 1, field: 'Exact genre', value: 'Jazz');
    await _addRule(tester, depth: 1, field: 'Minimum plays', value: '2');
    await _tapKey(
      tester,
      const ValueKey<String>('smart-playlist-rule-group-save-1'),
    );
    await _tapKey(
      tester,
      const ValueKey<String>('smart-playlist-rule-group-save-0'),
    );
    await _tapKey(tester, const Key('smart-playlist-save'));

    expect(library.customSmartPlaylists, hasLength(1));
    final playlist = library.customSmartPlaylists.single;
    expect(playlist.name, 'Rock or played jazz');
    expect(playlist.ruleGroups, hasLength(1));
    final outerGroup = playlist.ruleGroups.single;
    expect(outerGroup.matchMode, CustomSmartPlaylistMatchMode.any);
    expect(outerGroup.rules.single.field, CustomSmartPlaylistRuleField.genre);
    expect(outerGroup.rules.single.value, 'Rock');
    expect(outerGroup.groups, hasLength(1));
    expect(
      outerGroup.groups.single.rules.map((rule) => rule.field),
      <CustomSmartPlaylistRuleField>[
        CustomSmartPlaylistRuleField.genre,
        CustomSmartPlaylistRuleField.minimumPlayCount,
      ],
    );
    expect(
      library
          .tracksForCustomSmartPlaylist(playlist.id)
          .map((track) => track.id)
          .toSet(),
      <String>{'rock-track', 'played-jazz-track'},
    );

    final restored = LibraryStore();
    await restored.load();
    addTearDown(restored.dispose);
    expect(restored.customSmartPlaylists.single.ruleGroups, hasLength(1));
    expect(
      restored.customSmartPlaylists.single.ruleGroups.single.groups,
      hasLength(1),
    );

    const depthRule = CustomSmartPlaylistRule(
      field: CustomSmartPlaylistRuleField.searchText,
      value: 'signal',
    );
    var deepGroup = CustomSmartPlaylistRuleGroup(
      rules: List<CustomSmartPlaylistRule>.generate(
        maxCustomSmartPlaylistRulesPerGroup,
        (index) => CustomSmartPlaylistRule(
          field: CustomSmartPlaylistRuleField.searchText,
          value: 'signal-$index',
        ),
      ),
    );
    for (
      var depth = 1;
      depth < maxCustomSmartPlaylistRuleGroupDepth;
      depth += 1
    ) {
      deepGroup = CustomSmartPlaylistRuleGroup(
        rules: const <CustomSmartPlaylistRule>[depthRule],
        groups: <CustomSmartPlaylistRuleGroup>[deepGroup],
      );
    }
    final fillerGroup = CustomSmartPlaylistRuleGroup(
      rules: const <CustomSmartPlaylistRule>[depthRule],
    );
    await library.updateCustomSmartPlaylist(
      playlist.id,
      name: playlist.name,
      query: playlist.query,
      sourceId: playlist.sourceId,
      artist: playlist.artist,
      album: playlist.album,
      genre: playlist.genre,
      minimumDurationSeconds: playlist.minimumDurationSeconds,
      maximumDurationSeconds: playlist.maximumDurationSeconds,
      favoritesOnly: playlist.favoritesOnly,
      minimumPlayCount: playlist.minimumPlayCount,
      minimumDaysSinceLastPlayed: playlist.minimumDaysSinceLastPlayed,
      matchMode: playlist.matchMode,
      ruleGroups: <CustomSmartPlaylistRuleGroup>[
        deepGroup,
        ...List<CustomSmartPlaylistRuleGroup>.filled(
          maxCustomSmartPlaylistGroupsPerGroup - 1,
          fillerGroup,
        ),
      ],
      sortMode: playlist.sortMode,
      limit: playlist.limit,
    );
    await tester.pumpAndSettle();

    final actionsKey = ValueKey<String>(
      'smart-playlist-actions-${playlist.id}',
    );
    await tester.scrollUntilVisible(
      find.byKey(actionsKey),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await _tapKey(tester, actionsKey);
    await tester.tap(find.text('Edit rules'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('smart-playlist-add-rule-group')),
          )
          .onPressed,
      isNull,
    );
    await _tapKey(
      tester,
      const ValueKey<String>('smart-playlist-rule-group-0'),
    );
    for (
      var depth = 0;
      depth < maxCustomSmartPlaylistRuleGroupDepth - 1;
      depth += 1
    ) {
      await _tapKey(
        tester,
        ValueKey<String>('smart-playlist-nested-group-$depth-0'),
      );
    }

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey<String>('smart-playlist-add-rule-7')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(
              const ValueKey<String>('smart-playlist-add-nested-group-7'),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Rule limit reached'), findsOneWidget);
    expect(find.text('Maximum nesting depth reached'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _addRule(
  WidgetTester tester, {
  required int depth,
  required String field,
  required String value,
}) async {
  await _tapKey(tester, ValueKey<String>('smart-playlist-add-rule-$depth'));
  await _tapKey(tester, const Key('smart-playlist-rule-field'));
  await tester.tap(find.text(field).last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('smart-playlist-rule-value')),
    value,
  );
  await _tapKey(tester, const Key('smart-playlist-rule-save'));
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _TestPlaybackAudioEngine implements PlaybackAudioEngine {
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
