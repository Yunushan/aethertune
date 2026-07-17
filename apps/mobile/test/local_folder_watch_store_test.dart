import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/local_folder_scanner.dart';
import 'package:aethertune/src/data/local_folder_watch_store.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_chapter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists watched roots and safely reconciles local folder scans',
      () async {
    const root = '/music/watched';
    final normalizedRoot = p.normalize(p.absolute(root));
    final store = LibraryStore(clock: () => DateTime.utc(2026, 7, 12));
    await store.load();
    await store.watchLocalFolder(root);
    await store.watchLocalFolder('$root/');

    final original = _track(
      path: '$root/one.mp3',
      title: 'Original title',
      hash: 'old-hash',
      artworkUri: Uri.parse('data:image/png;base64,b3JpZ2luYWw='),
      addedAt: DateTime.utc(2026, 1, 1),
      chapters: const <TrackChapter>[
        TrackChapter(start: Duration(seconds: 30), title: 'Keep chapter'),
      ],
    );
    await store.addTracks(<Track>[original]);
    await store.toggleFavorite(original.id);
    await store.setLyrics(original.id, 'Manual lyrics');
    await store.recordPlayback(original.id);
    await store.recordPlaybackProgress(
      original.id,
      const Duration(seconds: 45),
      const Duration(minutes: 4),
    );
    await store.setTrackPlaybackSpeed(original.id, 1.25);
    final playlist = await store.createPlaylist(
      'Keep watched state',
      trackIds: <String>[original.id],
    );
    final privateArtwork = Uri.file('/private/manual-cover.png');
    await store.updateTrackArtwork(original.id, privateArtwork);

    final refreshed = _track(
      path: '$root/one.mp3',
      title: 'Rescanned title',
      hash: 'new-hash',
      artworkUri: Uri.parse('data:image/png;base64,cmVzY2FubmVk'),
      addedAt: DateTime.utc(2026, 7, 12),
      albumArtist: 'Rescanned album artist',
      year: 2026,
      trackNumber: 7,
      duration: const Duration(minutes: 4, seconds: 12),
      replayGainTrackDb: -6.5,
      replayGainAlbumDb: -4.25,
    );
    final added = _track(
      path: '$root/two.mp3',
      title: 'Newly discovered',
      hash: 'two-hash',
    );
    final embedded = _track(
      path: '$root/three.mp3',
      title: 'Embedded lyrics',
      hash: 'three-hash',
    );
    await store.reconcileWatchedLocalFolder(
      root,
      tracks: <Track>[refreshed, added, embedded],
      sidecarLyricsByTrackId: <String, String>{
        original.id: 'Sidecar must not overwrite manual lyrics',
        added.id: '[00:01.00]New sidecar lyrics',
      },
      embeddedLyricsByTrackId: <String, String>{
        original.id: 'Embedded must not overwrite manual lyrics',
        added.id: 'Embedded must not overwrite a sidecar',
        embedded.id: 'Imported embedded lyric',
      },
      pruneMissing: true,
    );

    final updated = store.tracks.firstWhere((track) => track.id == original.id);
    expect(updated.title, 'Rescanned title');
    expect(updated.albumArtist, 'Rescanned album artist');
    expect(updated.year, 2026);
    expect(updated.trackNumber, 7);
    expect(updated.duration, const Duration(minutes: 4, seconds: 12));
    expect(updated.replayGainTrackDb, -6.5);
    expect(updated.replayGainAlbumDb, -4.25);
    expect(updated.isFavorite, isTrue);
    expect(updated.addedAt, DateTime.utc(2026, 1, 1));
    expect(updated.artworkUri, privateArtwork);
    expect(
      updated.artworkSourceUri,
      Uri.parse('data:image/png;base64,b3JpZ2luYWw='),
    );
    expect(updated.artworkIsUserManaged, isTrue);
    expect(updated.chapters.single.title, 'Keep chapter');
    expect(store.lyricsForTrack(original.id)?.plainText, 'Manual lyrics');
    expect(store.playbackHistory.single.trackId, original.id);
    expect(
      store.playbackProgressForTrack(original.id)?.position,
      const Duration(seconds: 45),
    );
    expect(store.playbackSpeedForTrack(original.id), 1.25);
    expect(store.playlistById(playlist.id)?.trackIds, <String>[original.id]);
    expect(
      store.lyricsForTrack(added.id)?.plainText,
      '[00:01.00]New sidecar lyrics',
    );
    expect(store.lyricsForTrack(added.id)?.sourceId, 'sidecar');
    expect(store.lyricsForTrack(embedded.id)?.plainText, 'Imported embedded lyric');
    expect(store.lyricsForTrack(embedded.id)?.sourceId, 'embedded');

    await store.reconcileWatchedLocalFolder(
      root,
      tracks: <Track>[refreshed],
      sidecarLyricsByTrackId: const <String, String>{},
      pruneMissing: true,
    );
    expect(store.tracks.map((track) => track.id), <String>[original.id]);
    expect(store.lyricsForTrack(added.id), isNull);

    final restored = LibraryStore();
    await restored.load();
    expect(restored.watchedLocalFolderPaths, <String>[normalizedRoot]);
  });

  test('does not prune a watched folder after an incomplete scan', () async {
    const root = '/music/protected';
    final store = LibraryStore();
    await store.load();
    await store.watchLocalFolder(root);
    final existing = _track(
      path: '$root/existing.mp3',
      title: 'Existing',
      hash: 'existing-hash',
    );
    await store.addTracks(<Track>[existing]);

    await store.reconcileWatchedLocalFolder(
      root,
      tracks: const <Track>[],
      sidecarLyricsByTrackId: const <String, String>{},
      pruneMissing: false,
    );

    expect(store.tracks.single.id, existing.id);
  });

  test('watches relevant changes, debounces rescans, and ignores artwork',
      () async {
    const root = '/music/live';
    final normalizedRoot = p.normalize(p.absolute(root));
    final changes = StreamController<String>.broadcast(sync: true);
    var scanCount = 0;
    final store = LibraryStore();
    await store.load();
    await store.watchLocalFolder(root);
    final watcher = LocalFolderWatchStore(
      debounce: Duration.zero,
      watchStreamFactory: (_) => changes.stream,
      scanner: (rootPath, {DateTime? importedAt}) async {
        scanCount += 1;
        return LocalFolderScanResult(
          tracks: <Track>[
            _track(
              path: '$rootPath/scan-$scanCount.mp3',
              title: 'Scan $scanCount',
              hash: 'hash-$scanCount',
            ),
          ],
          ignoredFileCount: 0,
          inaccessibleDirectoryCount: 0,
          sidecarLyricsByTrackId: const <String, String>{},
        );
      },
    );
    addTearDown(() async {
      watcher.dispose();
      await changes.close();
    });

    watcher.updateLibrary(store);
    await _waitUntil(
      () => scanCount == 1 && !watcher.isRefreshing(normalizedRoot),
    );
    expect(store.tracks.single.title, 'Scan 1');

    changes.add('$root/cover.jpg');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(scanCount, 1);

    changes
      ..add('$root/new-track.mp3')
      ..add('$root/new-track.lrc');
    await _waitUntil(
      () => scanCount == 2 && !watcher.isRefreshing(normalizedRoot),
    );
    expect(store.tracks.single.title, 'Scan 2');
    expect(watcher.errorFor(normalizedRoot), isNull);
    expect(watcher.lastRefreshedAt(normalizedRoot), isNotNull);

    await store.unwatchLocalFolder(root);
    watcher.updateLibrary(store);
    changes.add('$root/ignored-after-removal.mp3');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(scanCount, 2);
  });
}

Track _track({
  required String path,
  required String title,
  required String hash,
  Uri? artworkUri,
  DateTime? addedAt,
  String? albumArtist,
  int? year,
  int? trackNumber,
  Duration duration = Duration.zero,
  double? replayGainTrackDb,
  double? replayGainAlbumDb,
  List<TrackChapter>? chapters,
}) {
  return Track(
    id: Track.stableLocalId(path),
    title: title,
    artist: 'Watched artist',
    album: 'Watched album',
    albumArtist: albumArtist,
    year: year,
    trackNumber: trackNumber,
    duration: duration,
    localPath: path,
    contentHash: hash,
    replayGainTrackDb: replayGainTrackDb,
    replayGainAlbumDb: replayGainAlbumDb,
    artworkUri: artworkUri,
    sourceId: 'local',
    addedAt: addedAt,
    chapters: chapters,
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for asynchronous folder watch work.');
}
