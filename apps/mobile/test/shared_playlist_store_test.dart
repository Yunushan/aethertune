import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/shared_playlist_store.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/provider_search.dart';
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
    expect(
      store.bindingForLocalPlaylist(playlist.id)?.remoteId,
      _MemorySharedPlaylistGateway.id,
    );

    await library.replacePlaylistTracks(
      playlist.id,
      const <String>['one', 'two', 'one'],
    );
    final published = await store.publish(hosted, library);

    expect(published.revision, 2);
    expect(
      gateway.remote.trackReferences?.map((reference) => reference.title),
      <String>['One', 'Two', 'One'],
    );
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

  test('merges current server order with local-only track occurrences',
      () async {
    final library = await _libraryWithTracks();
    final playlist = await library.createPlaylist(
      'Local mix',
      trackIds: const <String>['two'],
    );
    final gateway = _MemorySharedPlaylistGateway();
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();
    final hosted = await store.host(library, playlist);
    gateway.remote = _remote(
      role: SharedPlaylistAccessRole.owner,
      revision: 2,
      name: 'Server mix',
      trackIds: const <String>['one'],
    );

    final merged = await store.mergeAndPublish(
      hosted,
      library,
      preferLocalName: true,
    );

    expect(merged.revision, 3);
    expect(gateway.remote.name, 'Local mix');
    expect(gateway.remote.trackIds, <String>['one', 'two']);
    expect(library.playlistById(playlist.id)?.trackIds, <String>['one', 'two']);
  });

  test('preserves server order and duplicate counts while merging', () {
    expect(
      mergeSharedPlaylistTrackIds(
        const <String>['one', 'two', 'one'],
        const <String>['one', 'three', 'one', 'one', 'two'],
      ),
      <String>['one', 'two', 'one', 'three', 'one'],
    );
  });

  test('resolves only unambiguous portable shared tracks in another library',
      () async {
    final recipientLibrary = LibraryStore();
    await recipientLibrary.load();
    await recipientLibrary.addTracks(<Track>[
      Track(
        id: 'recipient-one',
        title: 'One',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(minutes: 3),
        localPath: '/recipient/one.mp3',
      ),
      Track(
        id: 'ambiguous-one',
        title: 'One',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(minutes: 3),
        localPath: '/recipient/another-one.mp3',
      ),
      Track(
        id: 'recipient-two',
        title: 'Two',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(minutes: 4),
        localPath: '/recipient/two.mp3',
      ),
    ]);
    final gateway = _MemorySharedPlaylistGateway()
      ..remote = _remote(
        role: SharedPlaylistAccessRole.viewer,
        revision: 1,
        trackIds: const <String>[],
        trackReferences: const <SharedPlaylistTrackReference>[
          SharedPlaylistTrackReference(
            title: 'Two',
            artist: 'Artist',
            album: 'Album',
            durationMilliseconds: 240000,
          ),
          SharedPlaylistTrackReference(
            title: 'One',
            artist: 'Artist',
            album: 'Album',
            durationMilliseconds: 180000,
          ),
          SharedPlaylistTrackReference(
            title: 'Missing',
            artist: 'Artist',
            album: 'Album',
            durationMilliseconds: 0,
          ),
        ],
      );
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();

    final binding = await store.joinInvite(
      'BBBBBBBBBBBBBBBBBBBBBBBB',
      recipientLibrary,
    );

    expect(
      recipientLibrary.playlistById(binding.localPlaylistId)?.trackIds,
      <String>['recipient-two'],
    );
    expect(binding.unavailableTrackCount, 2);

    final reloaded = SharedPlaylistStore(gatewayFactory: () => gateway);
    await reloaded.load();
    expect(reloaded.bindings.single.unavailableTrackCount, 2);
  });

  test('merges portable shared track references without dropping duplicates', () {
    const one = SharedPlaylistTrackReference(
      title: 'One',
      artist: 'Artist',
      album: 'Album',
      durationMilliseconds: 180000,
    );
    const two = SharedPlaylistTrackReference(
      title: 'Two',
      artist: 'Artist',
      album: 'Album',
      durationMilliseconds: 240000,
    );
    final merged = mergeSharedPlaylistTrackReferences(
      const <SharedPlaylistTrackReference>[one, two, one],
      const <SharedPlaylistTrackReference>[one, one, one, two],
    );
    expect(
      merged.map((reference) => reference.title),
      <String>['One', 'Two', 'One', 'One'],
    );
  });

  test('adds only a single exact provider match for an unavailable shared track',
      () async {
    final library = LibraryStore();
    await library.load();
    final gateway = _MemorySharedPlaylistGateway()
      ..remote = _remote(
        role: SharedPlaylistAccessRole.viewer,
        revision: 1,
        trackIds: const <String>[],
        trackReferences: const <SharedPlaylistTrackReference>[
          SharedPlaylistTrackReference(
            title: 'Provider song',
            artist: 'Provider artist',
            album: 'Provider album',
            durationMilliseconds: 180000,
          ),
        ],
      );
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();
    final binding = await store.joinInvite(
      'BBBBBBBBBBBBBBBBBBBBBBBB',
      library,
    );
    final provider = _SearchProvider(
      tracks: <Track>[
        Track(
          id: 'provider-song',
          title: 'Provider song',
          artist: 'Provider artist',
          album: 'Provider album',
          duration: const Duration(minutes: 3),
          sourceId: 'provider',
          streamUrl: 'https://catalog.example.test/provider-song',
        ),
      ],
    );

    final result = await store.resolveUnavailableTracks(
      binding,
      library,
      ProviderSearchCoordinator(<MusicSourceProvider>[provider]),
    );

    expect(result.resolvedTrackCount, 1);
    expect(result.unavailableTrackCount, 0);
    expect(result.providerErrorCount, 0);
    expect(provider.queries, <String>['Provider song Provider artist Provider album']);
    expect(library.playlistById(binding.localPlaylistId)?.trackIds, <String>[
      'provider-song',
    ]);
    expect(store.bindings.single.unavailableTrackCount, 0);
  });

  test('keeps provider results unavailable when an exact match is ambiguous',
      () async {
    final library = LibraryStore();
    await library.load();
    final gateway = _MemorySharedPlaylistGateway()
      ..remote = _remote(
        role: SharedPlaylistAccessRole.viewer,
        revision: 1,
        trackIds: const <String>[],
        trackReferences: const <SharedPlaylistTrackReference>[
          SharedPlaylistTrackReference(
            title: 'Provider song',
            artist: 'Provider artist',
            album: 'Provider album',
            durationMilliseconds: 180000,
          ),
        ],
      );
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();
    final binding = await store.joinInvite(
      'BBBBBBBBBBBBBBBBBBBBBBBB',
      library,
    );
    final provider = _SearchProvider(
      tracks: <Track>[
        Track(
          id: 'provider-song-one',
          title: 'Provider song',
          artist: 'Provider artist',
          album: 'Provider album',
          duration: const Duration(minutes: 3),
          sourceId: 'provider',
          streamUrl: 'https://catalog.example.test/provider-song-one',
        ),
        Track(
          id: 'provider-song-two',
          title: 'Provider song',
          artist: 'Provider artist',
          album: 'Provider album',
          duration: const Duration(minutes: 3),
          sourceId: 'provider',
          streamUrl: 'https://catalog.example.test/provider-song-two',
        ),
      ],
    );

    final result = await store.resolveUnavailableTracks(
      binding,
      library,
      ProviderSearchCoordinator(<MusicSourceProvider>[provider]),
    );

    expect(result.resolvedTrackCount, 0);
    expect(result.unavailableTrackCount, 1);
    expect(library.tracks, isEmpty);
    expect(library.playlistById(binding.localPlaylistId)?.trackIds, isEmpty);
  });

  test('does not make a resolved duration-less shared track ambiguous',
      () async {
    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[
      Track(
        id: 'existing-song',
        title: 'Provider song',
        artist: 'Provider artist',
        album: 'Provider album',
        duration: const Duration(minutes: 2),
        localPath: '/library/existing-song.mp3',
      ),
    ]);
    final gateway = _MemorySharedPlaylistGateway()
      ..remote = _remote(
        role: SharedPlaylistAccessRole.viewer,
        revision: 1,
        trackIds: const <String>[],
        trackReferences: const <SharedPlaylistTrackReference>[
          SharedPlaylistTrackReference(
            title: 'Provider song',
            artist: 'Provider artist',
            album: 'Provider album',
            durationMilliseconds: 0,
          ),
          SharedPlaylistTrackReference(
            title: 'Provider song',
            artist: 'Provider artist',
            album: 'Provider album',
            durationMilliseconds: 180000,
          ),
        ],
      );
    final store = SharedPlaylistStore(gatewayFactory: () => gateway);
    await store.load();
    final binding = await store.joinInvite(
      'BBBBBBBBBBBBBBBBBBBBBBBB',
      library,
    );
    final provider = _SearchProvider(
      tracks: <Track>[
        Track(
          id: 'provider-song',
          title: 'Provider song',
          artist: 'Provider artist',
          album: 'Provider album',
          duration: const Duration(minutes: 3),
          sourceId: 'provider',
          streamUrl: 'https://catalog.example.test/provider-song',
        ),
      ],
    );

    final result = await store.resolveUnavailableTracks(
      binding,
      library,
      ProviderSearchCoordinator(<MusicSourceProvider>[provider]),
    );

    expect(result.resolvedTrackCount, 0);
    expect(result.unavailableTrackCount, 1);
    expect(library.tracks.map((track) => track.id), <String>['existing-song']);
    expect(library.playlistById(binding.localPlaylistId)?.trackIds, <String>[
      'existing-song',
    ]);
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

class _SearchProvider implements MusicSourceProvider {
  _SearchProvider({required this.tracks});

  final List<Track> tracks;
  final List<String> queries = <String>[];

  @override
  Set<MusicSourceCapability> get capabilities =>
      const <MusicSourceCapability>{MusicSourceCapability.metadataSearch};

  @override
  String get description => 'Test provider';

  @override
  ProviderPrivacyDisclosure get disclosure =>
      const ProviderPrivacyDisclosure(networkDomains: <String>['catalog.example.test']);

  @override
  String get id => 'provider';

  @override
  String get name => 'Test provider';

  @override
  Future<Uri?> resolveStream(Track track) async => null;

  @override
  Future<List<Track>> search(String query) async {
    queries.add(query);
    return tracks;
  }
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
    List<SharedPlaylistTrackReference>? trackReferences,
  }) async {
    remote = _remote(
      role: SharedPlaylistAccessRole.owner,
      revision: 1,
      name: name,
      trackIds: trackReferences == null ? trackIds : const <String>[],
      trackReferences: trackReferences,
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
        trackReferences: remote.trackReferences,
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
      trackReferences: remote.trackReferences,
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
    List<SharedPlaylistTrackReference>? trackReferences,
  }) async {
    if (baseRevision != remote.revision) {
      throw SharedPlaylistConflictException(currentRevision: remote.revision);
    }
    remote = _remote(
      role: remote.role,
      revision: remote.revision + 1,
      name: name,
      trackIds: trackReferences == null ? trackIds : const <String>[],
      trackReferences: trackReferences,
      collaborators: remote.collaborators,
    );
    return remote;
  }
}

SharedPlaylistRemote _remote({
  required SharedPlaylistAccessRole role,
  required int revision,
  required List<String> trackIds,
  List<SharedPlaylistTrackReference>? trackReferences,
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
    trackReferences: trackReferences,
    updatedAt: DateTime.utc(2026, 7, 17),
    updatedByDevice: 'Test device',
    collaborators: collaborators,
  );
}
