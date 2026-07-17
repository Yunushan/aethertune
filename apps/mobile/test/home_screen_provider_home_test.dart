import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/l10n/app_localizations.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_store.dart';
import 'package:aethertune/src/data/local_folder_watch_store.dart';
import 'package:aethertune/src/data/internet_archive_provider.dart';
import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/data/radio_browser_provider.dart';
import 'package:aethertune/src/data/self_hosted_provider_store.dart';
import 'package:aethertune/src/data/spotify_metadata_provider.dart';
import 'package:aethertune/src/data/spotify_oauth_client.dart';
import 'package:aethertune/src/data/spotify_settings_store.dart';
import 'package:aethertune/src/data/youtube_channel_follow_store.dart';
import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';
import 'package:aethertune/src/data/youtube_data_settings_store.dart';
import 'package:aethertune/src/domain/music_catalog_discovery_provider.dart';
import 'package:aethertune/src/domain/music_catalog_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/self_hosted_provider_account.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/home_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'loads server discovery explicitly and opens a catalog collection',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = _FakeProviderHomeCatalog();
      final fixture = await _HomeFixture.create(provider: provider);
      addTearDown(fixture.dispose);
      await _pumpHome(tester, fixture);

      expect(find.text('From your servers'), findsOneWidget);
      expect(find.text('Your local feed is empty'), findsOneWidget);
      expect(provider.browseCalls, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey<String>('provider-home-refresh')),
      );
      await tester.pumpAndSettle();

      expect(provider.browseCalls, <MusicCatalogCollectionKind>[
        MusicCatalogCollectionKind.album,
        MusicCatalogCollectionKind.playlist,
      ]);
      expect(find.text('Test Server albums'), findsOneWidget);
      expect(find.text('Test Server playlists'), findsOneWidget);
      expect(find.text('Server Album'), findsOneWidget);
      expect(find.text('Server Playlist'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('provider-home-errors')),
        findsNothing,
      );

      final albumTile = find.byKey(
        const ValueKey<String>(
          'provider-home-collection-test-provider-album-album-1',
        ),
      );
      await tester.tap(albumTile);
      await tester.pumpAndSettle();

      expect(provider.loadCalls.map((collection) => collection.id), <String>[
        'album-1',
      ]);
      expect(find.text('Remote Song'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await fixture.selfHosted.testAndSave(
        fixture.account.copyWith(name: 'Renamed Server'),
        'rotated-secret',
      );
      await tester.pumpAndSettle();

      expect(albumTile, findsNothing);
      expect(find.text('From your servers'), findsOneWidget);
      expect(find.text('Your local feed is empty'), findsOneWidget);
    },
  );

  testWidgets('renders provider-specific discovery without an album fallback', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final provider = _FakeProviderHomeDiscoveryCatalog();
    final fixture = await _HomeFixture.create(provider: provider);
    addTearDown(fixture.dispose);
    await _pumpHome(tester, fixture);

    expect(provider.discoveryCalls, isEmpty);
    expect(provider.browseCalls, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('provider-home-refresh')),
    );
    await tester.pumpAndSettle();

    expect(provider.discoveryCalls, <MusicCatalogDiscoveryKind>[
      MusicCatalogDiscoveryKind.recentlyAdded,
    ]);
    expect(provider.browseCalls, <MusicCatalogCollectionKind>[
      MusicCatalogCollectionKind.playlist,
    ]);
    expect(find.text('Test Server recently added'), findsOneWidget);
    expect(find.text('Newest albums reported by this server'), findsOneWidget);
    expect(find.text('Latest Server Album'), findsOneWidget);
    expect(find.text('Test Server playlists'), findsOneWidget);
    expect(find.text('Test Server albums'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'surfaces recently added server albums by artists the user follows',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = _FakeProviderHomeDiscoveryCatalog();
      final fixture = await _HomeFixture.create(provider: provider);
      addTearDown(fixture.dispose);
      await fixture.library.setArtistFollowed('Remote Artist', true);
      await _pumpHome(tester, fixture);

      await tester.tap(
        find.byKey(const ValueKey<String>('provider-home-refresh')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Test Server from artists you follow'),
        findsOneWidget,
      );
      expect(
        find.text('Recently added albums by artists you follow'),
        findsOneWidget,
      );
      expect(find.text('Latest Server Album'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps desktop server discovery offline without requests', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 800);
    addTearDown(tester.view.reset);

    final provider = _FakeProviderHomeCatalog();
    final fixture = await _HomeFixture.create(provider: provider);
    addTearDown(fixture.dispose);
    await fixture.library.setOfflineModeEnabled(true);
    await _pumpHome(tester, fixture);

    expect(find.text('From your servers'), findsOneWidget);
    expect(find.text('Offline mode'), findsNWidgets(3));
    final refresh = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('provider-home-refresh')),
    );
    expect(refresh.onPressed, isNull);
    expect(provider.browseCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads more from a paged server discovery shelf', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1200);
    addTearDown(tester.view.reset);

    final provider = _FakePagedProviderHomeDiscoveryCatalog();
    final fixture = await _HomeFixture.create(provider: provider);
    addTearDown(fixture.dispose);
    await _pumpHome(tester, fixture);

    await tester.tap(
      find.byKey(const ValueKey<String>('provider-home-refresh')),
    );
    await tester.pumpAndSettle();

    expect(find.text('First Server Album'), findsOneWidget);
    expect(find.text('Second Server Album'), findsNothing);
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'provider-home-load-more-test-provider-recentlyAdded',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(provider.discoveryPageCalls, <String>[
      'recentlyAdded:0:6',
      'recentlyAdded:1:6',
    ]);
    expect(find.text('Second Server Album'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loads an explicit official music chart on Home', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final fixture = await _HomeFixture.create(
      provider: _FakeProviderHomeCatalog(),
    );
    addTearDown(fixture.dispose);
    final requestedRegions = <String>[];
    final youtube = YouTubeDataSettingsStore(
      credentialVault: _MemoryCredentialVault(),
      providerFactory: (apiKey) => YouTubeDataMetadataProvider(
        apiKey: apiKey,
        videosLoader: (uri) async {
          requestedRegions.add(uri.queryParameters['regionCode']!);
          return _youTubeChartPage;
        },
      ),
    );
    await youtube.load();
    await youtube.saveApiKey('project-key');
    addTearDown(youtube.dispose);

    await _pumpHome(tester, fixture, youtube: youtube);

    expect(find.text('Official YouTube music chart'), findsOneWidget);
    expect(requestedRegions, isEmpty);
    final regionField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Region',
    );
    await tester.enterText(regionField, 'tr');
    await tester.tap(
      find.byKey(const ValueKey<String>('home-youtube-music-chart-refresh')),
    );
    await tester.pumpAndSettle();

    expect(requestedRegions, <String>['TR']);
    expect(youtube.preferredRegion, 'TR');
    expect(find.text('Home chart result'), findsOneWidget);
    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();
    expect(fixture.library.tracks.single.isPlayable, isFalse);

    await fixture.library.setOfflineModeEnabled(true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(
              const ValueKey<String>('home-youtube-music-chart-refresh'),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(requestedRegions, <String>['TR']);
  });

  testWidgets('loads popular public radio stations explicitly on Home', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1200);
    addTearDown(tester.view.reset);

    final fixture = await _HomeFixture.create(
      provider: _FakeProviderHomeCatalog(),
    );
    addTearDown(fixture.dispose);
    Uri? requestedUri;
    final radio = RadioBrowserProvider(
      baseUri: Uri.parse('https://radio.example.test'),
      searchLoader: (uri) async {
        requestedUri = uri;
        return _popularRadioStationsPage;
      },
    );

    await _pumpHome(tester, fixture, radioBrowserProvider: radio);

    expect(find.text('Popular radio stations'), findsOneWidget);
    expect(requestedUri, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('home-popular-radio-refresh')),
    );
    await tester.pumpAndSettle();

    expect(requestedUri!.queryParameters.containsKey('name'), isFalse);
    expect(requestedUri!.queryParameters['limit'], '6');
    expect(requestedUri!.queryParameters['order'], 'clickcount');
    expect(requestedUri!.queryParameters['reverse'], 'true');
    expect(find.text('Aether Radio'), findsOneWidget);
    await tester.tap(find.byTooltip('Save station to library').first);
    await tester.pumpAndSettle();
    expect(fixture.library.tracks.single.isPlayable, isTrue);

    await fixture.library.setOfflineModeEnabled(true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey<String>('home-popular-radio-refresh')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('loads popular public Archive audio explicitly on Home', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1200);
    addTearDown(tester.view.reset);

    final fixture = await _HomeFixture.create(
      provider: _FakeProviderHomeCatalog(),
    );
    addTearDown(fixture.dispose);
    Uri? requestedSearchUri;
    final archive = InternetArchiveProvider(
      baseUri: Uri.parse('https://archive.example.test'),
      searchLoader: (uri) async {
        requestedSearchUri = uri;
        return _popularArchiveSearchPage;
      },
      metadataLoader: (_) async => _popularArchiveItemMetadata,
    );

    await _pumpHome(tester, fixture, internetArchiveProvider: archive);

    expect(find.text('Popular Archive audio'), findsOneWidget);
    expect(requestedSearchUri, isNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('home-popular-archive-refresh')),
    );
    await tester.pumpAndSettle();

    expect(requestedSearchUri!.path, '/advancedsearch.php');
    expect(requestedSearchUri!.queryParameters['q'], 'mediatype:audio');
    expect(requestedSearchUri!.queryParametersAll['sort[]'], <String>[
      'downloads desc',
    ]);
    expect(requestedSearchUri!.queryParameters['rows'], '6');
    expect(
      requestedSearchUri!.queryParametersAll.containsKey('facet[]'),
      isFalse,
    );
    expect(find.text('Public Archive Session'), findsOneWidget);

    await tester.tap(find.text('Public Archive Session'));
    await tester.pumpAndSettle();
    expect(find.text('Archive item'), findsOneWidget);
    expect(find.text('Playable files'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await fixture.library.setOfflineModeEnabled(true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(
              const ValueKey<String>('home-popular-archive-refresh'),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('loads followed YouTube channel metadata explicitly on Home', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1200);
    addTearDown(tester.view.reset);

    final fixture = await _HomeFixture.create(
      provider: _FakeProviderHomeCatalog(),
    );
    addTearDown(fixture.dispose);
    final requestedChannelIds = <String>[];
    final youtube = YouTubeDataSettingsStore(
      credentialVault: _MemoryCredentialVault(),
      providerFactory: (apiKey) => YouTubeDataMetadataProvider(
        apiKey: apiKey,
        searchLoader: (uri) async {
          final channelId = uri.queryParameters['channelId']!;
          requestedChannelIds.add(channelId);
          return switch (channelId) {
            'channel-one' => _followedChannelPage(
              'Earlier followed upload',
              'one',
              '2026-07-01T00:00:00Z',
            ),
            _ => _followedChannelPage(
              'Latest followed upload',
              'two',
              '2026-07-02T00:00:00Z',
            ),
          };
        },
      ),
    );
    final follows = YouTubeChannelFollowStore();
    await Future.wait<void>(<Future<void>>[youtube.load(), follows.load()]);
    await youtube.saveApiKey('project-key');
    await follows.setFollowed(
      const YouTubeDataChannel(id: 'channel-one', title: 'One'),
      true,
    );
    await follows.setFollowed(
      const YouTubeDataChannel(id: 'channel-two', title: 'Two'),
      true,
    );
    addTearDown(youtube.dispose);
    addTearDown(follows.dispose);

    await _pumpHome(
      tester,
      fixture,
      youtube: youtube,
      youtubeFollows: follows,
    );

    expect(find.text('Followed YouTube channels'), findsOneWidget);
    expect(requestedChannelIds, isEmpty);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('home-youtube-followed-channels-refresh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedChannelIds.toSet(), <String>{'channel-one', 'channel-two'});
    expect(find.text('Latest followed upload'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Latest followed upload')).dy,
      lessThan(tester.getTopLeft(find.text('Earlier followed upload')).dy),
    );
    final saveButton = find.byTooltip('Save metadata to library').first;
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(fixture.library.tracks.single.isPlayable, isFalse);

    await fixture.library.setOfflineModeEnabled(true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(
              const ValueKey<String>(
                'home-youtube-followed-channels-refresh',
              ),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(requestedChannelIds.toSet(), <String>{'channel-one', 'channel-two'});
  });

  testWidgets('loads connected Spotify library metadata explicitly on Home', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1200);
    addTearDown(tester.view.reset);

    final fixture = await _HomeFixture.create(
      provider: _FakeProviderHomeCatalog(),
    );
    addTearDown(fixture.dispose);
    final requests = <String>[];
    final spotify = SpotifySettingsStore(
      credentialVault: _MemoryCredentialVault(),
      authorizationRunner: (_) async => SpotifyOAuthToken(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.utc(2030),
      ),
      providerFactory: (readAccessToken) => SpotifyMetadataProvider(
        accessTokenReader: readAccessToken,
        savedTracksLoader: (uri, token) async {
          requests.add('tracks:${uri.queryParameters['offset']}');
          return _spotifySavedTracksPage;
        },
        savedAlbumsLoader: (uri, token) async {
          requests.add('albums:${uri.queryParameters['offset']}');
          return _spotifySavedAlbumsPage;
        },
        playlistsLoader: (uri, token) async {
          requests.add('playlists:${uri.queryParameters['offset']}');
          return _spotifySavedPlaylistsPage;
        },
      ),
    );
    await spotify.load();
    await spotify.connect('test-client');
    addTearDown(spotify.dispose);

    await _pumpHome(tester, fixture, spotify: spotify);

    expect(find.text('Your Spotify library'), findsOneWidget);
    expect(requests, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('home-spotify-library-refresh')),
    );
    await tester.pumpAndSettle();

    expect(requests, <String>['tracks:0']);
    expect(find.text('Home saved Spotify track'), findsOneWidget);
    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();
    expect(fixture.library.tracks.single.isPlayable, isFalse);

    await tester.tap(find.byKey(const ValueKey<String>('home-spotify-albums')));
    await tester.tap(
      find.byKey(const ValueKey<String>('home-spotify-library-refresh')),
    );
    await tester.pumpAndSettle();
    expect(requests, <String>['tracks:0', 'albums:0']);
    expect(find.text('Home saved Spotify album'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('home-spotify-playlists')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('home-spotify-library-refresh')),
    );
    await tester.pumpAndSettle();
    expect(requests, <String>['tracks:0', 'albums:0', 'playlists:0']);
    expect(find.text('Home saved Spotify playlist'), findsOneWidget);

    await fixture.library.setOfflineModeEnabled(true);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byKey(
              const ValueKey<String>('home-spotify-library-refresh'),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(requests, <String>['tracks:0', 'albums:0', 'playlists:0']);
  });
}

Future<void> _pumpHome(
  WidgetTester tester,
  _HomeFixture fixture, {
  YouTubeDataSettingsStore? youtube,
  YouTubeChannelFollowStore? youtubeFollows,
  SpotifySettingsStore? spotify,
  InternetArchiveProvider? internetArchiveProvider,
  RadioBrowserProvider? radioBrowserProvider,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>.value(value: fixture.library),
        ChangeNotifierProvider<SelfHostedProviderStore>.value(
          value: fixture.selfHosted,
        ),
        ChangeNotifierProvider<LibrarySyncStore>.value(value: fixture.sync),
        ChangeNotifierProvider<LocalFolderWatchStore>.value(
          value: fixture.folderWatch,
        ),
        ChangeNotifierProvider<PlayerController>.value(value: fixture.player),
        if (youtube != null)
          ChangeNotifierProvider<YouTubeDataSettingsStore>.value(
            value: youtube,
          ),
        if (youtubeFollows != null)
          ChangeNotifierProvider<YouTubeChannelFollowStore>.value(
            value: youtubeFollows,
          ),
        if (spotify != null)
          ChangeNotifierProvider<SpotifySettingsStore>.value(value: spotify),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          initialTab: 0,
          internetArchiveProvider: internetArchiveProvider,
          radioBrowserProvider: radioBrowserProvider,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _youTubeChartPage = '''
{
  "pageInfo": {"totalResults": 1},
  "items": [{
    "id": "home-chart-result",
    "snippet": {
      "title": "Home chart result",
      "channelTitle": "Official Channel"
    }
  }]
}
''';

const _spotifySavedTracksPage = '''
{
  "offset": 0,
  "total": 1,
  "next": null,
  "items": [{
    "added_at": "2026-07-17T12:00:00Z",
    "track": {
      "id": "spotify-home-saved-track",
      "name": "Home saved Spotify track",
      "artists": [{"name": "Aether"}],
      "album": {"name": "Signals"}
    }
  }]
}
''';

const _spotifySavedAlbumsPage = '''
{
  "offset": 0,
  "total": 1,
  "next": null,
  "items": [{
    "added_at": "2026-07-17T12:00:00Z",
    "album": {
      "id": "spotify-home-album",
      "name": "Home saved Spotify album",
      "total_tracks": 1,
      "artists": [{"name": "Aether"}]
    }
  }]
}
''';

const _spotifySavedPlaylistsPage = '''
{
  "offset": 0,
  "total": 1,
  "next": null,
  "items": [{
    "id": "spotify-home-playlist",
    "name": "Home saved Spotify playlist",
    "owner": {"display_name": "Aether"},
    "tracks": {"total": 1}
  }]
}
''';

const _popularRadioStationsPage = '''
[
  {
    "stationuuid": "popular-station-one",
    "name": "Aether Radio",
    "url_resolved": "https://stream.example.test/aether",
    "tags": "ambient, electronic",
    "countrycode": "US",
    "language": "english",
    "codec": "AAC",
    "bitrate": 128,
    "lastcheckok": 1
  },
  {
    "stationuuid": "popular-station-two",
    "name": "Signal Radio",
    "url_resolved": "https://stream.example.test/signal",
    "tags": "indie",
    "countrycode": "GB",
    "language": "english",
    "codec": "MP3",
    "bitrate": 192,
    "lastcheckok": 1
  }
]
''';

const _popularArchiveSearchPage = '''
{
  "response": {
    "numFound": 1,
    "docs": [
      {"identifier": "public_archive_session"}
    ]
  }
}
''';

const _popularArchiveItemMetadata = '''
{
  "metadata": {
    "identifier": "public_archive_session",
    "title": "Public Archive Session",
    "creator": "Open Artist",
    "year": "2024",
    "collection": "opensource_audio"
  },
  "files": [
    {
      "name": "public-session.mp3",
      "format": "VBR MP3",
      "title": "Public Session",
      "source": "original",
      "length": "120"
    }
  ]
}
''';

String _followedChannelPage(String title, String id, String publishedAt) => '''
{
  "items": [{
    "id": {"videoId": "$id"},
    "snippet": {
      "title": "$title",
      "channelTitle": "Aether Radio",
      "publishedAt": "$publishedAt"
    }
  }]
}
''';

final class _HomeFixture {
  _HomeFixture({
    required this.library,
    required this.selfHosted,
    required this.sync,
    required this.folderWatch,
    required this.player,
    required this.account,
  });

  final LibraryStore library;
  final SelfHostedProviderStore selfHosted;
  final LibrarySyncStore sync;
  final LocalFolderWatchStore folderWatch;
  final PlayerController player;
  final SelfHostedProviderAccount account;

  static Future<_HomeFixture> create({
    required MusicCatalogProvider provider,
  }) async {
    final library = LibraryStore();
    await library.load();
    final account = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.jellyfin,
      name: 'Test Server',
      baseUrl: 'https://music.example.test',
      identity: 'user-1',
      allowInsecureHttp: false,
    );
    final selfHosted = SelfHostedProviderStore(
      credentialVault: _MemoryCredentialVault(),
      connectionTester: (_, __) async {},
      providerFactory: (_, __) => provider,
    );
    await selfHosted.load();
    await selfHosted.testAndSave(account, 'secret');
    final sync = LibrarySyncStore();
    await sync.load();
    final folderWatch = LocalFolderWatchStore()..updateLibrary(library);
    final player = PlayerController(audioEngine: _TestPlaybackAudioEngine());
    return _HomeFixture(
      library: library,
      selfHosted: selfHosted,
      sync: sync,
      folderWatch: folderWatch,
      player: player,
      account: account,
    );
  }

  Future<void> dispose() async {
    folderWatch.dispose();
    sync.dispose();
    selfHosted.dispose();
    library.dispose();
    player.dispose();
  }
}

final class _MemoryCredentialVault implements ProviderCredentialVault {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String accountId) async => _values[accountId];

  @override
  Future<void> write(String accountId, String secret) async {
    _values[accountId] = secret;
  }

  @override
  Future<void> delete(String accountId) async {
    _values.remove(accountId);
  }
}

final class _FakeProviderHomeCatalog implements MusicCatalogProvider {
  final List<MusicCatalogCollectionKind> browseCalls =
      <MusicCatalogCollectionKind>[];
  final List<MusicCatalogCollection> loadCalls = <MusicCatalogCollection>[];

  @override
  String get id => 'test-provider';

  @override
  String get name => 'Test Server';

  @override
  String get description => 'Provider Home fixture';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
    MusicSourceCapability.libraryBrowse,
    MusicSourceCapability.playlists,
    MusicSourceCapability.streamResolution,
  };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
    networkDomains: <String>['music.example.test'],
    dataSent: <String>['catalog request', 'account credential'],
    requiresUserCredentials: true,
  );

  @override
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  ) async {
    browseCalls.add(kind);
    return switch (kind) {
      MusicCatalogCollectionKind.album => const <MusicCatalogCollection>[
        MusicCatalogCollection(
          id: 'album-1',
          title: 'Server Album',
          kind: MusicCatalogCollectionKind.album,
          subtitle: 'Remote Artist',
          itemCount: 1,
        ),
      ],
      MusicCatalogCollectionKind.playlist => const <MusicCatalogCollection>[
        MusicCatalogCollection(
          id: 'playlist-1',
          title: 'Server Playlist',
          kind: MusicCatalogCollectionKind.playlist,
          itemCount: 1,
        ),
      ],
      MusicCatalogCollectionKind.artist => const <MusicCatalogCollection>[],
    };
  }

  @override
  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  ) async {
    loadCalls.add(collection);
    return MusicCatalogDetail(
      collection: collection,
      tracks: <Track>[
        Track(
          id: 'remote-song',
          title: 'Remote Song',
          artist: 'Remote Artist',
          album: collection.title,
          sourceId: id,
          externalId: 'remote-song',
        ),
      ],
    );
  }

  @override
  Future<Uint8List?> loadArtwork(
    String artworkId, {
    String? version,
    int maxWidth = 512,
  }) async {
    return null;
  }

  @override
  Future<List<Track>> search(String query) async => const <Track>[];

  @override
  Future<Uri?> resolveStream(Track track) async {
    return Uri.parse('https://music.example.test/stream/${track.id}');
  }
}

final class _FakeProviderHomeDiscoveryCatalog
    extends _FakeProviderHomeCatalog
    implements MusicCatalogDiscoveryProvider {
  final List<MusicCatalogDiscoveryKind> discoveryCalls =
      <MusicCatalogDiscoveryKind>[];

  @override
  List<MusicCatalogDiscoveryKind> get discoveryKinds =>
      const <MusicCatalogDiscoveryKind>[
        MusicCatalogDiscoveryKind.recentlyAdded,
      ];

  @override
  Future<List<MusicCatalogCollection>> browseDiscoveryCollections(
    MusicCatalogDiscoveryKind kind, {
    int limit = 6,
  }) async {
    discoveryCalls.add(kind);
    return const <MusicCatalogCollection>[
      MusicCatalogCollection(
        id: 'album-latest',
        title: 'Latest Server Album',
        kind: MusicCatalogCollectionKind.album,
        subtitle: 'Remote Artist',
        itemCount: 1,
      ),
    ];
  }
}

final class _FakePagedProviderHomeDiscoveryCatalog
    extends _FakeProviderHomeCatalog
    implements MusicCatalogDiscoveryPagingProvider {
  final List<String> discoveryPageCalls = <String>[];

  @override
  List<MusicCatalogDiscoveryKind> get discoveryKinds =>
      const <MusicCatalogDiscoveryKind>[
        MusicCatalogDiscoveryKind.recentlyAdded,
      ];

  @override
  Set<MusicCatalogDiscoveryKind> get pagedDiscoveryKinds =>
      const <MusicCatalogDiscoveryKind>{
        MusicCatalogDiscoveryKind.recentlyAdded,
      };

  @override
  Future<List<MusicCatalogCollection>> browseDiscoveryCollections(
    MusicCatalogDiscoveryKind kind, {
    int limit = 6,
  }) async => const <MusicCatalogCollection>[];

  @override
  Future<MusicCatalogCollectionPage> browseDiscoveryCollectionsPage(
    MusicCatalogDiscoveryKind kind, {
    int offset = 0,
    int limit = 6,
  }) async {
    discoveryPageCalls.add('${kind.name}:$offset:$limit');
    return switch (offset) {
      0 => const MusicCatalogCollectionPage(
        collections: <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'first-server-album',
            title: 'First Server Album',
            kind: MusicCatalogCollectionKind.album,
          ),
        ],
        nextOffset: 1,
        hasMore: true,
      ),
      _ => const MusicCatalogCollectionPage(
        collections: <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'second-server-album',
            title: 'Second Server Album',
            kind: MusicCatalogCollectionKind.album,
          ),
        ],
        nextOffset: 2,
        hasMore: false,
      ),
    };
  }
}

final class _TestPlaybackAudioEngine implements PlaybackAudioEngine {
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
