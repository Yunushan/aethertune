import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/podcast_subscription.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('creates manual playlists with existing tracks only', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 1),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);

    final playlist = await store.createPlaylist(
      '  Road Mix  ',
      trackIds: <String>['1', 'missing', '2', '1'],
    );

    expect(playlist.name, 'Road Mix');
    expect(store.playlists, hasLength(1));
    expect(store.playlists.single.trackIds, <String>['1', '2']);
    expect(
      store
          .tracksForPlaylist(playlist.id)
          .map((track) => track.id)
          .toList(growable: false),
      <String>['1', '2'],
    );
  });

  test('adds and removes tracks without duplicating playlist entries', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 2),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);
    final playlist = await store.createPlaylist('Favorites');

    await store.addTrackToPlaylist(playlist.id, '1');
    await store.addTrackToPlaylist(playlist.id, '1');
    await store.addTrackToPlaylist(playlist.id, '2');
    await store.removeTrackFromPlaylist(playlist.id, '1');

    expect(store.playlistById(playlist.id)!.trackIds, <String>['2']);
  });

  test('reorders playlist tracks by index', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 2, 12),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2'), _track('3')]);
    final playlist = await store.createPlaylist(
      'Ordered',
      trackIds: <String>['1', '2', '3'],
    );

    await store.moveTrackInPlaylist(playlist.id, 2, 0);

    expect(store.playlistById(playlist.id)!.trackIds, <String>['3', '1', '2']);

    await store.moveTrackInPlaylist(playlist.id, 0, 2);
    await store.moveTrackInPlaylist(playlist.id, -1, 2);
    await store.moveTrackInPlaylist(playlist.id, 0, 99);

    expect(store.playlistById(playlist.id)!.trackIds, <String>['1', '2', '3']);
  });

  test('saves queue track order as a playlist', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 2, 18),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2'), _track('3')]);

    final playlist = await store.createPlaylist(
      'Queue Save',
      trackIds: <String>['3', 'missing', '1', '2'],
    );

    expect(playlist.name, 'Queue Save');
    expect(playlist.trackIds, <String>['3', '1', '2']);
    expect(
      store.tracksForPlaylist(playlist.id).map((track) => track.id),
      <String>['3', '1', '2'],
    );
  });

  test('filters playlist tracks without changing playlist order', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 2, 20),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Road One',
        artist: 'Ari',
        album: 'Home',
      ),
      _track(
        '2',
        title: 'Night Ride',
        artist: 'Road Crew',
        album: 'City',
      ),
      _track(
        '3',
        title: 'Archive Theme',
        artist: 'Orion',
        album: 'Road Album',
      ),
      _track(
        '4',
        title: 'Other Track',
        artist: 'Mia',
        album: 'Elsewhere',
      ),
    ]);
    final playlist = await store.createPlaylist(
      'Searchable',
      trackIds: <String>['3', '1', '2', '4'],
    );

    expect(
      store.tracksForPlaylist(playlist.id, query: '  road  ').map(
            (track) => track.id,
          ),
      <String>['3', '1', '2'],
    );
    expect(
      store.tracksForPlaylist(playlist.id, query: 'night').map(
            (track) => track.id,
          ),
      <String>['2'],
    );
    expect(
      store.tracksForPlaylist(playlist.id, query: 'orion').map(
            (track) => track.id,
          ),
      <String>['3'],
    );
    expect(store.tracksForPlaylist(playlist.id, query: 'missing'), isEmpty);
  });

  test('removing a library track removes it from playlists', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 3),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);
    final playlist = await store.createPlaylist(
      'Cleanup',
      trackIds: <String>['1', '2'],
    );

    await store.removeTrack('1');

    expect(store.playlistById(playlist.id)!.trackIds, <String>['2']);
  });

  test('persists playlists across store instances', () async {
    DateTime clock() => DateTime.utc(2026, 1, 4);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1')]);
    final playlist = await firstStore.createPlaylist(
      'Saved',
      trackIds: <String>['1'],
    );

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.playlists, hasLength(1));
    expect(secondStore.playlistById(playlist.id)!.name, 'Saved');
    expect(secondStore.tracksForPlaylist(playlist.id).single.id, '1');
  });

  test('exports and imports playlist JSON documents', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 4, 1),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track('1', title: 'First'),
      _track('2', title: 'Second'),
      _track('3', title: 'Third'),
    ]);
    final playlist = await store.createPlaylist(
      'Road JSON',
      trackIds: <String>['2', '1', '3'],
    );

    final document = store.exportPlaylistDocument(
      playlist.id,
      format: PlaylistDocumentFormat.json,
    );
    final decoded = jsonDecode(document) as Map<String, dynamic>;

    expect(decoded['type'], 'aethertune.playlist');
    expect((decoded['tracks'] as List<dynamic>), hasLength(3));

    await store.deletePlaylist(playlist.id);
    final imported = await store.importPlaylistDocument(
      document,
      format: PlaylistDocumentFormat.json,
    );

    expect(imported.name, 'Road JSON');
    expect(imported.trackIds, <String>['2', '1', '3']);
  });

  test('exports and imports M3U playlists by track path', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 4, 2),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track('1', title: 'Path One', artist: 'Ari'),
      _track('2', title: 'Path Two', artist: 'Mia'),
    ]);
    final playlist = await store.createPlaylist(
      'Road M3U',
      trackIds: <String>['2', '1'],
    );

    final document = store.exportPlaylistDocument(
      playlist.id,
      format: PlaylistDocumentFormat.m3u,
    );

    expect(document, contains('#EXTM3U'));
    expect(document, contains('#PLAYLIST:Road M3U'));
    expect(document, contains('/music/2.mp3'));

    await store.deletePlaylist(playlist.id);
    final imported = await store.importPlaylistDocument(
      document,
      format: PlaylistDocumentFormat.m3u,
    );

    expect(imported.name, 'Road M3U');
    expect(imported.trackIds, <String>['2', '1']);
  });

  test('exports and imports CSV playlists with quoted fields', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 4, 3),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Road, Theme',
        artist: 'Ari "Sky"',
        album: 'Comma Album',
      ),
      _track('2', title: 'Plain Track'),
    ]);
    final playlist = await store.createPlaylist(
      'Road CSV',
      trackIds: <String>['1', '2'],
    );

    final document = store.exportPlaylistDocument(
      playlist.id,
      format: PlaylistDocumentFormat.csv,
    );

    expect(document, contains('"Road, Theme"'));
    expect(document, contains('"Ari ""Sky"""'));

    await store.deletePlaylist(playlist.id);
    final imported = await store.importPlaylistDocument(
      document,
      format: PlaylistDocumentFormat.csv,
    );

    expect(imported.name, 'Road CSV');
    expect(imported.trackIds, <String>['1', '2']);
  });

  test('rejects playlist imports that do not match library tracks', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 4, 4),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);

    expect(
      store.importPlaylistDocument(
        '#EXTM3U\n#PLAYLIST:Missing\n/missing/file.mp3\n',
        format: PlaylistDocumentFormat.m3u,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(store.playlists, isEmpty);
  });

  test('saves and deletes plain lyrics for library tracks', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 5),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);

    await store.setLyrics('1', '  first line\nsecond line  ');

    expect(store.lyricsForTrack('1')!.plainText, 'first line\nsecond line');
    expect(store.lyricsForTrack('1')!.updatedAt, DateTime.utc(2026, 1, 5));

    await store.setLyrics('1', '   ');

    expect(store.lyricsForTrack('1'), isNull);
  });

  test('removing a library track removes its lyrics', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 6),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);
    await store.setLyrics('1', 'lyrics');

    await store.removeTrack('1');

    expect(store.lyricsForTrack('1'), isNull);
  });

  test('persists lyrics across store instances', () async {
    DateTime clock() => DateTime.utc(2026, 1, 7);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1')]);
    await firstStore.setLyrics('1', 'saved lyrics');

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.lyricsForTrack('1')!.plainText, 'saved lyrics');
  });

  test(
    'records recently played tracks with counts and last played time',
    () async {
      var now = DateTime.utc(2026, 1, 8, 12);
      final store = LibraryStore(clock: () => now);
      await store.load();
      await store.addTracks(<Track>[_track('1'), _track('2'), _track('3')]);

      await store.recordPlayback('1');
      now = DateTime.utc(2026, 1, 8, 12, 1);
      await store.recordPlayback('2');
      now = DateTime.utc(2026, 1, 8, 12, 2);
      await store.recordPlayback('1');
      await store.recordPlayback('missing');

      expect(
        store.playbackHistory.map((entry) => entry.trackId),
        <String>['1', '2', '1'],
      );
      expect(
        store.recentlyPlayedTracks().map((track) => track.id),
        <String>['1', '2'],
      );
      expect(
        store.recentlyPlayedTracks(limit: 1).map((track) => track.id),
        <String>['1'],
      );
      expect(store.playCountForTrack('1'), 2);
      expect(store.playCountForTrack('2'), 1);
      expect(store.lastPlayedAt('1'), DateTime.utc(2026, 1, 8, 12, 2));

      await store.clearPlaybackHistory();

      expect(store.playbackHistory, isEmpty);
    },
  );

  test('removing a library track removes its playback history', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 9),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);
    await store.recordPlayback('1');
    await store.recordPlayback('2');

    await store.removeTrack('1');

    expect(
      store.playbackHistory.map((entry) => entry.trackId),
      <String>['2'],
    );
  });

  test('persists playback history across store instances', () async {
    DateTime clock() => DateTime.utc(2026, 1, 10);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1')]);
    await firstStore.recordPlayback('1');

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.playbackHistory.single.trackId, '1');
    expect(secondStore.recentlyPlayedTracks().single.id, '1');
  });

  test('records persists and clears playback progress', () async {
    DateTime clock() => DateTime.utc(2026, 1, 14, 14);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('podcast')]);

    await firstStore.recordPlaybackProgress(
      'podcast',
      const Duration(minutes: 3),
      const Duration(minutes: 30),
    );

    expect(
      firstStore.playbackProgressForTrack('podcast')!.position,
      const Duration(minutes: 3),
    );

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(
      secondStore.playbackProgressForTrack('podcast')!.duration,
      const Duration(minutes: 30),
    );

    await secondStore.recordPlaybackProgress(
      'podcast',
      const Duration(seconds: 2),
      const Duration(minutes: 30),
    );

    expect(secondStore.playbackProgressForTrack('podcast'), isNull);

    await secondStore.recordPlaybackProgress(
      'podcast',
      const Duration(minutes: 10),
      const Duration(minutes: 30),
    );

    expect(secondStore.playbackProgressForTrack('podcast'), isNotNull);

    await secondStore.recordPlaybackProgress(
      'podcast',
      const Duration(minutes: 29, seconds: 45),
      const Duration(minutes: 30),
    );

    expect(secondStore.playbackProgressForTrack('podcast'), isNull);
  });

  test('saves persists and deletes podcast feed subscriptions', () async {
    var now = DateTime.utc(2026, 1, 15);
    DateTime clock() => now;
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();

    final subscription = await firstStore.savePodcastSubscription(
      PodcastSubscription(
        id: 'ignored',
        feedUrl: ' https://feeds.example.test/aether.xml ',
        title: ' Aether Radio ',
        description: ' Open feed ',
        author: ' Aether Hosts ',
        artworkUri: Uri.parse('https://media.example.test/show.jpg'),
      ),
    );
    await firstStore.savePodcastSubscription(
      PodcastSubscription(
        id: 'ignored-again',
        feedUrl: 'https://feeds.example.test/aether.xml',
        title: 'Aether Radio Updated',
      ),
    );

    expect(firstStore.podcastSubscriptions, hasLength(1));
    expect(
      firstStore.podcastSubscriptions.single.id,
      stablePodcastSubscriptionId('https://feeds.example.test/aether.xml'),
    );
    expect(firstStore.podcastSubscriptions.single.title, 'Aether Radio Updated');
    expect(subscription.addedAt, DateTime.utc(2026, 1, 15));

    now = DateTime.utc(2026, 1, 15, 6);
    final refreshed = await firstStore.markPodcastSubscriptionFetched(
      subscription.id,
    );

    expect(refreshed!.lastFetchedAt, DateTime.utc(2026, 1, 15, 6));
    expect(
      refreshed.isRefreshDue(
        DateTime.utc(2026, 1, 15, 17, 59),
      ),
      isFalse,
    );
    expect(
      refreshed.isRefreshDue(
        DateTime.utc(2026, 1, 15, 18),
      ),
      isTrue,
    );

    final failed = await firstStore.markPodcastSubscriptionFetchFailed(
      subscription.id,
      'network down',
    );

    expect(failed!.lastFetchError, 'network down');

    now = DateTime.utc(2026, 1, 15, 8);
    final recovered = await firstStore.markPodcastSubscriptionFetched(
      subscription.id,
    );

    expect(recovered!.lastFetchedAt, DateTime.utc(2026, 1, 15, 8));
    expect(recovered.lastFetchError, isEmpty);

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.podcastSubscriptions, hasLength(1));
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.feedUrl,
      'https://feeds.example.test/aether.xml',
    );
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.lastFetchedAt,
      DateTime.utc(2026, 1, 15, 8),
    );
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.lastFetchError,
      isEmpty,
    );

    await secondStore.deletePodcastSubscription(subscription.id);

    expect(secondStore.podcastSubscriptions, isEmpty);
  });

  test('sorts library searches and exposes recently added tracks', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'old',
        title: 'Gamma',
        artist: 'Zed',
        album: 'Third',
        addedAt: DateTime.utc(2026, 1, 1),
      ),
      _track(
        'middle',
        title: 'Alpha',
        artist: 'Mia',
        album: 'First',
        addedAt: DateTime.utc(2026, 1, 2),
      ),
      _track(
        'new',
        title: 'Beta',
        artist: 'Ari',
        album: 'Second',
        genre: 'Ambient',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
    ]);

    expect(
      store.recentlyAddedTracks().map((track) => track.id),
      <String>['new', 'middle', 'old'],
    );
    expect(
      store.recentlyAddedTracks(limit: 2).map((track) => track.id),
      <String>['new', 'middle'],
    );
    expect(
      store.search('').map((track) => track.id),
      <String>['new', 'middle', 'old'],
    );
    final titleSorted = store.search('', sortMode: LibrarySortMode.title);
    final artistSorted = store.search('', sortMode: LibrarySortMode.artist);
    final albumSorted = store.search('', sortMode: LibrarySortMode.album);

    expect(
      titleSorted.map((track) => track.title),
      <String>['Alpha', 'Beta', 'Gamma'],
    );
    expect(
      artistSorted.map((track) => track.artist),
      <String>['Ari', 'Mia', 'Zed'],
    );
    expect(
      albumSorted.map((track) => track.album),
      <String>['First', 'Second', 'Third'],
    );
    expect(store.search('ambient').single.id, 'new');
  });

  test('builds smart playlists from library and playback state', () async {
    var now = DateTime.utc(2026, 1, 14, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'old',
        title: 'Gamma',
        artist: 'Zed',
        addedAt: DateTime.utc(2026, 1, 1),
      ),
      _track(
        'middle',
        title: 'Alpha',
        artist: 'Ari',
        addedAt: DateTime.utc(2026, 1, 2),
      ),
      _track(
        'new',
        title: 'Beta',
        artist: 'Mia',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
    ]);

    await store.toggleFavorite('old');
    await store.toggleFavorite('middle');
    await store.recordPlayback('old');
    now = DateTime.utc(2026, 1, 14, 12, 1);
    await store.recordPlayback('new');
    now = DateTime.utc(2026, 1, 14, 12, 2);
    await store.recordPlayback('old');
    now = DateTime.utc(2026, 1, 14, 12, 3);
    await store.recordPlayback('middle');

    final smartPlaylists = store.smartPlaylists();

    expect(
      smartPlaylists.map((playlist) => playlist.type),
      SmartPlaylistType.values,
    );
    expect(
      smartPlaylists
          .firstWhere(
            (playlist) => playlist.type == SmartPlaylistType.favorites,
          )
          .trackCount,
      2,
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.favorites,
      ).map((track) => track.id),
      <String>['middle', 'old'],
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.recentlyAdded,
        limit: 2,
      ).map((track) => track.id),
      <String>['new', 'middle'],
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.recentlyPlayed,
      ).map((track) => track.id),
      <String>['middle', 'old', 'new'],
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.mostPlayed,
      ).map((track) => track.id),
      <String>['old', 'middle', 'new'],
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.mostPlayed,
        limit: 2,
      ).map((track) => track.id),
      <String>['old', 'middle'],
    );
    expect(
      store.tracksForSmartPlaylist(SmartPlaylistType.mostPlayed, limit: 0),
      isEmpty,
    );
  });

  test('groups library tracks by artist album genre source and folder', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'First',
        artist: 'Ari',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 2),
        localPath: '/music/Ari/Dawn/first.mp3',
      ),
      _track(
        '2',
        title: 'Second',
        artist: 'Ari',
        album: 'Dusk',
        genre: 'Ambient',
        duration: const Duration(minutes: 3),
        localPath: '/music/Ari/Dusk/second.mp3',
      ),
      _track(
        '3',
        title: 'Third',
        artist: 'Mia',
        album: 'Dawn',
        genre: 'Jazz',
        sourceId: 'demo',
        duration: const Duration(minutes: 4),
        localPath: r'C:\Music\Mia\Dawn\third.mp3',
      ),
    ]);

    final artistGroups = store.browseGroups(LibraryBrowseType.artist);
    final albumGroups = store.browseGroups(LibraryBrowseType.album);
    final genreGroups = store.browseGroups(LibraryBrowseType.genre);
    final sourceGroups = store.browseGroups(LibraryBrowseType.source);
    final folderGroups = store.browseGroups(LibraryBrowseType.folder);

    expect(artistGroups.map((group) => group.label), <String>['Ari', 'Mia']);
    expect(artistGroups.first.trackCount, 2);
    expect(artistGroups.first.totalDuration, const Duration(minutes: 5));
    expect(albumGroups.map((group) => group.label), <String>['Dawn', 'Dusk']);
    expect(
      genreGroups.map((group) => group.label),
      <String>['Ambient', 'Jazz'],
    );
    expect(
      sourceGroups.map((group) => group.label),
      <String>['demo', 'local'],
    );
    expect(
      folderGroups.map((group) => group.label),
      <String>[
        '/music/Ari/Dawn',
        '/music/Ari/Dusk',
        r'C:\Music\Mia\Dawn',
      ],
    );
    expect(
      store
          .browseGroups(LibraryBrowseType.genre, query: 'amb')
          .map((group) => group.label),
      <String>['Ambient'],
    );
    expect(
      store
          .tracksForBrowseGroup(
            LibraryBrowseType.folder,
            '/music/Ari/Dawn',
          )
          .map((track) => track.id),
      <String>['1'],
    );
    expect(
      store
          .tracksForBrowseGroup(
            LibraryBrowseType.genre,
            'ambient',
            sortMode: LibrarySortMode.title,
          )
          .map((track) => track.id),
      <String>['1', '2'],
    );
  });

  test('exports and restores a full library backup', () async {
    DateTime clock() => DateTime.utc(2026, 1, 11);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1'), _track('2')]);
    await firstStore.toggleFavorite('2');
    final playlist = await firstStore.createPlaylist(
      'Backup Mix',
      trackIds: <String>['1', '2'],
    );
    await firstStore.setLyrics('1', 'backup lyrics');
    await firstStore.recordPlayback('2');
    await firstStore.recordPlaybackProgress(
      '1',
      const Duration(minutes: 4),
      const Duration(minutes: 20),
    );
    final subscription = await firstStore.savePodcastSubscription(
      PodcastSubscription(
        id: 'podcast',
        feedUrl: 'https://feeds.example.test/aether.xml',
        title: 'Aether Radio',
      ),
    );
    await firstStore.markPodcastSubscriptionFetched(subscription.id);

    final backupJson = firstStore.exportBackupJson();

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();
    await secondStore.addTracks(<Track>[_track('stale')]);
    await secondStore.restoreBackupJson(backupJson);

    expect(
      secondStore.tracks.map((track) => track.id),
      containsAll(<String>[
        '1',
        '2',
      ]),
    );
    expect(secondStore.tracks, hasLength(2));
    expect(
      secondStore.tracks.singleWhere((track) => track.id == '2').isFavorite,
      isTrue,
    );
    expect(secondStore.playlistById(playlist.id)!.name, 'Backup Mix');
    expect(
      secondStore.playlistById(playlist.id)!.trackIds,
      <String>[
        '1',
        '2',
      ],
    );
    expect(secondStore.lyricsForTrack('1')!.plainText, 'backup lyrics');
    expect(secondStore.playbackHistory.single.trackId, '2');
    expect(secondStore.recentlyPlayedTracks().single.id, '2');
    expect(
      secondStore.playbackProgressForTrack('1')!.position,
      const Duration(minutes: 4),
    );
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.title,
      'Aether Radio',
    );
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.lastFetchedAt,
      DateTime.utc(2026, 1, 11),
    );
  });

  test('rejects invalid backup JSON without replacing the library', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 12),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);

    expect(
      store.restoreBackupJson('[]'),
      throwsA(isA<FormatException>()),
    );
    expect(store.tracks.single.id, '1');
  });

  test('rejects unsupported backup versions', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 13),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);
    final backup = jsonDecode(store.exportBackupJson()) as Map<String, dynamic>;
    backup['version'] = 999;

    expect(
      store.restoreBackupJson(jsonEncode(backup)),
      throwsA(isA<FormatException>()),
    );
  });
}

Track _track(
  String id, {
  String? title,
  String artist = 'Artist',
  String album = 'Album',
  String genre = 'Unknown Genre',
  String sourceId = 'local',
  Duration duration = Duration.zero,
  DateTime? addedAt,
  String? localPath,
}) {
  return Track(
    id: id,
    title: title ?? 'Track $id',
    artist: artist,
    album: album,
    genre: genre,
    duration: duration,
    localPath: localPath ?? '/music/$id.mp3',
    sourceId: sourceId,
    addedAt: addedAt ?? DateTime.utc(2026),
  );
}
