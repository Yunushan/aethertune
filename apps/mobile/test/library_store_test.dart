import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
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
  DateTime? addedAt,
}) {
  return Track(
    id: id,
    title: title ?? 'Track $id',
    artist: artist,
    album: album,
    localPath: '/music/$id.mp3',
    addedAt: addedAt ?? DateTime.utc(2026),
  );
}
