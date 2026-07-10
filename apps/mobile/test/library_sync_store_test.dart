import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/library_sync_credential_vault.dart';
import 'package:aethertune/src/data/library_sync_store.dart';
import 'package:aethertune/src/domain/library_sync_account.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('tests before saving metadata and keeps token only in the vault',
      () async {
    final vault = _MemorySyncVault();
    final gateway = _FakeSyncGateway(
      remote: LibrarySyncRemoteSnapshot(
        revision: 3,
        updatedAt: DateTime.utc(2026, 7, 10, 12),
        updatedByDevice: 'Phone',
        checksum: 'checksum',
        snapshot: _emptySnapshot(),
      ),
    );
    final store = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) {
        expect(token, 'private-token');
        return gateway;
      },
    );
    await store.load();

    await store.testAndSave(_account(), 'private-token');

    expect(store.isConfigured, isTrue);
    expect(store.lastKnownRevision, 0);
    expect(store.remoteRevision, 3);
    expect(vault.token, 'private-token');
    final prefs = await SharedPreferences.getInstance();
    final metadata = prefs.getString('aethertune.library_sync.metadata.v1')!;
    expect(metadata, contains('sync.example.test'));
    expect(metadata, contains('Test device'));
    expect(metadata, isNot(contains('private-token')));

    final restored = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
    );
    await restored.load();
    expect(restored.isConfigured, isTrue);
    expect(restored.remoteRevision, 3);
  });

  test('failed connection and vault writes do not replace working settings',
      () async {
    final vault = _MemorySyncVault();
    final firstGateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
    );
    var activeGateway = firstGateway;
    final store = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => activeGateway,
    );
    await store.load();
    await store.testAndSave(_account(), 'old-token');

    activeGateway = _FakeSyncGateway(
      fetchError: StateError('Rejected replacement-token.'),
    );
    await expectLater(
      store.testAndSave(_account(deviceId: 'Changed device'), 'replacement-token'),
      throwsA(
        predicate<Object>((error) {
          final message = error.toString();
          return message.contains('[redacted]') &&
              !message.contains('replacement-token');
        }),
      ),
    );
    expect(vault.token, 'old-token');
    expect(store.account?.deviceId, 'Test device');

    activeGateway = firstGateway;
    vault.failNextWriteFor = 'write-failure-token';
    await expectLater(
      store.testAndSave(_account(deviceId: 'Changed device'), 'write-failure-token'),
      throwsA(isA<Exception>()),
    );
    expect(vault.token, 'old-token');
    expect(store.account?.deviceId, 'Test device');
  });

  test('push detects conflicts and explicit overwrite advances revision',
      () async {
    final vault = _MemorySyncVault();
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
    );
    final sync = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
      clock: () => DateTime.utc(2026, 7, 10, 15),
    );
    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[
      Track(id: 'track-1', title: 'Track 1', localPath: '/music/track.mp3'),
    ]);
    await sync.load();
    await sync.testAndSave(_account(), 'token');
    gateway.pushError = const LibrarySyncConflictException(
      currentRevision: 4,
      updatedByDevice: 'Other device',
    );

    await expectLater(
      sync.push(library),
      throwsA(isA<LibrarySyncConflictException>()),
    );
    expect(sync.lastKnownRevision, 0);
    expect(sync.remoteRevision, 4);
    expect(sync.conflict?.updatedByDevice, 'Other device');

    gateway
      ..pushError = null
      ..pushResult = LibrarySyncRemoteSnapshot(
        revision: 5,
        updatedAt: DateTime.utc(2026, 7, 10, 14),
        updatedByDevice: 'Test device',
        checksum: 'new-checksum',
      );
    await sync.push(library, baseRevision: sync.conflict!.currentRevision);

    expect(gateway.pushedBaseRevisions, <int>[0, 4]);
    expect(sync.lastKnownRevision, 5);
    expect(sync.remoteRevision, 5);
    expect(sync.conflict, isNull);
    expect(sync.lastSyncAt, DateTime.utc(2026, 7, 10, 15));
    final pushedJson = jsonEncode(gateway.pushedSnapshots.last);
    expect(pushedJson, isNot(contains('/music/track.mp3')));
  });

  test('pull applies remote library and preserves matched local file', () async {
    final remoteStore = LibraryStore();
    await remoteStore.load();
    await remoteStore.addTracks(<Track>[
      Track(
        id: 'remote-id',
        title: 'Remote title',
        localPath: '/desktop/music.mp3',
        contentHash: 'same-file',
      ),
    ]);
    final snapshot = jsonDecode(remoteStore.exportSyncSnapshotJson())
        as Map<String, dynamic>;

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final localStore = LibraryStore();
    await localStore.load();
    await localStore.addTracks(<Track>[
      Track(
        id: 'local-id',
        title: 'Local title',
        localPath: '/phone/music.mp3',
        contentHash: 'same-file',
      ),
    ]);
    final gateway = _FakeSyncGateway(
      remote: LibrarySyncRemoteSnapshot(
        revision: 2,
        updatedAt: DateTime.utc(2026, 7, 10),
        updatedByDevice: 'Desktop',
        checksum: 'checksum',
        snapshot: Map<String, Object?>.from(snapshot),
      ),
    );
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await sync.load();
    await sync.testAndSave(_account(), 'token');

    await sync.pull(localStore);

    expect(localStore.tracks.single.id, 'remote-id');
    expect(localStore.tracks.single.title, 'Remote title');
    expect(localStore.tracks.single.localPath, '/phone/music.mp3');
    expect(sync.lastKnownRevision, 2);
    expect(sync.conflict, isNull);
  });

  test('offline mode blocks network sync and removal clears secure state',
      () async {
    final vault = _MemorySyncVault();
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
    );
    final sync = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
    );
    final library = LibraryStore();
    await library.load();
    await sync.load();
    await sync.testAndSave(_account(), 'token');
    await library.setOfflineModeEnabled(true);

    await expectLater(sync.push(library), throwsA(isA<StateError>()));
    await expectLater(sync.pull(library), throwsA(isA<StateError>()));
    expect(gateway.pushCalls, 0);

    await sync.remove();
    expect(sync.isConfigured, isFalse);
    expect(vault.token, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('aethertune.library_sync.metadata.v1'), isNull);
  });
}

LibrarySyncAccount _account({String deviceId = 'Test device'}) {
  return createLibrarySyncAccount(
    baseUrl: 'https://sync.example.test',
    deviceId: deviceId,
    allowInsecureHttp: false,
  );
}

Map<String, Object?> _emptySnapshot() {
  return <String, Object?>{
    'syncVersion': 1,
    'version': 1,
    'tracks': <Object?>[],
    'playlists': <Object?>[],
    'lyrics': <Object?>[],
    'offlineCacheQueue': <Object?>[],
  };
}

class _MemorySyncVault implements LibrarySyncCredentialVault {
  String? token;
  String? failNextWriteFor;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async {
    this.token = token;
    if (failNextWriteFor == token) {
      failNextWriteFor = null;
      throw StateError('Could not store $token.');
    }
  }

  @override
  Future<void> delete() async {
    token = null;
  }
}

class _FakeSyncGateway implements LibrarySyncGateway {
  _FakeSyncGateway({required this.remote, this.fetchError});

  LibrarySyncRemoteSnapshot remote;
  Object? fetchError;
  Object? pushError;
  LibrarySyncRemoteSnapshot? pushResult;
  int pushCalls = 0;
  final List<int> pushedBaseRevisions = <int>[];
  final List<Map<String, Object?>> pushedSnapshots =
      <Map<String, Object?>>[];

  @override
  Future<LibrarySyncRemoteSnapshot> fetch() async {
    if (fetchError != null) {
      throw fetchError!;
    }
    return remote;
  }

  @override
  Future<LibrarySyncRemoteSnapshot> push({
    required int baseRevision,
    required Map<String, Object?> snapshot,
  }) async {
    pushCalls += 1;
    pushedBaseRevisions.add(baseRevision);
    pushedSnapshots.add(snapshot);
    if (pushError != null) {
      throw pushError!;
    }
    return pushResult ??
        LibrarySyncRemoteSnapshot(
          revision: baseRevision + 1,
          updatedAt: DateTime.utc(2026, 7, 10),
          updatedByDevice: 'Test device',
          checksum: 'checksum',
        );
  }
}
