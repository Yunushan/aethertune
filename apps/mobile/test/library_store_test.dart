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

  test('detects duplicate tracks by path provider stream and metadata', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'path-a',
        title: 'Path A',
        localPath: '/music/shared.mp3',
      ),
      _track(
        'path-b',
        title: 'Path B',
        localPath: '/music/shared.mp3',
      ),
      _track(
        'provider-a',
        title: 'Provider A',
        sourceId: 'archive',
        externalId: 'item-1',
        localPath: null,
      ),
      _track(
        'provider-b',
        title: 'Provider B',
        sourceId: 'archive',
        externalId: 'item-1',
        localPath: null,
      ),
      _track(
        'stream-a',
        title: 'Stream A',
        streamUrl: 'https://media.example.test/song.mp3',
        localPath: null,
      ),
      _track(
        'stream-b',
        title: 'Stream B',
        streamUrl: 'https://media.example.test/song.mp3',
        localPath: null,
      ),
      _track(
        'meta-a',
        title: 'Same Song',
        artist: 'Mira',
        album: 'Dawn',
        duration: const Duration(minutes: 3),
      ),
      _track(
        'meta-b',
        title: ' same song ',
        artist: ' mira ',
        album: ' dawn ',
        duration: const Duration(minutes: 3),
      ),
    ]);

    final groups = store.duplicateTrackGroups();

    expect(
      groups.map((group) => group.type),
      containsAll(<DuplicateMatchType>[
        DuplicateMatchType.localPath,
        DuplicateMatchType.sourceExternalId,
        DuplicateMatchType.streamUrl,
        DuplicateMatchType.metadata,
      ]),
    );
    expect(
      groups
          .firstWhere((group) => group.type == DuplicateMatchType.localPath)
          .tracks
          .map((track) => track.id),
      containsAll(<String>['path-a', 'path-b']),
    );
  });

  test('resolves duplicates while preserving attached library state', () async {
    var now = DateTime.utc(2026, 1, 4, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'keep',
        title: 'Aether Bloom',
        artist: 'Mira',
        album: 'Dawn',
        duration: const Duration(minutes: 3),
        addedAt: DateTime.utc(2026, 1, 1),
      ),
      _track(
        'duplicate',
        title: 'Aether Bloom',
        artist: 'Mira',
        album: 'Dawn',
        duration: const Duration(minutes: 3),
        addedAt: DateTime.utc(2026, 1, 2),
      ),
      _track(
        'other',
        title: 'Other',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
    ]);
    final playlist = await store.createPlaylist(
      'Merge',
      trackIds: <String>['duplicate', 'other', 'keep'],
    );
    await store.setLyrics('keep', 'old lyrics');
    now = DateTime.utc(2026, 1, 4, 12, 1);
    await store.setLyrics('duplicate', 'new lyrics');
    await store.recordPlayback('keep');
    now = DateTime.utc(2026, 1, 4, 12, 2);
    await store.recordPlayback('duplicate');
    await store.recordPlaybackProgress(
      'duplicate',
      const Duration(minutes: 10),
      const Duration(minutes: 30),
    );
    await store.toggleFavorite('duplicate');

    final removed = await store.resolveDuplicateTracks(
      keepTrackId: 'keep',
      duplicateTrackIds: <String>['duplicate'],
    );

    expect(removed, 1);
    expect(store.tracks.map((track) => track.id), isNot(contains('duplicate')));
    expect(
      store.playlistById(playlist.id)!.trackIds,
      <String>['keep', 'other'],
    );
    expect(
      store.playbackHistory.map((entry) => entry.trackId),
      <String>['keep', 'keep'],
    );
    expect(store.playCountForTrack('keep'), 2);
    expect(
      store.tracks.firstWhere((track) => track.id == 'keep').isFavorite,
      isTrue,
    );
    expect(store.lyricsForTrack('keep')!.plainText, 'new lyrics');
    expect(store.lyricsForTrack('duplicate'), isNull);
    expect(
      store.playbackProgressForTrack('keep')!.position,
      const Duration(minutes: 10),
    );
    expect(store.playbackProgressForTrack('duplicate'), isNull);
    expect(store.duplicateTrackGroups(), isEmpty);

    final secondStore = LibraryStore(clock: () => now);
    await secondStore.load();

    expect(
      secondStore.tracks.map((track) => track.id),
      isNot(contains('duplicate')),
    );
    expect(secondStore.playlistById(playlist.id)!.trackIds, <String>[
      'keep',
      'other',
    ]);
    expect(secondStore.lyricsForTrack('keep')!.plainText, 'new lyrics');
    expect(secondStore.playCountForTrack('keep'), 2);
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

  test('edits persists exports imports and clears playlist artwork', () async {
    var now = DateTime.utc(2026, 1, 4, 5);
    DateTime clock() => now;
    final artworkUri = Uri.parse('https://media.example.test/road.jpg');
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1'), _track('2')]);
    final playlist = await firstStore.createPlaylist(
      'Artwork Mix',
      trackIds: <String>['1', '2'],
    );

    now = DateTime.utc(2026, 1, 4, 5, 1);
    final updated = await firstStore.updatePlaylistArtwork(
      playlist.id,
      artworkUri,
    );

    expect(updated!.artworkUri, artworkUri);
    expect(updated.updatedAt, now);
    expect(firstStore.playlistById(playlist.id)!.artworkUri, artworkUri);

    final playlistDocument = firstStore.exportPlaylistJson(playlist.id);
    final decoded = jsonDecode(playlistDocument) as Map<String, dynamic>;

    expect(
      (decoded['playlist'] as Map<String, dynamic>)['artworkUri'],
      artworkUri.toString(),
    );

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.playlistById(playlist.id)!.artworkUri, artworkUri);

    await secondStore.deletePlaylist(playlist.id);
    final imported = await secondStore.importPlaylistJson(playlistDocument);

    expect(imported.artworkUri, artworkUri);

    now = DateTime.utc(2026, 1, 4, 5, 2);
    final cleared = await secondStore.updatePlaylistArtwork(imported.id, null);

    expect(cleared!.artworkUri, isNull);
    expect(cleared.updatedAt, now);
    expect(secondStore.playlistById(imported.id)!.artworkUri, isNull);
    expect(
      await secondStore.updatePlaylistArtwork('missing', artworkUri),
      isNull,
    );
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

  test('builds library listening stats from playback history', () async {
    var now = DateTime.utc(2026, 1, 8, 13);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Aether One',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 3),
      ),
      _track(
        '2',
        title: 'Aether Two',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 4),
      ),
      _track(
        '3',
        title: 'Night Three',
        artist: 'Orion',
        album: 'Night',
        genre: 'Jazz',
        duration: const Duration(minutes: 5),
      ),
    ]);
    await store.toggleFavorite('2');
    await store.recordPlayback('1');
    now = DateTime.utc(2026, 1, 8, 13, 1);
    await store.recordPlayback('2');
    now = DateTime.utc(2026, 1, 8, 13, 2);
    await store.recordPlayback('1');
    now = DateTime.utc(2026, 1, 8, 13, 3);
    await store.recordPlayback('3');

    final stats = store.libraryStats(limit: 2);

    expect(stats.trackCount, 3);
    expect(stats.libraryDuration, const Duration(minutes: 12));
    expect(stats.favoriteTrackCount, 1);
    expect(stats.playbackCount, 4);
    expect(stats.uniquePlayedTrackCount, 3);
    expect(stats.estimatedListeningDuration, const Duration(minutes: 15));
    expect(
      stats.topTracks.map((trackStats) => trackStats.track.id),
      <String>['1', '3'],
    );
    expect(stats.topTracks.first.playCount, 2);
    expect(
      stats.topTracks.first.estimatedListeningDuration,
      const Duration(minutes: 6),
    );
    expect(stats.topArtists.map((group) => group.label), <String>[
      'Mira',
      'Orion',
    ]);
    expect(stats.topArtists.first.playCount, 3);
    expect(stats.topArtists.first.trackCount, 2);
    expect(stats.topAlbums.first.label, 'Dawn');
    expect(stats.topGenres.first.label, 'Ambient');
    expect(store.libraryStats(limit: 0).topTracks, isEmpty);
  });

  test('filters and exports library stats by playback date range', () async {
    var now = DateTime.utc(2026, 1, 1, 9);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Aether One',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 3),
      ),
      _track(
        '2',
        title: 'Night Two',
        artist: 'Orion',
        album: 'Night',
        genre: 'Jazz',
        duration: const Duration(minutes: 4),
      ),
      _track(
        '3',
        title: 'Old Three',
        artist: 'Ari',
        album: 'Archive',
        genre: 'Folk',
        duration: const Duration(minutes: 5),
      ),
    ]);

    await store.recordPlayback('3');
    now = DateTime.utc(2026, 1, 10, 10);
    await store.recordPlayback('1');
    now = DateTime.utc(2026, 1, 11, 10);
    await store.recordPlayback('1');
    now = DateTime.utc(2026, 1, 12, 10);
    await store.recordPlayback('2');

    final from = DateTime.utc(2026, 1, 10);
    final to = DateTime.utc(2026, 1, 13);
    final stats = store.libraryStats(limit: 2, from: from, to: to);

    expect(stats.from, from);
    expect(stats.to, to);
    expect(stats.playbackCount, 3);
    expect(stats.uniquePlayedTrackCount, 2);
    expect(stats.estimatedListeningDuration, const Duration(minutes: 10));
    expect(
      stats.topTracks.map((trackStats) => trackStats.track.id),
      <String>['1', '2'],
    );
    expect(store.playCountForTrack('1', from: from, to: to), 2);
    expect(
      store.lastPlayedAt('1', from: from, to: to),
      DateTime.utc(2026, 1, 11, 10),
    );
    expect(
      store.recentlyPlayedTracks(from: from, to: to).map((track) => track.id),
      <String>['2', '1'],
    );
    expect(store.libraryStats(from: to).playbackCount, 0);

    final jsonDocument = store.exportLibraryStatsDocument(
      format: LibraryStatsExportFormat.json,
      limit: 1,
      from: from,
      to: to,
    );
    final decoded = jsonDecode(jsonDocument) as Map<String, dynamic>;

    expect(decoded['type'], 'aethertune.library_stats');
    expect(decoded['version'], 1);
    expect(decoded['from'], from.toIso8601String());
    expect(decoded['to'], to.toIso8601String());
    expect((decoded['summary'] as Map<String, dynamic>)['playbackCount'], 3);
    expect((decoded['topTracks'] as List<dynamic>), hasLength(1));
    expect(
      ((decoded['topTracks'] as List<dynamic>).single
          as Map<String, dynamic>)['trackId'],
      '1',
    );

    final csvDocument = store.exportLibraryStatsDocument(
      format: LibraryStatsExportFormat.csv,
      from: from,
      to: to,
    );

    expect(csvDocument, contains('summary,playbackCount,3'));
    expect(csvDocument, contains('top_track,Aether One'));
    expect(csvDocument, contains(from.toIso8601String()));
    expect(csvDocument, contains(to.toIso8601String()));
  });

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

  test('filters library searches to local offline-playable tracks', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      Track(
        id: 'local',
        title: 'Ambient Local',
        artist: 'Mia',
        album: 'Offline',
        genre: 'Ambient',
        localPath: '/music/ambient-local.mp3',
      ),
      Track(
        id: 'stream',
        title: 'Ambient Stream',
        artist: 'Mia',
        album: 'Archive',
        genre: 'Ambient',
        streamUrl: 'https://media.example.test/ambient.mp3',
        sourceId: 'archive',
      ),
    ]);

    expect(
      store.search('ambient').map((track) => track.id),
      containsAll(<String>['local', 'stream']),
    );
    expect(
      store.search('ambient', offlineOnly: true).map((track) => track.id),
      <String>['local'],
    );
  });

  test('builds local search suggestions from recent playback and metadata', () async {
    var now = DateTime.utc(2026, 1, 15, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'ambient',
        title: 'Ambient Signal',
        artist: 'Mia Nova',
        album: 'Dawn Archive',
        genre: 'Ambient',
        sourceId: 'archive',
        localPath: '/music/Mia/Dawn/ambient.mp3',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
      _track(
        'jazz',
        title: 'Late Train',
        artist: 'Ari Vale',
        album: 'Night Lines',
        genre: 'Jazz',
        sourceId: 'radio',
        localPath: '/music/Ari/Night/train.mp3',
        addedAt: DateTime.utc(2026, 1, 2),
      ),
    ]);

    await store.recordPlayback('jazz');
    now = DateTime.utc(2026, 1, 15, 12, 1);
    await store.recordPlayback('ambient');

    final suggestions = store.searchSuggestions('');

    expect(
      suggestions.take(2).map((suggestion) => suggestion.type),
      <SearchSuggestionType>[
        SearchSuggestionType.recent,
        SearchSuggestionType.recent,
      ],
    );
    expect(
      suggestions.take(2).map((suggestion) => suggestion.value),
      <String>['Ambient Signal', 'Late Train'],
    );
    expect(
      suggestions.map((suggestion) => suggestion.value),
      containsAll(<String>[
        'Mia Nova',
        'Dawn Archive',
        'Ambient',
        'archive',
        '/music/Mia/Dawn',
      ]),
    );
    expect(
      suggestions.map((suggestion) => suggestion.value).toSet(),
      hasLength(suggestions.length),
    );

    expect(
      store.searchSuggestions('dawn').map((suggestion) => suggestion.value),
      containsAll(<String>['Dawn Archive', '/music/Mia/Dawn']),
    );
    expect(
      store.search('/music/mia/dawn').map((track) => track.id),
      <String>['ambient'],
    );
    expect(store.searchSuggestions('ambient', limit: 1), hasLength(1));
  });

  test('persists submitted search query history for suggestions', () async {
    final store = LibraryStore();
    await store.load();

    for (var index = 0; index < 25; index += 1) {
      await store.recordSearchQuery('Query $index');
    }
    await store.recordSearchQuery(' query 20 ');
    await store.recordSearchQuery('');

    expect(store.searchQueryHistory, hasLength(20));
    expect(store.searchQueryHistory.first, 'query 20');
    expect(store.searchQueryHistory, isNot(contains('Query 4')));

    final suggestions = store.searchSuggestions('20');
    expect(suggestions.single.type, SearchSuggestionType.query);
    expect(suggestions.single.value, 'query 20');

    final secondStore = LibraryStore();
    await secondStore.load();

    expect(secondStore.searchQueryHistory.first, 'query 20');
    expect(
      secondStore.searchSuggestions('').first.type,
      SearchSuggestionType.query,
    );

    final backupJson = secondStore.exportBackupJson();
    final thirdStore = LibraryStore();
    await thirdStore.load();
    await thirdStore.restoreBackupJson(backupJson);

    expect(thirdStore.searchQueryHistory, secondStore.searchQueryHistory);
  });

  test('persists offline mode and restores it from backups', () async {
    final firstStore = LibraryStore();
    await firstStore.load();

    expect(firstStore.offlineModeEnabled, isFalse);

    await firstStore.setOfflineModeEnabled(true);

    expect(firstStore.offlineModeEnabled, isTrue);

    final secondStore = LibraryStore();
    await secondStore.load();

    expect(secondStore.offlineModeEnabled, isTrue);

    final backupJson = secondStore.exportBackupJson();
    final backup = jsonDecode(backupJson) as Map<String, dynamic>;
    expect(backup['offlineModeEnabled'], isTrue);

    final legacyBackup = Map<String, dynamic>.from(backup)
      ..remove('offlineModeEnabled');
    await secondStore.restoreBackupJson(jsonEncode(legacyBackup));

    expect(secondStore.offlineModeEnabled, isFalse);

    await secondStore.restoreBackupJson(backupJson);

    expect(secondStore.offlineModeEnabled, isTrue);
  });

  test('edits persisted track metadata for search browse and suggestions', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Untitled Import',
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        genre: 'Unknown Genre',
      ),
    ]);

    final updated = await store.updateTrackMetadata(
      '1',
      title: '  Aether Bloom  ',
      artist: '  Mira Vale  ',
      album: '  Dawn Signals  ',
      genre: '  Synthwave  ',
    );

    expect(updated, isNotNull);
    expect(updated!.id, '1');
    expect(updated.title, 'Aether Bloom');
    expect(updated.artist, 'Mira Vale');
    expect(updated.album, 'Dawn Signals');
    expect(updated.genre, 'Synthwave');
    expect(store.search('untitled'), isEmpty);
    expect(store.search('synthwave').single.id, '1');
    expect(
      store.browseGroups(LibraryBrowseType.artist).single.label,
      'Mira Vale',
    );
    expect(
      store.searchSuggestions('dawn').map((suggestion) => suggestion.value),
      contains('Dawn Signals'),
    );

    final secondStore = LibraryStore();
    await secondStore.load();

    expect(secondStore.tracks.single.title, 'Aether Bloom');
    expect(secondStore.search('mira').single.id, '1');
  });

  test('track metadata edits require a title and normalize empty fields', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[_track('1', title: 'Original')]);

    expect(
      store.updateTrackMetadata(
        '1',
        title: '   ',
        artist: 'Artist',
        album: 'Album',
        genre: 'Genre',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      await store.updateTrackMetadata(
        'missing',
        title: 'Missing',
        artist: '',
        album: '',
        genre: '',
      ),
      isNull,
    );

    final updated = await store.updateTrackMetadata(
      '1',
      title: 'Original',
      artist: '',
      album: '',
      genre: '',
    );

    expect(updated!.artist, 'Unknown Artist');
    expect(updated.album, 'Unknown Album');
    expect(updated.genre, 'Unknown Genre');
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

  test('creates updates and persists custom smart playlist rules', () async {
    var now = DateTime.utc(2026, 1, 15, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'ari-old',
        title: 'Low Tide',
        artist: 'Ari',
        genre: 'Ambient',
        addedAt: DateTime.utc(2026, 1),
      ),
      _track(
        'ari-new',
        title: 'Dawn Tide',
        artist: 'Ari',
        genre: 'Ambient',
        addedAt: DateTime.utc(2026, 1, 2),
      ),
      _track(
        'ari-rock',
        title: 'Rock Sun',
        artist: 'Ari',
        genre: 'Rock',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
      _track(
        'mia',
        title: 'Mia Drift',
        artist: 'Mia',
        genre: 'Ambient',
        addedAt: DateTime.utc(2026, 1, 4),
      ),
    ]);
    await store.toggleFavorite('ari-old');
    await store.toggleFavorite('ari-new');
    await store.toggleFavorite('ari-rock');
    await store.recordPlayback('ari-old');
    now = DateTime.utc(2026, 1, 15, 12, 1);
    await store.recordPlayback('ari-new');
    now = DateTime.utc(2026, 1, 15, 12, 2);
    await store.recordPlayback('ari-old');

    final rule = await store.createCustomSmartPlaylist(
      name: '  Ambient Ari  ',
      query: 'ambient',
      favoritesOnly: true,
      minimumPlayCount: 1,
      sortMode: CustomSmartPlaylistSortMode.mostPlayed,
      limit: 2,
    );

    expect(rule.name, 'Ambient Ari');
    expect(rule.query, 'ambient');
    expect(
      store.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['ari-old', 'ari-new'],
    );

    final secondStore = LibraryStore(clock: () => now);
    await secondStore.load();

    expect(secondStore.customSmartPlaylists.single.id, rule.id);
    expect(
      secondStore.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['ari-old', 'ari-new'],
    );

    final updated = await secondStore.updateCustomSmartPlaylist(
      rule.id,
      name: 'Ari Library',
      query: 'ari',
      favoritesOnly: false,
      minimumPlayCount: 0,
      sortMode: CustomSmartPlaylistSortMode.title,
      limit: 3,
    );

    expect(updated!.name, 'Ari Library');
    expect(
      secondStore
          .tracksForCustomSmartPlaylist(rule.id)
          .map((track) => track.id),
      <String>['ari-new', 'ari-old', 'ari-rock'],
    );

    await secondStore.deleteCustomSmartPlaylist(rule.id);

    expect(secondStore.customSmartPlaylists, isEmpty);
    expect(secondStore.tracksForCustomSmartPlaylist(rule.id), isEmpty);
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
    final playlistArtworkUri =
        Uri.parse('https://media.example.test/backup-mix.jpg');
    await firstStore.updatePlaylistArtwork(playlist.id, playlistArtworkUri);
    await firstStore.setLyrics('1', 'backup lyrics');
    await firstStore.recordPlayback('2');
    await firstStore.recordPlaybackProgress(
      '1',
      const Duration(minutes: 4),
      const Duration(minutes: 20),
    );
    final smartRule = await firstStore.createCustomSmartPlaylist(
      name: 'Favorite plays',
      favoritesOnly: true,
      minimumPlayCount: 1,
      sortMode: CustomSmartPlaylistSortMode.mostPlayed,
      limit: 10,
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
    expect(
      secondStore.playlistById(playlist.id)!.artworkUri,
      playlistArtworkUri,
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
    expect(secondStore.customSmartPlaylists.single.name, 'Favorite plays');
    expect(
      secondStore
          .tracksForCustomSmartPlaylist(smartRule.id)
          .map((track) => track.id),
      <String>['2'],
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
  String? externalId,
  Duration duration = Duration.zero,
  DateTime? addedAt,
  String? localPath,
  String? streamUrl,
}) {
  return Track(
    id: id,
    title: title ?? 'Track $id',
    artist: artist,
    album: album,
    genre: genre,
    duration: duration,
    localPath: localPath ?? '/music/$id.mp3',
    streamUrl: streamUrl,
    sourceId: sourceId,
    externalId: externalId,
    addedAt: addedAt ?? DateTime.utc(2026),
  );
}
