import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/shared_playlist_store.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('hosts and explicitly publishes a private shared playlist', () async {
    final library = await _libraryWithTracks();
    final playlist = await library.createPlaylist(
      'Road mix',
      trackIds: const <String>['one'],
    );
    final gateway = _MemorySharedPlaylistGateway();
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();

    final hosted = await store.host(library, playlist);
    expect(hosted.isOwner, isTrue);
    expect(hosted.revision, 1);
    expect(store.bindingForLocalPlaylist(playlist.id)?.remoteId, gateway.id);

    await library.replacePlaylistTracks(
      playlist.id,
      const <String>['one', 'two', 'one'],
    );
    final published = await store.publish(hosted, library);

    expect(published.revision, 2);
    expect(gateway.remote.trackIds, <String>['one', 'two', 'one']);
  });

  test('joins an invite as a local playlist and preserves repeated tracks',
      () async {
    final library = await _libraryWithTracks();
    final gateway = _MemorySharedPlaylistGateway()
      ..remote = _remote(
        role: SharedPlaylistAccessRole.viewer,
        revision: 3,
        trackIds: const <String>['one', 'two', 'one'],
      );
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();

    final binding = await store.joinInvite(
      'BBBBBBBBBBBBBBBBBBBBBBBB',
      library,
    );

    final local = library.playlistById(binding.localPlaylistId);
    expect(binding.role, SharedPlaylistAccessRole.viewer);
    expect(local?.name, 'Shared mix');
    expect(local?.trackIds, <String>['one', 'two', 'one']);
    await expectLater(
      store.publish(binding, library),
      throwsA(isA<StateError>()),
    );
  });

  test('owners can revoke a collaborator and retain the new revision',
      () async {
    final library = await _libraryWithTracks();
    final playlist = await library.createPlaylist(
      'Road mix',
      trackIds: const <String>['one'],
    );
    final gateway = _MemorySharedPlaylistGateway();
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();
    final hosted = await store.host(library, playlist);
    gateway.remote = _remote(
      role: SharedPlaylistAccessRole.owner,
      revision: 2,
      trackIds: const <String>['one'],
      collaborators: const <String, SharedPlaylistAccessRole>{
        'viewer-account': SharedPlaylistAccessRole.viewer,
      },
    );
    final refreshed = await store.refresh(hosted, library);

    final revoked = await store.revokeCollaborator(
      refreshed,
      'viewer-account',
      library,
    );

    expect(revoked.revision, 3);
    expect(revoked.collaborators, isEmpty);
  });

  test('owners can invalidate unused private invite codes', () async {
    final library = await _libraryWithTracks();
    final playlist = await library.createPlaylist('Road mix');
    final gateway = _MemorySharedPlaylistGateway();
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();
    final hosted = await store.host(library, playlist);

    expect(await store.invalidateUnusedInvites(hosted, library), 2);
  });

  test('loads revision history without changing the local playlist', () async {
    final library = await _libraryWithTracks();
    final playlist = await library.createPlaylist('Road mix');
    final gateway = _MemorySharedPlaylistGateway();
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();
    final hosted = await store.host(library, playlist);

    final history = await store.history(hosted, library);

    expect(history.map((revision) => revision.revision), <int>[1]);
    expect(library.playlistById(playlist.id)?.trackIds, isEmpty);
  });

  test('restores an earlier revision as a new shared playlist revision',
      () async {
    final library = await _libraryWithTracks();
    final playlist = await library.createPlaylist(
      'Current mix',
      trackIds: const <String>['two'],
    );
    final gateway = _MemorySharedPlaylistGateway();
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();
    final hosted = await store.host(library, playlist);
    await library.replacePlaylistTracks(playlist.id, const <String>['two']);
    final current = await store.publish(hosted, library);

    final restored = await store.restoreRevision(
      current,
      SharedPlaylistRevision(
        revision: 1,
        name: 'Earlier mix',
        trackIds: const <String>['one', 'one'],
        updatedAt: DateTime.utc(2026, 7, 17),
        updatedByDevice: 'Phone',
        checksum: 'a' * 64,
      ),
      library,
    );

    expect(restored.revision, 3);
    expect(gateway.remote.name, 'Earlier mix');
    expect(gateway.remote.trackIds, <String>['one', 'one']);
    expect(library.playlistById(playlist.id)?.name, 'Earlier mix');
    expect(library.playlistById(playlist.id)?.trackIds, <String>['one', 'one']);
  });
}

Future<LibraryStore> _libraryWithTracks() async {
  final library = LibraryStore();
  await library.load();
  await library.addTracks(<Track>[
    Track(id: 'one', title: 'One', localPath: '/music/one.mp3'),
    Track(id: 'two', title: 'Two', localPath: '/music/two.mp3'),
  ]);
  return library;
}

class _MemorySharedPlaylistGateway implements SharedPlaylistGateway {
  static const id = 'AAAAAAAAAAAAAAAAAAAAAAAA';
  SharedPlaylistRemote remote = _remote(
    role: SharedPlaylistAccessRole.owner,
    revision: 1,
    trackIds: const <String>[],
  );

  @override
  Future<SharedPlaylistRemote> createSharedPlaylist({
    required String name,
    required List<String> trackIds,
  }) async {
    remote = _remote(
      role: SharedPlaylistAccessRole.owner,
      revision: 1,
      name: name,
      trackIds: trackIds,
    );
    return remote;
  }

  @override
  Future<void> deleteSharedPlaylist({
    required String playlistId,
    required int baseRevision,
  }) async {
    if (baseRevision != remote.revision) {
      throw SharedPlaylistConflictException(currentRevision: remote.revision);
    }
  }

  @override
  Future<SharedPlaylistRemote> fetchSharedPlaylist(String playlistId) async =>
      remote;

  @override
  Future<List<SharedPlaylistRevision>> fetchSharedPlaylistHistory(
    String playlistId,
  ) async => <SharedPlaylistRevision>[
    SharedPlaylistRevision(
      revision: remote.revision,
      name: remote.name,
      trackIds: remote.trackIds,
      updatedAt: remote.updatedAt ?? DateTime.utc(2026, 7, 17),
      updatedByDevice: remote.updatedByDevice ?? 'Test device',
      checksum: 'a' * 64,
    ),
  ];

  @override
  Future<SharedPlaylistInvitation> issueSharedPlaylistInvite({
    required String playlistId,
    required SharedPlaylistAccessRole role,
  }) async => SharedPlaylistInvitation(
    code: 'BBBBBBBBBBBBBBBBBBBBBBBB',
    role: role,
    expiresAt: DateTime.utc(2026, 7, 24),
  );

  @override
  Future<int> invalidateSharedPlaylistInvites({
    required String playlistId,
  }) async => 2;

  @override
  Future<SharedPlaylistRemote> revokeSharedPlaylistCollaborator({
    required String playlistId,
    required String collaboratorId,
    required int baseRevision,
  }) async {
    if (baseRevision != remote.revision) {
      throw SharedPlaylistConflictException(currentRevision: remote.revision);
    }
    final collaborators = <String, SharedPlaylistAccessRole>{
      ...remote.collaborators,
    }..remove(collaboratorId);
    remote = _remote(
      role: remote.role,
      revision: remote.revision + 1,
      name: remote.name,
      trackIds: remote.trackIds,
      collaborators: collaborators,
    );
    return remote;
  }

  @override
  Future<SharedPlaylistRemote> joinSharedPlaylistInvite(String inviteCode) async =>
      remote;

  @override
  Future<SharedPlaylistRemote> updateSharedPlaylist({
    required String playlistId,
    required int baseRevision,
    required String name,
    required List<String> trackIds,
  }) async {
    if (baseRevision != remote.revision) {
      throw SharedPlaylistConflictException(currentRevision: remote.revision);
    }
    remote = _remote(
      role: remote.role,
      revision: remote.revision + 1,
      name: name,
      trackIds: trackIds,
      collaborators: remote.collaborators,
    );
    return remote;
  }
}

SharedPlaylistRemote _remote({
  required SharedPlaylistAccessRole role,
  required int revision,
  required List<String> trackIds,
  String name = 'Shared mix',
  Map<String, SharedPlaylistAccessRole> collaborators =
      const <String, SharedPlaylistAccessRole>{},
}) {
  return SharedPlaylistRemote(
    id: _MemorySharedPlaylistGateway.id,
    revision: revision,
    role: role,
    name: name,
    trackIds: trackIds,
    updatedAt: DateTime.utc(2026, 7, 17),
    updatedByDevice: 'Test device',
    collaborators: collaborators,
  );
}
