import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/music_catalog_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/self_hosted_browse_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('browses, filters, plays, and saves a self-hosted library', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final provider = _FakeCatalogProvider();
    final library = LibraryStore();
    final engine = _FakePlaybackAudioEngine();
    final player = PlayerController(
      audioEngine: engine,
      trackResolver: (track) async {
        final stream = await provider.resolveStream(track);
        return track.copyWith(
          streamUrl: stream?.toString(),
          streamUrlIsEphemeral: true,
        );
      },
    );
    addTearDown(player.dispose);

    await tester.pumpWidget(
      _testApp(provider: provider, library: library, player: player),
    );
    await tester.pumpAndSettle();

    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Open Artist'), findsOneWidget);
    expect(provider.artworkCalls, isNotEmpty);

    await tester.enterText(
      find.byKey(const Key('catalog-filter-artist')),
      'ambient',
    );
    await tester.pump();
    expect(find.text('Ambient Artist'), findsOneWidget);
    expect(find.text('Open Artist'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('catalog-filter-artist')),
      '',
    );
    await tester.pump();
    await tester.tap(find.text('Open Artist'));
    await tester.pumpAndSettle();

    expect(find.text('Blue Rooms'), findsOneWidget);
    await tester.tap(find.text('Blue Rooms'));
    await tester.pumpAndSettle();

    expect(find.text('Aether Session'), findsOneWidget);
    expect(find.text('Local Cloud'), findsOneWidget);
    await tester.tap(find.byKey(const Key('catalog-play-all')));
    await tester.pumpAndSettle();

    expect(engine.queue, hasLength(2));
    expect(engine.queue.first.title, 'Aether Session');
    expect(engine.queue.first.streamUrl, contains('/stream/song-1'));
    expect(player.current!.streamUrlIsEphemeral, isTrue);

    await tester.tap(find.byKey(const Key('catalog-save-all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(library.tracks, hasLength(2));
    expect(find.text('Saved 2 track(s).'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows all catalog tabs without overflow on desktop', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    final provider = _FakeCatalogProvider();
    final player = PlayerController(audioEngine: _FakePlaybackAudioEngine());
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _testApp(
        provider: provider,
        library: LibraryStore(),
        player: player,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.text('Blue Rooms'), findsOneWidget);

    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    expect(find.text('Late Night'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates renames and deletes remote playlists', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final provider = _FakeCatalogProvider();
    final player = PlayerController(audioEngine: _FakePlaybackAudioEngine());
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _testApp(
        provider: provider,
        library: LibraryStore(),
        player: player,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-create-playlist')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('remote-playlist-name')),
      'Morning Focus',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('Morning Focus'), findsOneWidget);
    expect(provider.mutationCalls, contains('create:Morning Focus:'));

    await tester.tap(
      find.byKey(const Key('catalog-playlist-actions-playlist-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('remote-playlist-name')),
      'Morning Drive',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(find.text('Morning Drive'), findsOneWidget);
    expect(find.text('Morning Focus'), findsNothing);
    expect(provider.mutationCalls, contains('rename:playlist-2:Morning Drive'));

    await tester.tap(
      find.byKey(const Key('catalog-playlist-actions-playlist-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Morning Drive'), findsNothing);
    expect(provider.mutationCalls, contains('delete:playlist-2'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('adds reorders and removes remote playlist tracks', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final provider = _FakeCatalogProvider();
    final player = PlayerController(audioEngine: _FakePlaybackAudioEngine());
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _testApp(
        provider: provider,
        library: LibraryStore(),
        player: player,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blue Rooms'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('catalog-track-actions-track-song-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Add to remote playlist'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('remote-playlist-choice-playlist-1')),
    );
    await tester.pumpAndSettle();

    expect(provider.mutationCalls, contains('add:playlist-1:song-1'));
    expect(provider.playlistTrackIds('playlist-1'), <String>[
      'song-3',
      'song-4',
      'song-1',
    ]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Late Night'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('catalog-track-actions-track-song-3')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Move down'));
    await tester.pumpAndSettle();
    expect(provider.playlistTrackIds('playlist-1'), <String>[
      'song-4',
      'song-3',
      'song-1',
    ]);

    await tester.tap(
      find.byKey(const Key('catalog-track-actions-track-song-3')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ListTile, 'Remove from playlist'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(provider.playlistTrackIds('playlist-1'), <String>[
      'song-4',
      'song-1',
    ]);
    expect(find.text('Playlist Cut'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote playlist failures preserve the current catalog', (
    tester,
  ) async {
    final provider = _FakeCatalogProvider(mutationFailuresRemaining: 1);
    final player = PlayerController(audioEngine: _FakePlaybackAudioEngine());
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _testApp(
        provider: provider,
        library: LibraryStore(),
        player: player,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog-create-playlist')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('remote-playlist-name')),
      'Rejected Mix',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Remote playlist update failed'), findsOneWidget);
    expect(find.text('Rejected Mix'), findsNothing);
    expect(find.text('Late Night'), findsOneWidget);
    expect(provider.mutationCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline mode performs no catalog requests', (tester) async {
    final provider = _FakeCatalogProvider();
    final library = LibraryStore();
    await library.setOfflineModeEnabled(true);
    final player = PlayerController(audioEngine: _FakePlaybackAudioEngine());
    addTearDown(player.dispose);

    await tester.pumpWidget(
      _testApp(provider: provider, library: library, player: player),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Self-hosted browsing is unavailable in offline mode.'),
      findsOneWidget,
    );
    expect(provider.browseCalls, isEmpty);
  });

  testWidgets('failed catalog loads can be retried', (tester) async {
    final provider = _FakeCatalogProvider(artistFailuresRemaining: 1);
    final player = PlayerController(audioEngine: _FakePlaybackAudioEngine());
    addTearDown(player.dispose);

    await tester.pumpWidget(
      _testApp(
        provider: provider,
        library: LibraryStore(),
        player: player,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Test Server request failed'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Open Artist'), findsOneWidget);
    expect(
      provider.browseCalls
          .where((kind) => kind == MusicCatalogCollectionKind.artist),
      hasLength(2),
    );
  });

  testWidgets('failed collection details can be retried', (tester) async {
    final provider = _FakeCatalogProvider(albumFailuresRemaining: 1);
    final player = PlayerController(audioEngine: _FakePlaybackAudioEngine());
    addTearDown(player.dispose);

    await tester.pumpWidget(
      _testApp(
        provider: provider,
        library: LibraryStore(),
        player: player,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blue Rooms'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Album detail request failed'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Aether Session'), findsOneWidget);
    expect(
      provider.loadCalls.where(
        (collection) => collection.kind == MusicCatalogCollectionKind.album,
      ),
      hasLength(2),
    );
  });
}

Widget _testApp({
  required MusicCatalogProvider provider,
  required LibraryStore library,
  required PlayerController player,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LibraryStore>.value(value: library),
      ChangeNotifierProvider<PlayerController>.value(value: player),
    ],
    child: MaterialApp(home: SelfHostedBrowseScreen(provider: provider)),
  );
}

class _FakeCatalogProvider
    implements MusicCatalogProvider, MusicPlaylistMutationProvider {
  _FakeCatalogProvider({
    this.artistFailuresRemaining = 0,
    this.albumFailuresRemaining = 0,
    this.mutationFailuresRemaining = 0,
  }) {
    _playlistTracks['playlist-1'] = <Track>[
      _track('song-3', 'Playlist Cut'),
      _track('song-4', 'Night Signal'),
    ];
  }

  int artistFailuresRemaining;
  int albumFailuresRemaining;
  int mutationFailuresRemaining;
  final List<MusicCatalogCollectionKind> browseCalls =
      <MusicCatalogCollectionKind>[];
  final List<MusicCatalogCollection> loadCalls = <MusicCatalogCollection>[];
  final List<String> artworkCalls = <String>[];
  final List<String> mutationCalls = <String>[];
  final List<MusicCatalogCollection> _playlists =
      <MusicCatalogCollection>[
    const MusicCatalogCollection(
      id: 'playlist-1',
      title: 'Late Night',
      kind: MusicCatalogCollectionKind.playlist,
      subtitle: '2 tracks',
      itemCount: 2,
      artworkId: 'playlist-cover-1',
    ),
  ];
  final Map<String, List<Track>> _playlistTracks = <String, List<Track>>{};

  @override
  String get id => 'test-self-hosted';

  @override
  String get name => 'Test Server';

  @override
  String get description => 'Test self-hosted catalog';

  @override
  Set<MusicSourceCapability> get capabilities =>
      const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.libraryBrowse,
        MusicSourceCapability.playlists,
        MusicSourceCapability.playlistMutation,
        MusicSourceCapability.artwork,
        MusicSourceCapability.offlineCache,
        MusicSourceCapability.downloads,
        MusicSourceCapability.authentication,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
        networkDomains: <String>['music.example.test'],
        dataSent: <String>['catalog request', 'account credential'],
        requiresUserCredentials: true,
        cachesMetadata: true,
        cachesMedia: true,
        supportsDownloads: true,
      );

  @override
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  ) async {
    browseCalls.add(kind);
    if (kind == MusicCatalogCollectionKind.artist &&
        artistFailuresRemaining > 0) {
      artistFailuresRemaining -= 1;
      throw StateError('Test Server request failed.');
    }
    return switch (kind) {
      MusicCatalogCollectionKind.artist => const <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'artist-1',
            title: 'Open Artist',
            kind: MusicCatalogCollectionKind.artist,
            subtitle: '2 albums',
            artworkId: 'artist-cover-1',
          ),
          MusicCatalogCollection(
            id: 'artist-2',
            title: 'Ambient Artist',
            kind: MusicCatalogCollectionKind.artist,
            subtitle: '1 album',
          ),
        ],
      MusicCatalogCollectionKind.album => const <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'album-1',
            title: 'Blue Rooms',
            kind: MusicCatalogCollectionKind.album,
            subtitle: 'Open Artist',
            artworkId: 'album-cover-1',
          ),
        ],
      MusicCatalogCollectionKind.playlist =>
        List<MusicCatalogCollection>.unmodifiable(_playlists),
    };
  }

  @override
  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  ) async {
    loadCalls.add(collection);
    if (collection.kind == MusicCatalogCollectionKind.album &&
        albumFailuresRemaining > 0) {
      albumFailuresRemaining -= 1;
      throw StateError('Album detail request failed.');
    }
    if (collection.kind == MusicCatalogCollectionKind.artist) {
      return MusicCatalogDetail(
        collection: collection,
        collections: const <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'album-1',
            title: 'Blue Rooms',
            kind: MusicCatalogCollectionKind.album,
            subtitle: 'Open Artist · 2024',
            artworkId: 'album-cover-1',
          ),
        ],
      );
    }
    return MusicCatalogDetail(
      collection: collection,
      tracks: collection.kind == MusicCatalogCollectionKind.playlist
          ? List<Track>.unmodifiable(
              _playlistTracks[collection.id] ?? const <Track>[],
            )
          : <Track>[
              _track('song-1', 'Aether Session'),
              _track('song-2', 'Local Cloud'),
            ],
    );
  }

  @override
  Future<List<Track>> search(String query) async => const <Track>[];

  @override
  Future<Uint8List?> loadArtwork(
    String artworkId, {
    String? version,
    int maxWidth = 512,
  }) async {
    artworkCalls.add('$artworkId@$maxWidth');
    return base64Decode(_tinyPngBase64);
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    return Uri.parse(
      'https://music.example.test/stream/${track.externalId}',
    );
  }

  @override
  Future<void> createPlaylist(
    String name, {
    List<String> trackIds = const <String>[],
  }) async {
    _failMutationIfNeeded();
    final id = 'playlist-${_playlists.length + 1}';
    mutationCalls.add('create:$name:${trackIds.join(',')}');
    _playlistTracks[id] = trackIds.map(_trackForId).toList(growable: true);
    _playlists.add(
      MusicCatalogCollection(
        id: id,
        title: name,
        kind: MusicCatalogCollectionKind.playlist,
        subtitle: '${trackIds.length} tracks',
        itemCount: trackIds.length,
      ),
    );
  }

  @override
  Future<void> renamePlaylist(String playlistId, String name) async {
    _failMutationIfNeeded();
    mutationCalls.add('rename:$playlistId:$name');
    final index = _playlists.indexWhere((item) => item.id == playlistId);
    final current = _playlists[index];
    _playlists[index] = MusicCatalogCollection(
      id: current.id,
      title: name,
      kind: current.kind,
      subtitle: current.subtitle,
      itemCount: current.itemCount,
      artworkId: current.artworkId,
      artworkVersion: current.artworkVersion,
    );
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _failMutationIfNeeded();
    mutationCalls.add('delete:$playlistId');
    _playlists.removeWhere((item) => item.id == playlistId);
    _playlistTracks.remove(playlistId);
  }

  @override
  Future<void> addPlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    _failMutationIfNeeded();
    mutationCalls.add('add:$playlistId:${trackIds.join(',')}');
    _playlistTracks[playlistId]!.addAll(trackIds.map(_trackForId));
    _syncPlaylistCount(playlistId);
  }

  @override
  Future<void> replacePlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    _failMutationIfNeeded();
    mutationCalls.add('replace:$playlistId:${trackIds.join(',')}');
    _playlistTracks[playlistId] =
        trackIds.map(_trackForId).toList(growable: true);
    _syncPlaylistCount(playlistId);
  }

  List<String> playlistTrackIds(String playlistId) {
    return (_playlistTracks[playlistId] ?? const <Track>[])
        .map((track) => track.externalId!)
        .toList(growable: false);
  }

  Track _trackForId(String externalId) {
    return switch (externalId) {
      'song-1' => _track(externalId, 'Aether Session'),
      'song-2' => _track(externalId, 'Local Cloud'),
      'song-3' => _track(externalId, 'Playlist Cut'),
      'song-4' => _track(externalId, 'Night Signal'),
      _ => _track(externalId, externalId),
    };
  }

  void _syncPlaylistCount(String playlistId) {
    final index = _playlists.indexWhere((item) => item.id == playlistId);
    final current = _playlists[index];
    final count = _playlistTracks[playlistId]?.length ?? 0;
    _playlists[index] = MusicCatalogCollection(
      id: current.id,
      title: current.title,
      kind: current.kind,
      subtitle: '$count tracks',
      itemCount: count,
      artworkId: current.artworkId,
      artworkVersion: current.artworkVersion,
    );
  }

  void _failMutationIfNeeded() {
    if (mutationFailuresRemaining <= 0) {
      return;
    }
    mutationFailuresRemaining -= 1;
    throw StateError('Remote playlist update failed.');
  }

  Track _track(String externalId, String title) {
    return Track(
      id: 'track-$externalId',
      title: title,
      artist: 'Open Artist',
      album: 'Blue Rooms',
      duration: const Duration(minutes: 3),
      sourceId: id,
      externalId: externalId,
      providerArtworkId: 'album-cover-1',
    );
  }
}

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA'
    'CklEQVR4nGMAAQAABQABDQotxAAAAABJRU5ErkJggg==';

class _FakePlaybackAudioEngine implements PlaybackAudioEngine {
  List<Track> queue = <Track>[];
  bool playingValue = false;
  bool shuffleValue = false;
  LoopMode loopModeValue = LoopMode.off;
  int currentIndex = 0;

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
  bool get playing => playingValue;

  @override
  bool get shuffleModeEnabled => shuffleValue;

  @override
  LoopMode get loopMode => loopModeValue;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

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
  }

  @override
  Future<void> play() async => playingValue = true;

  @override
  Future<void> pause() async => playingValue = false;

  @override
  Future<void> stop() async => playingValue = false;

  @override
  Future<void> seek(Duration position, {int? index}) async {
    currentIndex = index ?? currentIndex;
  }

  @override
  Future<void> seekToNext() async => currentIndex += 1;

  @override
  Future<void> seekToPrevious() async => currentIndex -= 1;

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    shuffleValue = enabled;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async => loopModeValue = mode;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}
