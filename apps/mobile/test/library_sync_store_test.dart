import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/library_sync_credential_vault.dart';
import 'package:aethertune/src/data/library_sync_store.dart';
import 'package:aethertune/src/data/provider_error.dart';
import 'package:aethertune/src/domain/library_sync_account.dart';
import 'package:aethertune/src/domain/library_sync_profile.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_queue.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';

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
      profile: _managedProfile(),
    );
    final store = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) {
        expect(token, 'private-token');
        return gateway;
      },
    );
    await store.load();
    final library = LibraryStore();
    await library.load();

    await store.testAndSave(library, _account(), 'private-token');

    expect(store.isConfigured, isTrue);
    expect(store.lastKnownRevision, 0);
    expect(store.remoteRevision, 3);
    expect(store.profile?.effectiveDisplayName, 'Primary listener');
    expect(store.profile?.device?.name, 'Windows desktop');
    expect(vault.token, 'private-token');
    final prefs = await SharedPreferences.getInstance();
    final metadata = prefs.getString('aethertune.library_sync.metadata.v1')!;
    expect(metadata, contains('sync.example.test'));
    expect(metadata, contains('Test device'));
    expect(metadata, contains('Primary listener'));
    expect(metadata, contains('Windows desktop'));
    expect(metadata, isNot(contains('private-token')));

    final restored = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
    );
    await restored.load();
    expect(restored.isConfigured, isTrue);
    expect(restored.remoteRevision, 3);
    expect(restored.profile?.id, 'primary');
    expect(restored.profile?.device?.name, 'Windows desktop');
  });

  test('refreshes and persists non-secret account identity', () async {
    final vault = _MemorySyncVault();
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
      profile: _managedProfile(),
    );
    final store = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
    );
    final library = LibraryStore();
    await library.load();
    await store.load();
    await store.testAndSave(library, _account(), 'private-token');

    gateway.profile = LibrarySyncProfile(
      id: 'primary',
      displayName: 'Updated listener',
      managed: true,
      device: _managedProfile().device,
      editable: true,
    );
    await store.refreshProfile(library);

    expect(gateway.profileFetchCalls, 2);
    expect(store.profile?.effectiveDisplayName, 'Updated listener');
    final restored = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
    );
    await restored.load();
    expect(restored.profile?.effectiveDisplayName, 'Updated listener');
    final metadata = (await SharedPreferences.getInstance()).getString(
      'aethertune.library_sync.metadata.v1',
    )!;
    expect(metadata, isNot(contains('private-token')));
  });

  test('updates managed identity and local upload attribution', () async {
    final vault = _MemorySyncVault();
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
      profile: _managedProfile(),
    );
    final store = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
    );
    final library = LibraryStore();
    await library.load();
    await store.load();
    await store.testAndSave(library, _account(), 'private-token');

    final updated = await store.updateProfile(
      library,
      displayName: '  Shared listeners  ',
      deviceName: '  Pocket player  ',
    );

    expect(gateway.profileUpdateCalls, 1);
    expect(gateway.lastDisplayName, 'Shared listeners');
    expect(gateway.lastDeviceName, 'Pocket player');
    expect(updated.id, 'primary');
    expect(updated.device?.id, _managedProfile().device?.id);
    expect(store.profile?.effectiveDisplayName, 'Shared listeners');
    expect(store.profile?.device?.name, 'Pocket player');
    expect(store.account?.deviceId, 'Pocket player');

    final restored = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
    );
    await restored.load();
    expect(restored.profile?.effectiveDisplayName, 'Shared listeners');
    expect(restored.profile?.device?.name, 'Pocket player');
    expect(restored.account?.deviceId, 'Pocket player');
    final metadata = (await SharedPreferences.getInstance()).getString(
      'aethertune.library_sync.metadata.v1',
    )!;
    expect(metadata, isNot(contains('private-token')));

    gateway.profileUpdateResult = LibrarySyncProfile(
      id: 'different-account',
      displayName: 'Invalid identity',
      managed: true,
      device: _managedProfile().device,
      editable: true,
    );
    await expectLater(
      store.updateProfile(
        library,
        displayName: 'Invalid identity',
        deviceName: 'Pocket player',
      ),
      throwsA(isA<ProviderRequestException>()),
    );
    expect(store.profile?.effectiveDisplayName, 'Shared listeners');
    expect(store.account?.deviceId, 'Pocket player');
  });

  test('failed connection and vault writes do not replace working settings',
      () async {
    final vault = _MemorySyncVault();
    final firstGateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
      profile: _managedProfile(),
    );
    var activeGateway = firstGateway;
    final store = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => activeGateway,
    );
    await store.load();
    final library = LibraryStore();
    await library.load();
    await store.testAndSave(library, _account(), 'old-token');

    activeGateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
      fetchError: StateError('Rejected replacement-token.'),
    );
    await expectLater(
      store.testAndSave(
        library,
        _account(deviceId: 'Changed device'),
        'replacement-token',
      ),
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
    expect(store.profile?.effectiveDisplayName, 'Primary listener');

    activeGateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
      profile: LibrarySyncProfile(
        id: 'replacement',
        displayName: 'Replacement profile',
        managed: true,
        device: _managedProfile().device,
      ),
    );
    vault.failNextWriteFor = 'write-failure-token';
    await expectLater(
      store.testAndSave(
        library,
        _account(deviceId: 'Changed device'),
        'write-failure-token',
      ),
      throwsA(isA<Exception>()),
    );
    expect(vault.token, 'old-token');
    expect(store.account?.deviceId, 'Test device');
    expect(store.profile?.effectiveDisplayName, 'Primary listener');
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
    await sync.testAndSave(library, _account(), 'token');
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
    await sync.testAndSave(localStore, _account(), 'token');

    await sync.pull(localStore);

    expect(localStore.tracks.single.id, 'remote-id');
    expect(localStore.tracks.single.title, 'Remote title');
    expect(localStore.tracks.single.localPath, '/phone/music.mp3');
    expect(sync.lastKnownRevision, 2);
    expect(sync.conflict, isNull);
  });

  test('opt-in queue sync shares only IDs and restores the remote queue',
      () async {
    final library = LibraryStore();
    await library.load();
    final localFirst = Track(
      id: 'local-first',
      title: 'Local first',
      localPath: '/phone/local-first.mp3',
    );
    final localSecond = Track(
      id: 'local-second',
      title: 'Local second',
      localPath: '/phone/local-second.mp3',
    );
    await library.addTracks(<Track>[localFirst, localSecond]);
    final engine = _QueueSyncPlaybackAudioEngine();
    final player = PlayerController(
      audioEngine: engine,
      clock: () => DateTime.utc(2026, 7, 16, 10),
    );
    addTearDown(player.dispose);
    await player.playTrack(
      localSecond,
      queue: <Track>[
        localFirst,
        Track(
          id: 'search-only',
          title: 'Search-only result',
          streamUrl: 'https://private.example.test/stream?token=secret',
        ),
        localSecond,
      ],
    );
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
    );
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    await sync.setQueueSyncEnabled(true);

    await sync.push(library, player: player);

    final pushedQueue = Map<String, Object?>.from(
      gateway.pushedSnapshots.single['queueSync']! as Map,
    );
    expect(pushedQueue['trackIds'], <String>['local-first', 'local-second']);
    expect(pushedQueue['currentTrackId'], 'local-second');
    final pushedJson = jsonEncode(gateway.pushedSnapshots.single);
    expect(pushedJson, isNot(contains('/phone/local-first.mp3')));
    expect(pushedJson, isNot(contains('private.example.test')));

    final remoteLibrary = LibraryStore();
    await remoteLibrary.load();
    await remoteLibrary.addTracks(<Track>[
      Track(id: 'remote-first', title: 'Remote first'),
      Track(id: 'remote-second', title: 'Remote second'),
    ]);
    final remoteSnapshot = Map<String, Object?>.from(
      jsonDecode(remoteLibrary.exportSyncSnapshotJson()) as Map,
    )..['queueSync'] = TrackQueueReferenceSnapshot(
        trackIds: const <String>['remote-second', 'remote-first'],
        currentTrackId: 'remote-first',
        updatedAt: DateTime.utc(2026, 7, 16, 11),
      ).toJson();
    gateway.remote = LibrarySyncRemoteSnapshot(
      revision: 2,
      updatedAt: DateTime.utc(2026, 7, 16, 11),
      updatedByDevice: 'Desktop',
      checksum: 'remote-checksum',
      snapshot: remoteSnapshot,
    );

    await sync.pull(library, player: player);

    expect(player.queue.map((track) => track.id), <String>[
      'remote-second',
      'remote-first',
    ]);
    expect(player.current?.id, 'remote-first');
    expect(engine.playingValue, isFalse);
    expect(engine.stopCalls, 1);
  });

  test('deletes only the remote snapshot and disables automatic upload',
      () async {
    final gateway = _FakeSyncGateway(
      remote: LibrarySyncRemoteSnapshot(
        revision: 4,
        updatedAt: DateTime.utc(2026, 7, 10),
        updatedByDevice: 'Desktop',
        checksum: 'checksum',
        snapshot: _emptySnapshot(),
      ),
    )
      ..deleteResult = LibrarySyncRemoteSnapshot(
        revision: 5,
        updatedAt: DateTime.utc(2026, 7, 11),
        updatedByDevice: 'Test device',
      );
    final library = LibraryStore();
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
      clock: () => DateTime.utc(2026, 7, 11),
    );
    await library.load();
    await library.addTracks(<Track>[Track(id: 'local', title: 'Local')]);
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    await sync.setAutomaticUploadEnabled(true);

    final result = await sync.deleteRemoteSnapshot(library);

    expect(gateway.deletedBaseRevisions, <int>[4]);
    expect(result.revision, 5);
    expect(result.hasSnapshot, isFalse);
    expect(sync.lastKnownRevision, 5);
    expect(sync.remoteRevision, 5);
    expect(sync.automaticUploadEnabled, isFalse);
    expect(library.tracks.single.id, 'local');
  });

  test('merge and push keeps the accepted merged library', () async {
    final remoteSnapshot = _emptySnapshot()
      ..['tracks'] = <Object?>[
        Track(id: 'remote-track', title: 'Remote track').toJson(),
      ];
    final gateway = _FakeSyncGateway(
      remote: LibrarySyncRemoteSnapshot(
        revision: 4,
        updatedAt: DateTime.utc(2026, 7, 12),
        updatedByDevice: 'Desktop',
        checksum: 'remote-checksum',
        snapshot: remoteSnapshot,
      ),
    );
    final library = LibraryStore();
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await library.load();
    await library.addTracks(<Track>[Track(id: 'local-track', title: 'Local')]);
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');

    await sync.mergeAndPush(library);

    expect(library.tracks.map((track) => track.id), containsAll(<String>[
      'local-track',
      'remote-track',
    ]));
    expect(gateway.pushedBaseRevisions, <int>[4]);
    expect(sync.lastKnownRevision, 5);
  });

  test('merge and push keeps saved history views from both devices', () async {
    final remoteLibrary = LibraryStore(
      clock: () => DateTime.utc(2026, 7, 12, 10),
    );
    await remoteLibrary.load();
    await remoteLibrary.createSavedHistoryView(
      name: 'Desktop recent albums',
      query: 'album',
      range: ListeningHistoryRange.thirtyDays,
    );
    final remoteSnapshot = Map<String, Object?>.from(
      jsonDecode(remoteLibrary.exportSyncSnapshotJson()) as Map,
    );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore(
      clock: () => DateTime.utc(2026, 7, 12, 11),
    );
    await library.load();
    await library.createSavedHistoryView(
      name: 'Phone favorites',
      query: 'favorite',
      range: ListeningHistoryRange.sevenDays,
    );
    final gateway = _FakeSyncGateway(
      remote: LibrarySyncRemoteSnapshot(
        revision: 4,
        updatedAt: DateTime.utc(2026, 7, 12, 10),
        updatedByDevice: 'Desktop',
        checksum: 'remote-checksum',
        snapshot: remoteSnapshot,
      ),
    );
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');

    await sync.mergeAndPush(library);

    expect(
      library.savedHistoryViews.map((view) => view.name),
      containsAll(<String>['Desktop recent albums', 'Phone favorites']),
    );
    final pushedViews = gateway.pushedSnapshots.single['savedHistoryViews']
        as List<Object?>;
    expect(pushedViews, hasLength(2));
  });

  test('merge and push keeps saved library views from both devices', () async {
    final remoteLibrary = LibraryStore(
      clock: () => DateTime.utc(2026, 7, 12, 10),
    );
    await remoteLibrary.load();
    await remoteLibrary.createSavedLibraryView(
      name: 'Desktop albums',
      query: 'album',
      sortMode: LibrarySortMode.album,
    );
    final remoteSnapshot = Map<String, Object?>.from(
      jsonDecode(remoteLibrary.exportSyncSnapshotJson()) as Map,
    );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore(
      clock: () => DateTime.utc(2026, 7, 12, 11),
    );
    await library.load();
    await library.createSavedLibraryView(
      name: 'Phone offline favorites',
      query: 'favorite',
      favoritesOnly: true,
      offlineOnly: true,
    );
    final gateway = _FakeSyncGateway(
      remote: LibrarySyncRemoteSnapshot(
        revision: 4,
        updatedAt: DateTime.utc(2026, 7, 12, 10),
        updatedByDevice: 'Desktop',
        checksum: 'remote-checksum',
        snapshot: remoteSnapshot,
      ),
    );
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');

    await sync.mergeAndPush(library);

    expect(
      library.savedLibraryViews.map((view) => view.name),
      containsAll(<String>['Desktop albums', 'Phone offline favorites']),
    );
    final pushedViews = gateway.pushedSnapshots.single['savedLibraryViews']
        as List<Object?>;
    expect(pushedViews, hasLength(2));
  });

  test('merge and push restores the local library when the server rejects it',
      () async {
    final remoteSnapshot = _emptySnapshot()
      ..['tracks'] = <Object?>[
        Track(id: 'remote-track', title: 'Remote track').toJson(),
      ];
    final gateway = _FakeSyncGateway(
      remote: LibrarySyncRemoteSnapshot(
        revision: 4,
        updatedAt: DateTime.utc(2026, 7, 12),
        updatedByDevice: 'Desktop',
        checksum: 'remote-checksum',
        snapshot: remoteSnapshot,
      ),
    )..pushError = StateError('Server rejected merged snapshot.');
    final library = LibraryStore();
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await library.load();
    await library.addTracks(<Track>[Track(id: 'local-track', title: 'Local')]);
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');

    await expectLater(
      sync.mergeAndPush(library),
      throwsA(isA<StateError>()),
    );

    expect(library.tracks.map((track) => track.id), <String>['local-track']);
    expect(sync.lastKnownRevision, 0);
  });

  test('automatic uploads are opt-in, paced, persisted, and conflict-safe',
      () async {
    var now = DateTime.utc(2026, 7, 11, 9);
    final vault = _MemorySyncVault();
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
    );
    final library = LibraryStore();
    final sync = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
      clock: () => now,
    );
    await library.load();
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');

    expect(await sync.uploadAutomaticallyIfDue(library), isFalse);
    expect(gateway.pushCalls, 0);

    await sync.setAutomaticUploadEnabled(true);
    expect(await sync.uploadAutomaticallyIfDue(library), isTrue);
    expect(gateway.pushCalls, 1);
    expect(sync.lastAutomaticUploadAt, now);

    now = now.add(const Duration(minutes: 14));
    expect(await sync.uploadAutomaticallyIfDue(library), isFalse);
    expect(gateway.pushCalls, 1);

    now = now.add(const Duration(minutes: 1));
    await library.setOfflineModeEnabled(true);
    expect(await sync.uploadAutomaticallyIfDue(library), isFalse);
    expect(gateway.pushCalls, 1);
    await library.setOfflineModeEnabled(false);

    now = now.add(const Duration(minutes: 15));
    gateway.pushError = const LibrarySyncConflictException(
      currentRevision: 7,
      updatedByDevice: 'Desktop',
    );
    expect(await sync.uploadAutomaticallyIfDue(library), isFalse);
    expect(gateway.pushCalls, 2);
    expect(sync.conflict?.currentRevision, 7);
    expect(sync.lastAutomaticUploadAt, DateTime.utc(2026, 7, 11, 9));

    final restored = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
      clock: () => now,
    );
    await restored.load();
    expect(restored.automaticUploadEnabled, isTrue);
    expect(restored.lastAutomaticUploadAt, DateTime.utc(2026, 7, 11, 9));
  });

  test('automatic uploads avoid sending a stale library snapshot', () async {
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
    );
    final library = LibraryStore();
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await library.load();
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    await sync.setAutomaticUploadEnabled(true);
    gateway.remote = const LibrarySyncRemoteSnapshot(
      revision: 3,
      updatedByDevice: 'Desktop',
      checksum: 'checksum',
    );

    expect(await sync.uploadAutomaticallyIfDue(library), isFalse);
    expect(gateway.metadataFetchCalls, 1);
    expect(gateway.pushCalls, 0);
    expect(sync.conflict?.currentRevision, 3);
    expect(sync.remoteUpdatedByDevice, 'Desktop');
  });

  test('automatic uploads fall back for older sync servers', () async {
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
    )..metadataUnavailable = true;
    final library = LibraryStore();
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await library.load();
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    await sync.setAutomaticUploadEnabled(true);

    expect(await sync.uploadAutomaticallyIfDue(library), isTrue);
    expect(gateway.metadataFetchCalls, 1);
    expect(gateway.pushCalls, 1);
  });

  test('automatic uploads skip an unchanged library snapshot', () async {
    var now = DateTime.utc(2026, 7, 11, 9);
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
    )..usesSnapshotChecksum = true;
    final library = LibraryStore();
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
      clock: () => now,
    );
    await library.load();
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    await sync.setAutomaticUploadEnabled(true);

    expect(await sync.uploadAutomaticallyIfDue(library), isTrue);
    now = now.add(LibrarySyncStore.automaticUploadInterval);
    expect(await sync.uploadAutomaticallyIfDue(library), isFalse);
    expect(gateway.metadataFetchCalls, 2);
    expect(gateway.pushCalls, 1);
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
    await sync.testAndSave(library, _account(), 'token');
    await library.setOfflineModeEnabled(true);

    await expectLater(sync.push(library), throwsA(isA<StateError>()));
    await expectLater(sync.pull(library), throwsA(isA<StateError>()));
    expect(gateway.pushCalls, 0);

    await sync.remove();
    expect(sync.isConfigured, isFalse);
    expect(sync.profile, isNull);
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

LibrarySyncProfile _managedProfile() {
  return LibrarySyncProfile(
    id: 'primary',
    displayName: 'Primary listener',
    managed: true,
    device: LibrarySyncProfileDevice(
      id: '0123456789abcdef01234567',
      name: 'Windows desktop',
      createdAt: DateTime.utc(2026, 7, 15, 12),
    ),
    editable: true,
  );
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

class _FakeSyncGateway
    implements
        LibrarySyncGateway,
        LibrarySyncMetadataGateway,
        LibrarySyncProfileGateway,
        LibrarySyncProfileEditorGateway {
  _FakeSyncGateway({
    required this.remote,
    this.profile,
    this.fetchError,
  });

  LibrarySyncRemoteSnapshot remote;
  LibrarySyncProfile? profile;
  Object? fetchError;
  Object? pushError;
  LibrarySyncRemoteSnapshot? pushResult;
  Object? deleteError;
  LibrarySyncRemoteSnapshot? deleteResult;
  Object? profileUpdateError;
  LibrarySyncProfile? profileUpdateResult;
  int pushCalls = 0;
  int metadataFetchCalls = 0;
  bool metadataUnavailable = false;
  bool usesSnapshotChecksum = false;
  int profileFetchCalls = 0;
  int profileUpdateCalls = 0;
  String? lastDisplayName;
  String? lastDeviceName;
  final List<int> pushedBaseRevisions = <int>[];
  final List<int> deletedBaseRevisions = <int>[];
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
  Future<LibrarySyncRemoteSnapshot?> fetchMetadata() async {
    metadataFetchCalls += 1;
    return metadataUnavailable ? null : remote;
  }

  @override
  Future<LibrarySyncProfile?> fetchProfile() async {
    profileFetchCalls += 1;
    return profile;
  }

  @override
  Future<LibrarySyncProfile> updateProfile({
    required String displayName,
    required String deviceName,
  }) async {
    profileUpdateCalls += 1;
    lastDisplayName = displayName;
    lastDeviceName = deviceName;
    if (profileUpdateError != null) {
      throw profileUpdateError!;
    }
    final current = profile;
    if (current == null || current.device == null) {
      throw StateError('No managed profile.');
    }
    final result = profileUpdateResult ??
        LibrarySyncProfile(
          id: current.id,
          displayName: displayName,
          managed: true,
          device: LibrarySyncProfileDevice(
            id: current.device!.id,
            name: deviceName,
            createdAt: current.device!.createdAt,
          ),
          editable: current.editable,
        );
    profile = result;
    return result;
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
    final result = pushResult ??
        LibrarySyncRemoteSnapshot(
          revision: baseRevision + 1,
          updatedAt: DateTime.utc(2026, 7, 10),
          updatedByDevice: 'Test device',
          checksum: usesSnapshotChecksum
              ? sha256.convert(utf8.encode(jsonEncode(snapshot))).toString()
              : 'checksum',
        );
    remote = result;
    return result;
  }

  @override
  Future<LibrarySyncRemoteSnapshot> delete({
    required int baseRevision,
  }) async {
    deletedBaseRevisions.add(baseRevision);
    if (deleteError != null) {
      throw deleteError!;
    }
    return deleteResult ??
        LibrarySyncRemoteSnapshot(
          revision: baseRevision + 1,
          updatedAt: DateTime.utc(2026, 7, 10),
          updatedByDevice: 'Test device',
        );
  }
}

class _QueueSyncPlaybackAudioEngine implements PlaybackAudioEngine {
  List<Track> queue = <Track>[];
  bool playingValue = false;
  int stopCalls = 0;

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
  }) async {
    queue = List<Track>.from(tracks);
  }

  @override
  Future<void> play() async {
    playingValue = true;
  }

  @override
  Future<void> pause() async {
    playingValue = false;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    playingValue = false;
  }

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
