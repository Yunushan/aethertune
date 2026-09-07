import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aethertune/src/data/file_library_storage.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_queue.dart';
import 'package:aethertune/src/player/player_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/player_storage_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'migrates all legacy player sections without changing preference bytes',
    () async {
      final legacy = _values('Legacy');
      SharedPreferences.setMockInitialValues({
        ...legacy,
        'unrelated': 'preserved',
      });
      final storage = ControlledPlayerStorage();
      final store = PlayerStateStore(storage: storage);
      expect(await store.load(), isTrue);
      expect(storage.current!.values, legacy);
      expect(storage.writes, 1);
      expect(await store.write(_values('New')), isTrue);
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      expect(preferences.getString('unrelated'), 'preserved');
      for (final key in legacy.keys) {
        expect(preferences.getString(key), legacy[key]);
      }
      final reopened = PlayerStateStore(storage: storage);
      expect(await reopened.load(), isTrue);
      expect(reopened.values, _values('New'));
    },
  );

  test(
    'migration ignores rejected values left only in the singleton cache',
    () async {
      final preferences = await SharedPreferences.getInstance();
      SharedPreferencesStorePlatform.instance = _RejectingPreferences.empty();
      expect(
        await preferences.setString(
          PlayerStateStore.queueKey,
          _values('Phantom')[PlayerStateStore.queueKey]!,
        ),
        isFalse,
      );
      expect(preferences.getString(PlayerStateStore.queueKey), isNotNull);
      final storage = ControlledPlayerStorage();
      expect(await PlayerStateStore(storage: storage).load(), isTrue);
      expect(storage.current!.values, isEmpty);
      expect(
        preferences.getString(PlayerStateStore.queueKey),
        isNotNull,
        reason: 'Migration must not replace the shared cache',
      );
    },
  );

  for (final key in [
    PlayerStateStore.queueKey,
    PlayerStateStore.queuesKey,
    PlayerStateStore.settingsKey,
  ]) {
    test('keeps corrupt legacy $key and refuses migration writes', () async {
      SharedPreferences.setMockInitialValues({key: '{broken'});
      final storage = ControlledPlayerStorage();
      final store = PlayerStateStore(storage: storage);
      expect(await store.load(), isFalse);
      expect(await store.write(_values('Replacement')), isFalse);
      expect(storage.writes, 0);
      expect((await SharedPreferences.getInstance()).getString(key), '{broken');
      expect(store.error, isNotNull);
    });
  }

  test(
    'rejects collections and tracks that would be silently discarded',
    () async {
      for (final raw in [
        {
          'version': 1,
          'activeQueueId': 'default',
          'queues': [null],
        },
        {'version': 2, 'activeQueueId': 'default', 'queues': []},
        {
          'version': 1,
          'activeQueueId': 'default',
          'queues': List.generate(
            13,
            (i) => {
              'id': i == 0 ? 'default' : '$i',
              'name': '$i',
              'snapshot': {'tracks': []},
            },
          ),
        },
        {
          'version': 1,
          'activeQueueId': 'default',
          'queues': [
            {
              'id': 'default',
              'name': 'Queue',
              'snapshot': {
                'tracks': [null],
              },
            },
          ],
        },
      ]) {
        SharedPreferences.setMockInitialValues({
          PlayerStateStore.queuesKey: jsonEncode(raw),
        });
        final storage = ControlledPlayerStorage();
        expect(await PlayerStateStore(storage: storage).load(), isFalse);
        expect(storage.writes, 0);
      }
    },
  );

  test('serializes overlapping section saves and preserves both', () async {
    final storage = ControlledPlayerStorage();
    final store = PlayerStateStore(storage: storage);
    expect(await store.load(), isTrue);
    storage.writeStarted = Completer();
    storage.releaseWrite = Completer();
    final queue = store.write({
      PlayerStateStore.queueKey: _values('Queue')[PlayerStateStore.queueKey],
    });
    await storage.writeStarted!.future;
    final settings = store.write({
      PlayerStateStore.settingsKey: '{"volume":0.4}',
    });
    storage.releaseWrite!.complete();
    expect(await queue, isTrue);
    expect(await settings, isTrue);
    expect(
      storage.current!.values[PlayerStateStore.queueKey],
      contains('Queue'),
    );
    expect(
      storage.current!.values[PlayerStateStore.settingsKey],
      '{"volume":0.4}',
    );
  });

  test('a failed commit cancels queued saves until explicit reload', () async {
    final storage = ControlledPlayerStorage();
    final store = PlayerStateStore(storage: storage);
    expect(await store.load(), isTrue);
    expect(await store.write(_values('Saved')), isTrue);
    storage.failWrites = true;
    storage.writeStarted = Completer();
    storage.releaseWrite = Completer();
    final first = store.write(_values('Lost'));
    await storage.writeStarted!.future;
    final queued = store.write({
      PlayerStateStore.settingsKey: '{"volume":0.9}',
    });
    storage.releaseWrite!.complete();
    expect(await first, isFalse);
    expect(await queued, isFalse);
    expect(storage.writes, 3);
    expect(store.values, _values('Saved'));
    storage.failWrites = false;
    expect(await store.write(_values('Blocked')), isFalse);
    expect(await store.reload(), isTrue);
    expect(await store.write(_values('Retry')), isTrue);
  });

  test('stale writers cannot overwrite a newer process snapshot', () async {
    final storage = ControlledPlayerStorage();
    final first = PlayerStateStore(storage: storage);
    final second = PlayerStateStore(storage: storage);
    expect(await first.load(), isTrue);
    expect(await second.load(), isTrue);
    expect(
      await first.write({PlayerStateStore.settingsKey: '{"volume":0.3}'}),
      isTrue,
    );
    expect(await second.write(_values('Stale')), isFalse);
    expect(second.error, contains('another process'));
    expect(storage.current!.values, {
      PlayerStateStore.settingsKey: '{"volume":0.3}',
    });
    expect(await second.reload(), isTrue);
    expect(
      await second.write({
        PlayerStateStore.queueKey: _values('Fresh')[PlayerStateStore.queueKey],
      }),
      isTrue,
    );
    expect(
      storage.current!.values[PlayerStateStore.settingsKey],
      '{"volume":0.3}',
    );
  });

  test(
    'real file commit failure preserves bytes and reopens the last saved state',
    () async {
      final root = await _temporaryDirectory();
      var fail = false;
      final storage = FileLibraryStorage(
        directory: () async => root,
        beforeCommit: (_) async {
          if (fail) throw const FileSystemException('Injected disk failure');
        },
      );
      final store = PlayerStateStore(storage: storage);
      expect(await store.load(), isTrue);
      expect(await store.write(_values('Saved')), isTrue);
      final file = File(p.join(root.path, 'library.json'));
      final before = await file.readAsBytes();
      fail = true;
      expect(await store.write(_values('Rejected')), isFalse);
      expect(await file.readAsBytes(), before);
      final reopened = PlayerStateStore(
        storage: FileLibraryStorage(directory: () async => root),
      );
      expect(await reopened.load(), isTrue);
      expect(reopened.values, _values('Saved'));
    },
  );

  test(
    'explicit previous-file recovery archives corrupt current bytes',
    () async {
      final root = await _temporaryDirectory();
      final storage = FileLibraryStorage(directory: () async => root);
      final store = PlayerStateStore(storage: storage);
      expect(await store.load(), isTrue);
      expect(await store.write(_values('Previous')), isTrue);
      expect(await store.write(_values('Latest')), isTrue);
      final file = File(p.join(root.path, 'library.json'));
      await file.writeAsString('damaged-synthetic-data', flush: true);
      expect(await store.reload(), isFalse);
      expect(await store.write(_values('Overwrite')), isFalse);
      expect(await file.readAsString(), 'damaged-synthetic-data');
      expect(await store.reload(previous: true), isTrue);
      expect(store.values, _values('Previous'));
      final archives = await Directory(p.join(root.path, 'recovery'))
          .list(recursive: true)
          .where(
            (entry) =>
                entry is File && p.basename(entry.path) == 'library.json',
          )
          .toList();
      expect(archives, hasLength(1));
      expect(
        await File(archives.single.path).readAsString(),
        'damaged-synthetic-data',
      );
    },
  );
}

Map<String, String> _values(String title) {
  final queue = TrackQueueSnapshot(
    tracks: [Track(id: 'fixture', title: title, localPath: '/fixture.wav')],
    currentTrackId: 'fixture',
    currentIndex: 0,
  );
  return {
    PlayerStateStore.queueKey: jsonEncode(queue.toJson()),
    PlayerStateStore.queuesKey: jsonEncode(
      SavedTrackQueueCollection(
        activeQueueId: 'default',
        queues: [SavedTrackQueue(id: 'default', name: title, snapshot: queue)],
      ).toJson(),
    ),
    PlayerStateStore.settingsKey: '{"volume":0.5}',
  };
}

Future<Directory> _temporaryDirectory() async {
  final root = await Directory.systemTemp.createTemp(
    'aethertune-player-state-',
  );
  addTearDown(() async {
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    final actual = await root.resolveSymbolicLinks();
    if (!p.isWithin(temp, actual) ||
        !p.basename(actual).startsWith('aethertune-player-state-')) {
      throw StateError('Refusing to remove an unexpected fixture directory');
    }
    await root.delete(recursive: true);
  });
  return root;
}

class _RejectingPreferences extends InMemorySharedPreferencesStore {
  _RejectingPreferences.empty() : super.empty();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}
