import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:aethertune/src/data/library_storage.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  late FileLibraryStorage storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp(
      'aethertune-library-durability-',
    );
    storage = FileLibraryStorage(directory: () async => root);
  });
  tearDown(() async => root.delete(recursive: true));

  test('commits all sections together and detects stale writers', () async {
    final first = await storage.write({
      'tracks': ['one'],
      'playlists': ['list-one'],
    }, expectedRevision: null);
    final next = await storage.write({
      'tracks': ['two'],
      'playlists': ['list-two'],
    }, expectedRevision: first.revision);
    await expectLater(
      storage.write({
        'tracks': ['stale'],
      }, expectedRevision: first.revision),
      throwsA(isA<LibraryStorageConflict>()),
    );
    final reopened = FileLibraryStorage(directory: () async => root);
    expect((await reopened.read())!.values, next.values);
    expect((await reopened.read())!.revision, next.revision);
  });

  test('disk-full before commit retains the entire prior snapshot', () async {
    final original = await storage.write({
      'tracks': ['one'],
      'playlists': ['list'],
    }, expectedRevision: null);
    final failing = FileLibraryStorage(
      directory: () async => root,
      beforeCommit: (file) async => throw FileSystemException(
        'No space left on device',
        file.path,
        const OSError('disk full', 28),
      ),
    );
    await expectLater(
      failing.write({
        'tracks': ['new'],
      }, expectedRevision: original.revision),
      throwsA(isA<FileSystemException>()),
    );
    expect((await storage.read())!.values, original.values);
    expect(await File(p.join(root.path, 'library.pending')).exists(), isTrue);
    final restarted = await storage.write({
      'tracks': ['retry'],
    }, expectedRevision: original.revision);
    expect((await storage.read())!.revision, restarted.revision);
  });

  test(
    'a corrupt current snapshot requires explicit recovery and is archived',
    () async {
      final first = await storage.write({
        'value': 'first',
      }, expectedRevision: null);
      await storage.write({
        'value': 'second',
      }, expectedRevision: first.revision);
      final current = File(p.join(root.path, 'library.json'));
      await current.writeAsString('{damaged', flush: true);
      await expectLater(storage.read(), throwsFormatException);
      final recovery = await storage.recoveryData();
      expect(
        utf8.decode(
          base64Decode((recovery['library.json'] as Map)['base64'] as String),
        ),
        '{damaged',
      );
      await storage.recoverPrevious();
      expect((await storage.read())!.values, {'value': 'first'});
      final archived = await Directory(p.join(root.path, 'recovery'))
          .list(recursive: true)
          .where(
            (entity) =>
                entity is File && p.basename(entity.path) == 'library.json',
          )
          .cast<File>()
          .toList();
      expect(archived, hasLength(1));
      expect(await archived.single.readAsString(), '{damaged');
    },
  );

  test(
    'checksum alteration is detected without changing stored bytes',
    () async {
      await storage.write({'value': 'first'}, expectedRevision: null);
      final file = File(p.join(root.path, 'library.json'));
      final document =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      document['payload'] = jsonEncode({'value': 'altered'});
      final corrupted = jsonEncode(document);
      await file.writeAsString(corrupted);
      await expectLater(storage.read(), throwsFormatException);
      expect(await file.readAsString(), corrupted);
    },
  );

  test(
    'missing current file does not silently discard a previous snapshot',
    () async {
      final first = await storage.write({'value': 1}, expectedRevision: null);
      await storage.write({'value': 2}, expectedRevision: first.revision);
      await File(p.join(root.path, 'library.json')).delete();
      await expectLater(
        storage.read(),
        throwsA(isA<LibraryStorageException>()),
      );
      await storage.recoverPrevious();
      expect((await storage.read())!.values, {'value': 1});
    },
  );

  test('cross-isolate writers cannot overwrite a newer revision', () async {
    final original = await storage.write({
      'value': 'original',
    }, expectedRevision: null);
    final entered = Completer<void>();
    final release = Completer<void>();
    final holding = FileLibraryStorage(
      directory: () async => root,
      beforeCommit: (_) async {
        entered.complete();
        await release.future;
      },
    );
    final first = holding.write({
      'value': 'first',
    }, expectedRevision: original.revision);
    await entered.future;
    final rootPath = root.path;
    final revision = original.revision;
    final attempted = ReceivePort();
    final port = attempted.sendPort;
    final second = _runOtherWriter(rootPath, revision, port);
    try {
      await attempted.first.timeout(const Duration(seconds: 10));
    } finally {
      attempted.close();
      release.complete();
    }
    await first;
    expect(await second, 'conflict');
    expect((await storage.read())!.values, {'value': 'first'});
  });

  test(
    'library migration retains legacy data and ignores it after migration',
    () async {
      final track = Track(id: 'legacy', title: 'Legacy');
      final raw = jsonEncode([track.toJson()]);
      SharedPreferences.setMockInitialValues({
        'aethertune.tracks.v1': raw,
        'aethertune.onboarding_completed.v1': true,
      });
      final library = LibraryStore(storage: storage);
      await library.load();
      expect(library.loaded, isTrue);
      expect(library.tracks.single.id, 'legacy');
      expect(library.onboardingCompleted, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('aethertune.tracks.v1'), raw);
      await prefs.setString('aethertune.tracks.v1', '{corrupt legacy');
      final restarted = LibraryStore(storage: storage);
      await restarted.load();
      expect(restarted.loaded, isTrue);
      expect(restarted.tracks.single.id, 'legacy');
      library.dispose();
      restarted.dispose();
    },
  );

  test(
    'failed library save rolls back memory and exposes a persistent error',
    () async {
      var fail = false;
      final backend = FileLibraryStorage(
        directory: () async => root,
        beforeCommit: (_) async {
          if (fail) throw const FileSystemException('disk full');
        },
      );
      final library = LibraryStore(storage: backend);
      await library.load();
      fail = true;
      await expectLater(
        library.addTracks([Track(id: 'lost', title: 'Lost')]),
        throwsA(isA<FileSystemException>()),
      );
      expect(library.tracks, isEmpty);
      expect(library.saveError, isNotNull);
      final restarted = LibraryStore(storage: storage);
      await restarted.load();
      expect(restarted.tracks, isEmpty);
      fail = false;
      await library.reloadSavedLibrary();
      expect(library.saveError, isNull);
      await library.addTracks([Track(id: 'retry', title: 'Retry')]);
      await restarted.reloadSavedLibrary();
      expect(restarted.tracks.single.id, 'retry');
      library.dispose();
      restarted.dispose();
    },
  );

  test(
    'overlapping saves commit in order without dropping either change',
    () async {
      final library = LibraryStore(storage: storage);
      await library.load();
      await Future.wait([
        library.addTracks([Track(id: 'one', title: 'One')]),
        library.addTracks([Track(id: 'two', title: 'Two')]),
        library.setOnboardingCompleted(true),
      ]);
      final restarted = LibraryStore(storage: storage);
      await restarted.load();
      expect(
        restarted.tracks.map((track) => track.id),
        containsAll(['one', 'two']),
      );
      expect(restarted.onboardingCompleted, isTrue);
      library.dispose();
      restarted.dispose();
    },
  );

  test('a failed save invalidates dependent queued changes', () async {
    var fail = false;
    final library = LibraryStore(
      storage: FileLibraryStorage(
        directory: () async => root,
        beforeCommit: (_) async {
          if (fail) throw const FileSystemException('disk full');
        },
      ),
    );
    await library.load();
    await library.addTracks([Track(id: 'saved', title: 'Saved')]);
    fail = true;
    await Future.wait([
      expectLater(
        library.addTracks([Track(id: 'unsaved', title: 'Unsaved')]),
        throwsA(isA<FileSystemException>()),
      ),
      expectLater(
        library.setOnboardingCompleted(true),
        throwsA(isA<LibraryStorageException>()),
      ),
    ]);
    expect(library.tracks.single.id, 'saved');
    expect(library.onboardingCompleted, isFalse);
    library.dispose();
  });

  test(
    'encoding failure rolls back after earlier valid queued saves',
    () async {
      final library = LibraryStore(storage: storage);
      await library.load();
      final saved = library.addTracks([Track(id: 'saved', title: 'Saved')]);
      final rejected = library.addTracks([
        Track(id: 'invalid', title: 'Invalid', replayGainTrackDb: double.nan),
      ]);
      await Future.wait([
        saved,
        expectLater(rejected, throwsA(isA<JsonUnsupportedObjectError>())),
        expectLater(
          library.setOnboardingCompleted(true),
          throwsA(isA<LibraryStorageException>()),
        ),
      ]);
      expect(library.tracks.single.id, 'saved');
      expect(library.onboardingCompleted, isFalse);
      expect(library.saveError, isNotNull);
      await library.reloadSavedLibrary();
      expect(library.saveError, isNull);
      expect(library.tracks.single.id, 'saved');
      await library.addTracks([Track(id: 'retry', title: 'Retry')]);
      final restarted = LibraryStore(storage: storage);
      await restarted.load();
      expect(
        restarted.tracks.map((track) => track.id),
        containsAll(['saved', 'retry']),
      );
      library.dispose();
      restarted.dispose();
    },
  );

  for (final key in [
    'tracks',
    'playlists',
    'custom_smart_playlists',
    'saved_history_views',
    'saved_library_views',
    'podcast_subscriptions',
    'lyrics',
    'playback_history',
    'playback_progress',
    'track_bookmarks',
    'track_bookmark_tombstones',
    'offline_cache_queue',
    'search_query_history',
  ]) {
    test(
      'corrupt $key produces a recoverable load state and keeps raw data',
      () async {
        final storageKey = 'aethertune.$key.v1';
        SharedPreferences.setMockInitialValues({storageKey: '{damaged'});
        final library = LibraryStore(storage: storage);
        await library.load();
        expect(library.loaded, isFalse);
        expect(library.loadError, isNotNull);
        expect(library.tracks, isEmpty);
        expect((await storage.read()), isNull);
        final data = jsonDecode(await library.exportRecoveryJson()) as Map;
        expect((data['legacy'] as Map)[storageKey], '{damaged');
        await library.resetAfterLoadFailure();
        expect(library.loaded, isTrue);
        expect(library.loadError, isNull);
        expect(
          (await SharedPreferences.getInstance()).getString(storageKey),
          '{damaged',
        );
        library.dispose();
      },
    );
  }

  test(
    'corrupted startup accepts a valid backup without a silent reset',
    () async {
      final source = LibraryStore();
      await source.load();
      await source.addTracks([Track(id: 'restored', title: 'Restored')]);
      final backup = source.exportBackupJson();
      SharedPreferences.setMockInitialValues({'aethertune.tracks.v1': '{bad'});
      final library = LibraryStore(storage: storage);
      await library.load();
      await expectLater(
        library.restoreBackupForRecovery('{bad'),
        throwsFormatException,
      );
      expect(library.loaded, isFalse);
      await library.restoreBackupForRecovery(backup);
      expect(library.loaded, isTrue);
      expect(library.loadError, isNull);
      expect(library.tracks.single.id, 'restored');
      final restarted = LibraryStore(storage: storage);
      await restarted.load();
      expect(restarted.tracks.single.id, 'restored');
      source.dispose();
      library.dispose();
      restarted.dispose();
    },
  );
}

Future<String> _runOtherWriter(
  String rootPath,
  String revision,
  SendPort port,
) => Isolate.run(() async {
  final other = FileLibraryStorage(directory: () async => Directory(rootPath));
  port.send('attempting');
  try {
    await other.write({'value': 'second'}, expectedRevision: revision);
    return 'overwritten';
  } on LibraryStorageConflict {
    return 'conflict';
  }
});
