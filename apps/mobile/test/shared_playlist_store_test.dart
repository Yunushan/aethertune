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
  Future<String> issueSharedPlaylistInvite({
    required String playlistId,
    required SharedPlaylistAccessRole role,
  }) async => 'BBBBBBBBBBBBBBBBBBBBBBBB';

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
    );
    return remote;
  }
}

SharedPlaylistRemote _remote({
  required SharedPlaylistAccessRole role,
  required int revision,
  required List<String> trackIds,
  String name = 'Shared mix',
}) {
  return SharedPlaylistRemote(
    id: _MemorySharedPlaylistGateway.id,
    revision: revision,
    role: role,
    name: name,
    trackIds: trackIds,
    updatedAt: DateTime.utc(2026, 7, 17),
    updatedByDevice: 'Test device',
  );
}
