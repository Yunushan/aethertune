import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/l10n/app_localizations.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_store.dart';
import 'package:aethertune/src/data/itunes_podcast_directory.dart';
import 'package:aethertune/src/data/local_folder_watch_store.dart';
import 'package:aethertune/src/data/podcast_rss_provider.dart';
import 'package:aethertune/src/data/self_hosted_provider_store.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/home_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'retains provider search results and retries the failed cursor',
    (tester) async {
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
      final provider = _PagedSearchProvider();

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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeScreen(
              initialTab: 4,
              providerSearchProviders: <MusicSourceProvider>[provider],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Search library and providers',
      );
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(searchField, 300, scrollable: scrollable);
      await tester.enterText(searchField, 'aether');
      await tester.tap(find.byTooltip('Search library and providers'));
      await tester.pumpAndSettle();

      expect(provider.calls, <String>['aether|initial|8']);
      final firstResult = find.byKey(
        const ValueKey<String>(
          'provider-search-result-paged-test-first-provider-result',
        ),
      );
      await tester.scrollUntilVisible(
        firstResult,
        300,
        scrollable: scrollable,
      );
      expect(find.text('First Provider Result'), findsOneWidget);

      final loadMore = find.byKey(
        const ValueKey<String>('provider-search-load-more'),
      );
      await tester.scrollUntilVisible(loadMore, 300, scrollable: scrollable);
      final providerSearchOffset = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;
      await library.setOfflineModeEnabled(true);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(loadMore, 300, scrollable: scrollable);
      expect(tester.widget<OutlinedButton>(loadMore).onPressed, isNull);
      expect(provider.calls, <String>['aether|initial|8']);

      await library.setOfflineModeEnabled(false);
      await tester.pumpAndSettle();
      tester
          .state<ScrollableState>(scrollable)
          .position
          .jumpTo(providerSearchOffset);
      await tester.pumpAndSettle();
      expect(loadMore, findsOneWidget);
      expect(tester.widget<OutlinedButton>(loadMore).onPressed, isNotNull);
      await tester.tap(loadMore);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        firstResult,
        -300,
        scrollable: scrollable,
      );
      expect(find.text('First Provider Result'), findsOneWidget);
      final loadMoreError = find.byKey(
        const ValueKey<String>(
          'provider-search-load-more-error-paged-test',
        ),
      );
      await tester.scrollUntilVisible(
        loadMoreError,
        300,
        scrollable: scrollable,
      );
      expect(loadMoreError, findsOneWidget);
      expect(find.text('Second Provider Result'), findsNothing);

      final retry = find.byKey(
        const ValueKey<String>('provider-search-load-more-retry'),
      );
      await tester.drag(scrollable, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();

      final secondResult = find.byKey(
        const ValueKey<String>(
          'provider-search-result-paged-test-second-provider-result',
        ),
      );
      await tester.scrollUntilVisible(
        firstResult,
        -300,
        scrollable: scrollable,
      );
      expect(find.text('First Provider Result'), findsOneWidget);
      await tester.scrollUntilVisible(
        secondResult,
        300,
        scrollable: scrollable,
      );
      expect(find.text('Second Provider Result'), findsOneWidget);
      expect(loadMore, findsNothing);
      expect(retry, findsNothing);
      expect(provider.searchCalls, 0);
      expect(provider.calls, <String>[
        'aether|initial|8',
        'aether|second|8',
        'aether|second|8',
      ]);
    },
  );

  testWidgets('uses a provider suggestion to launch unified search',
      (tester) async {
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
    final provider = _SuggestionSearchProvider();

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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            initialTab: 4,
            providerSearchProviders: <MusicSourceProvider>[provider],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Search library and providers',
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(searchField, 300, scrollable: scrollable);
    await tester.enterText(searchField, 'mi');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(provider.suggestionQueries, <String>['mi']);
    final suggestion = find.byKey(
      const ValueKey<String>('provider-search-suggestion-suggested-Mira Sol'),
    );
    await tester.scrollUntilVisible(suggestion, 100, scrollable: scrollable);
    expect(suggestion, findsOneWidget);
    await tester.tap(suggestion);
    await tester.pumpAndSettle();

    expect(provider.searchQueries, <String>['Mira Sol']);
    expect(find.text('Mira Sol Result'), findsOneWidget);

    await library.setOfflineModeEnabled(true);
    final offlineSearchField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Search library and providers',
      skipOffstage: false,
    );
    await tester.scrollUntilVisible(
      offlineSearchField,
      -300,
      scrollable: scrollable,
    );
    await tester.enterText(offlineSearchField, 'offline');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(provider.suggestionQueries, <String>['mi']);
  });

  testWidgets('finds a podcast directory result and subscribes to its RSS',
      (tester) async {
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
    var directoryRequests = 0;
    final directory = ItunesPodcastDirectory(
      loader: (_) async {
        directoryRequests += 1;
        return _podcastDirectoryResponse;
      },
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            initialTab: 4,
            podcastDirectory: directory,
            podcastProviderFactory: (feedUri) => PodcastRssProvider(
              feedUri: feedUri,
              feedLoader: (_) async => _podcastFeedXml,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final query = find.byKey(const Key('podcast-directory-query'));
    await tester.scrollUntilVisible(query, 300, scrollable: scrollable);
    await tester.enterText(query, 'aether');
    await tester.tap(find.byKey(const Key('podcast-directory-search')));
    await tester.pumpAndSettle();

    expect(directoryRequests, 1);
    expect(find.text('Aether Podcast'), findsOneWidget);
    final subscribe = find.byKey(
      const ValueKey<String>(
        'podcast-directory-subscribe-https://feeds.example.test/aether.xml',
      ),
    );
    await tester.scrollUntilVisible(subscribe, 200, scrollable: scrollable);
    await tester.tap(subscribe);
    await tester.pumpAndSettle();

    expect(library.podcastSubscriptions, hasLength(1));
    expect(library.podcastSubscriptions.single.title, 'Aether Podcast');
    expect(find.text('Aether Episode'), findsOneWidget);

    await library.setOfflineModeEnabled(true);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(query, -300, scrollable: scrollable);
    expect(
      tester.widget<IconButton>(
        find.byKey(const Key('podcast-directory-search')),
      ).onPressed,
      isNull,
    );
    expect(directoryRequests, 1);
    expect(tester.takeException(), isNull);
  });
}

const _podcastDirectoryResponse = '''
{
  "results": [
    {
      "collectionName": "Aether Podcast",
      "artistName": "Aether Studio",
      "primaryGenreName": "Technology",
      "feedUrl": "https://feeds.example.test/aether.xml"
    }
  ]
}
''';

const _podcastFeedXml = '''
<rss version="2.0">
  <channel>
    <title>Aether Podcast</title>
    <description>Open audio research.</description>
    <author>Aether Studio</author>
    <item>
      <guid>aether-episode-1</guid>
      <title>Aether Episode</title>
      <description>Episode one.</description>
      <enclosure url="https://cdn.example.test/aether.mp3" type="audio/mpeg" />
    </item>
  </channel>
</rss>
''';

final class _PagedSearchProvider implements MusicSourceSearchPagingProvider {
  final List<String> calls = <String>[];
  int continuationAttempts = 0;
  int searchCalls = 0;

  @override
  String get id => 'paged-test';

  @override
  String get name => 'Paged test provider';

  @override
  String get description => name;

  @override
  Set<MusicSourceCapability> get capabilities =>
      const <MusicSourceCapability>{MusicSourceCapability.metadataSearch};

  @override
  ProviderPrivacyDisclosure get disclosure =>
      const ProviderPrivacyDisclosure();

  @override
  Future<List<Track>> search(String query) async {
    searchCalls += 1;
    return const <Track>[];
  }

  @override
  Future<MusicSourceSearchPage> searchPage(
    String query, {
    String? cursor,
    int limit = 20,
  }) async {
    calls.add('$query|${cursor ?? 'initial'}|$limit');
    if (cursor == null) {
      return MusicSourceSearchPage(
        tracks: <Track>[
          Track(
            id: 'first-provider-result',
            title: 'First Provider Result',
            artist: 'Open Artist',
            sourceId: id,
          ),
        ],
        nextCursor: 'second',
      );
    }

    continuationAttempts += 1;
    if (continuationAttempts == 1) {
      throw StateError('Temporary provider failure.');
    }
    return MusicSourceSearchPage(
      tracks: <Track>[
        Track(
          id: 'second-provider-result',
          title: 'Second Provider Result',
          artist: 'Open Artist',
          sourceId: id,
        ),
      ],
    );
  }

  @override
  Future<Uri?> resolveStream(Track track) async => null;
}

final class _SuggestionSearchProvider
    implements MusicSourceSearchSuggestionProvider {
  final List<String> suggestionQueries = <String>[];
  final List<String> searchQueries = <String>[];

  @override
  String get id => 'suggested';

  @override
  String get name => 'Suggested provider';

  @override
  String get description => name;

  @override
  Set<MusicSourceCapability> get capabilities =>
      const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.searchSuggestions,
      };

  @override
  ProviderPrivacyDisclosure get disclosure =>
      const ProviderPrivacyDisclosure();

  @override
  Future<List<Track>> search(String query) async {
    searchQueries.add(query);
    return <Track>[
      Track(
        id: 'mira-result',
        title: 'Mira Sol Result',
        artist: 'Mira Sol',
        sourceId: id,
      ),
    ];
  }

  @override
  Future<Uri?> resolveStream(Track track) async => null;

  @override
  Future<List<MusicSourceSearchSuggestion>> suggest(
    String query, {
    int limit = 8,
  }) async {
    suggestionQueries.add(query);
    return const <MusicSourceSearchSuggestion>[
      MusicSourceSearchSuggestion(
        value: 'Mira Sol',
        kind: MusicSourceSearchSuggestionKind.artist,
      ),
    ];
  }
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
