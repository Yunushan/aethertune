import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/internet_archive_provider.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('portable snapshot excludes device paths cache jobs and secret URLs',
      () async {
    final store = LibraryStore(clock: () => DateTime.utc(2026, 7, 10));
    await store.load();
    final privateTrack = Track(
      id: 'local-private',
      title: 'Private local track',
      artworkUri: Uri.file(r'C:\Users\Yunus\Pictures\cover.png'),
      localPath: r'C:\Users\Yunus\Music\private.mp3',
      contentHash: 'content-hash-1',
      streamUrl: 'https://media.example.test/audio?token=private-token',
      sourceId: 'local',
    );
    final publicTrack = Track(
      id: 'public',
      title: 'Public stream',
      artworkUri: Uri.parse('data:image/png;base64,iVBORw0KGgo='),
      streamUrl: 'https://archive.org/download/item/audio.mp3',
      sourceId: 'internet-archive',
      externalId: 'item',
    );
    await store.addTracks(<Track>[privateTrack, publicTrack]);
    await store.createPlaylist(
      'Portable playlist',
      trackIds: <String>[privateTrack.id, publicTrack.id],
      artworkUri: Uri.file('/private/playlist-cover.png'),
    );
    final provider = InternetArchiveProvider();
    final policy = OfflineMediaPolicy(<MusicSourceProvider>[provider]);
    await store.queueOfflineCache(
      publicTrack,
      OfflineMediaAction.cache,
      policy.evaluate(publicTrack, OfflineMediaAction.cache),
    );

    final raw = store.exportSyncSnapshotJson();
    final snapshot = jsonDecode(raw) as Map<String, dynamic>;
    final tracks = (snapshot['tracks'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final privateJson = tracks.singleWhere(
      (track) => track['id'] == privateTrack.id,
    );
    final publicJson = tracks.singleWhere(
      (track) => track['id'] == publicTrack.id,
    );
    final playlist = (snapshot['playlists'] as List<dynamic>).single
        as Map<String, dynamic>;

    expect(snapshot['syncVersion'], 1);
    expect(snapshot['offlineCacheQueue'], isEmpty);
    expect(snapshot.containsKey('offlineModeEnabled'), isFalse);
    expect(snapshot.containsKey('offlineCacheLimitMegabytes'), isFalse);
    expect(
      snapshot.containsKey('offlineCacheProviderLimitMegabytes'),
      isFalse,
    );
    expect(privateJson['localPath'], isNull);
    expect(privateJson['artworkUri'], isNull);
    expect(privateJson['streamUrl'], isNull);
    expect(privateJson['contentHash'], 'content-hash-1');
    expect(publicJson['streamUrl'], publicTrack.streamUrl);
    expect(publicJson['artworkUri'], publicTrack.artworkUri.toString());
    expect(playlist['artworkUri'], isNull);
    expect(raw, isNot(contains(r'C:\Users\Yunus')));
    expect(raw, isNot(contains('/private/playlist-cover.png')));
    expect(raw, isNot(contains('private-token')));
  });

  test('restore reattaches local files and preserves device cache settings',
      () async {
    final remoteStore = LibraryStore(clock: () => DateTime.utc(2026, 7, 10));
    await remoteStore.load();
    final remoteTrack = Track(
      id: 'remote-track-id',
      title: 'Edited on desktop',
      artist: 'Shared artist',
      localPath: '/home/yunus/Music/song.mp3',
      contentHash: 'shared-content-hash',
      sourceId: 'local',
    );
    await remoteStore.addTracks(<Track>[remoteTrack]);
    await remoteStore.createPlaylist(
      'Desktop playlist',
      trackIds: <String>[remoteTrack.id],
    );
    await remoteStore.setLyrics(
      remoteTrack.id,
      'Synced lyrics',
    );
    await remoteStore.recordPlaybackProgress(
      remoteTrack.id,
      const Duration(minutes: 2),
      const Duration(minutes: 4),
    );
    final remoteSnapshot = remoteStore.exportSyncSnapshotJson();

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final localStore = LibraryStore(clock: () => DateTime.utc(2026, 7, 11));
    await localStore.load();
    final localTrack = Track(
      id: 'phone-track-id',
      title: 'Original phone metadata',
      localPath: r'D:\Music\song.mp3',
      contentHash: 'shared-content-hash',
      sourceId: 'local',
    );
    await localStore.addTracks(<Track>[localTrack]);
    await localStore.setOfflineModeEnabled(true);
    await localStore.setOfflineCacheLimitMegabytes(777);
    final provider = InternetArchiveProvider();
    final queuedTrack = Track(
      id: 'device-cache-job',
      title: 'Device cache job',
      streamUrl: 'https://archive.org/download/item/audio.mp3',
      sourceId: provider.id,
      externalId: 'item',
    );
    final policy = OfflineMediaPolicy(<MusicSourceProvider>[provider]);
    await localStore.queueOfflineCache(
      queuedTrack,
      OfflineMediaAction.cache,
      policy.evaluate(queuedTrack, OfflineMediaAction.cache),
    );

    await localStore.restoreSyncSnapshotJson(remoteSnapshot);

    expect(localStore.tracks, hasLength(1));
    expect(localStore.tracks.single.id, 'remote-track-id');
    expect(localStore.tracks.single.title, 'Edited on desktop');
    expect(localStore.tracks.single.localPath, r'D:\Music\song.mp3');
    expect(localStore.playlists.single.name, 'Desktop playlist');
    expect(localStore.playlists.single.trackIds, <String>['remote-track-id']);
    expect(localStore.lyricsForTrack('remote-track-id')?.plainText,
        'Synced lyrics');
    expect(
      localStore.playbackProgressForTrack('remote-track-id')?.position,
      const Duration(minutes: 2),
    );
    expect(localStore.offlineModeEnabled, isTrue);
    expect(localStore.offlineCacheLimitMegabytes, 777);
    expect(localStore.offlineCacheQueue.single.track.id, 'device-cache-job');
  });

  test('rejects non-portable snapshots before replacing local state', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      Track(id: 'existing', title: 'Existing', localPath: '/music/existing.mp3'),
    ]);
    final snapshot = jsonDecode(store.exportSyncSnapshotJson())
        as Map<String, dynamic>;
    final track = (snapshot['tracks'] as List<dynamic>).single
        as Map<String, dynamic>;
    track['localPath'] = '/leaked/remote/path.mp3';

    await expectLater(
      store.restoreSyncSnapshotJson(jsonEncode(snapshot)),
      throwsA(isA<FormatException>()),
    );
    expect(store.tracks.single.id, 'existing');

    snapshot['syncVersion'] = 99;
    await expectLater(
      store.restoreSyncSnapshotJson(jsonEncode(snapshot)),
      throwsA(isA<FormatException>()),
    );
    expect(store.tracks.single.id, 'existing');
  });
}
