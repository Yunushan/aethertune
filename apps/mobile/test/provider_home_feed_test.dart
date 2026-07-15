import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/music_catalog_discovery_provider.dart';
import 'package:aethertune/src/domain/music_catalog_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/provider_home_feed.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  test(
    'loads bounded album and playlist sections from unique providers',
    () async {
      final first = _FakeHomeCatalogProvider(
        id: 'first',
        name: 'First Server',
        albums: const <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'album-1',
            title: 'First Album',
            kind: MusicCatalogCollectionKind.album,
          ),
          MusicCatalogCollection(
            id: 'album-1',
            title: 'Duplicate Album',
            kind: MusicCatalogCollectionKind.album,
          ),
          MusicCatalogCollection(
            id: 'wrong-kind',
            title: 'Wrong Kind',
            kind: MusicCatalogCollectionKind.artist,
          ),
          MusicCatalogCollection(
            id: 'blank-title',
            title: '   ',
            kind: MusicCatalogCollectionKind.album,
          ),
          MusicCatalogCollection(
            id: 'album-2',
            title: 'Second Album',
            kind: MusicCatalogCollectionKind.album,
          ),
          MusicCatalogCollection(
            id: 'album-3',
            title: 'Beyond Limit',
            kind: MusicCatalogCollectionKind.album,
          ),
        ],
        playlists: const <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'playlist-1',
            title: 'First Playlist',
            kind: MusicCatalogCollectionKind.playlist,
          ),
        ],
      );
      final duplicate = _FakeHomeCatalogProvider(
        id: 'first',
        name: 'Duplicate Server',
      );
      final second = _FakeHomeCatalogProvider(
        id: 'second',
        name: 'Second Server',
        albums: const <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'album-4',
            title: 'Remote Album',
            kind: MusicCatalogCollectionKind.album,
          ),
        ],
      );

      final feed = await const ProviderHomeFeedCoordinator().load(
        <MusicCatalogProvider>[first, duplicate, second],
        limitPerSection: 2,
      );

      expect(
        feed.sections.map(
          (section) => '${section.provider.id}:${section.kind.name}',
        ),
        <String>['first:album', 'first:playlist', 'second:album'],
      );
      expect(
        feed.sections.first.collections.map((collection) => collection.id),
        <String>['album-1', 'album-2'],
      );
      expect(feed.errors, isEmpty);
      expect(first.browseCalls, <MusicCatalogCollectionKind>[
        MusicCatalogCollectionKind.album,
        MusicCatalogCollectionKind.playlist,
      ]);
      expect(duplicate.browseCalls, isEmpty);
      expect(second.browseCalls, <MusicCatalogCollectionKind>[
        MusicCatalogCollectionKind.album,
        MusicCatalogCollectionKind.playlist,
      ]);
      expect(feed.hasContent, isTrue);
      expect(() => feed.sections.clear(), throwsUnsupportedError);
      expect(
        () => feed.sections.first.collections.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'isolates provider section failures without exposing raw errors',
    () async {
      final provider = _FakeHomeCatalogProvider(
        id: 'private',
        name: 'Private Server',
        failAlbums: true,
        playlists: const <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'playlist-1',
            title: 'Still Available',
            kind: MusicCatalogCollectionKind.playlist,
          ),
        ],
      );

      final feed = await const ProviderHomeFeedCoordinator().load(
        <MusicCatalogProvider>[provider],
      );

      expect(feed.sections, hasLength(1));
      expect(feed.sections.single.kind, MusicCatalogCollectionKind.playlist);
      expect(feed.errors, hasLength(1));
      expect(feed.errors.single.providerId, 'private');
      expect(feed.errors.single.providerName, 'Private Server');
      expect(feed.errors.single.kind, MusicCatalogCollectionKind.album);
    },
  );

  test(
    'prefers isolated discovery shelves and retains provider playlists',
    () async {
      final provider = _FakeHomeCatalogProvider(
        id: 'discovery',
        name: 'Discovery Server',
        discoveryKinds: const <MusicCatalogDiscoveryKind>[
          MusicCatalogDiscoveryKind.recentlyAdded,
          MusicCatalogDiscoveryKind.frequentlyPlayed,
          MusicCatalogDiscoveryKind.frequentlyPlayed,
        ],
        discoveryCollections: const <
            MusicCatalogDiscoveryKind,
            List<MusicCatalogCollection>>{
          MusicCatalogDiscoveryKind.recentlyAdded:
              <MusicCatalogCollection>[
            MusicCatalogCollection(
              id: 'new-1',
              title: 'New Album',
              kind: MusicCatalogCollectionKind.album,
            ),
            MusicCatalogCollection(
              id: 'new-1',
              title: 'Duplicate Album',
              kind: MusicCatalogCollectionKind.album,
            ),
            MusicCatalogCollection(
              id: 'wrong-kind',
              title: 'Wrong Kind',
              kind: MusicCatalogCollectionKind.playlist,
            ),
          ],
        },
        failDiscoveryKinds: const <MusicCatalogDiscoveryKind>{
          MusicCatalogDiscoveryKind.frequentlyPlayed,
        },
        albums: const <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'fallback-album',
            title: 'Fallback Album',
            kind: MusicCatalogCollectionKind.album,
          ),
        ],
        playlists: const <MusicCatalogCollection>[
          MusicCatalogCollection(
            id: 'playlist-1',
            title: 'Server Playlist',
            kind: MusicCatalogCollectionKind.playlist,
          ),
        ],
      );

      final feed = await const ProviderHomeFeedCoordinator().load(
        <MusicCatalogProvider>[provider],
      );

      expect(feed.sections, hasLength(2));
      expect(
        feed.sections.first.discoveryKind,
        MusicCatalogDiscoveryKind.recentlyAdded,
      );
      expect(feed.sections.first.collections.single.id, 'new-1');
      expect(feed.sections.last.kind, MusicCatalogCollectionKind.playlist);
      expect(provider.browseCalls, <MusicCatalogCollectionKind>[
        MusicCatalogCollectionKind.playlist,
      ]);
      expect(provider.discoveryCalls, <MusicCatalogDiscoveryKind>[
        MusicCatalogDiscoveryKind.recentlyAdded,
        MusicCatalogDiscoveryKind.frequentlyPlayed,
      ]);
      expect(feed.errors, hasLength(1));
      expect(
        feed.errors.single.discoveryKind,
        MusicCatalogDiscoveryKind.frequentlyPlayed,
      );
      expect(feed.errors.single.kind, MusicCatalogCollectionKind.album);
    },
  );

  test('does not contact providers for invalid bounds', () async {
    final provider = _FakeHomeCatalogProvider(id: 'server', name: 'Server');
    const coordinator = ProviderHomeFeedCoordinator();

    expect(
      (await coordinator.load(<MusicCatalogProvider>[
        provider,
      ], limitPerSection: 0)).sections,
      isEmpty,
    );
    expect(
      (await coordinator.load(<MusicCatalogProvider>[
        provider,
      ], maxProviders: 0)).sections,
      isEmpty,
    );
    expect(provider.browseCalls, isEmpty);
  });
}

final class _FakeHomeCatalogProvider
    implements MusicCatalogDiscoveryProvider {
  _FakeHomeCatalogProvider({
    required this.id,
    required this.name,
    this.albums = const <MusicCatalogCollection>[],
    this.playlists = const <MusicCatalogCollection>[],
    this.failAlbums = false,
    this.discoveryKinds = const <MusicCatalogDiscoveryKind>[],
    this.discoveryCollections = const <
        MusicCatalogDiscoveryKind,
        List<MusicCatalogCollection>>{},
    this.failDiscoveryKinds = const <MusicCatalogDiscoveryKind>{},
  });

  @override
  final String id;

  @override
  final String name;

  final List<MusicCatalogCollection> albums;
  final List<MusicCatalogCollection> playlists;
  final bool failAlbums;
  @override
  final List<MusicCatalogDiscoveryKind> discoveryKinds;
  final Map<MusicCatalogDiscoveryKind, List<MusicCatalogCollection>>
      discoveryCollections;
  final Set<MusicCatalogDiscoveryKind> failDiscoveryKinds;
  final List<MusicCatalogCollectionKind> browseCalls =
      <MusicCatalogCollectionKind>[];
  final List<MusicCatalogDiscoveryKind> discoveryCalls =
      <MusicCatalogDiscoveryKind>[];

  @override
  String get description => 'Test catalog';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
    MusicSourceCapability.libraryBrowse,
  };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
    networkDomains: <String>['music.example.test'],
    dataSent: <String>['catalog request'],
    requiresUserCredentials: true,
  );

  @override
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  ) async {
    browseCalls.add(kind);
    if (kind == MusicCatalogCollectionKind.album && failAlbums) {
      throw StateError('secret-token-leak');
    }
    return switch (kind) {
      MusicCatalogCollectionKind.album => albums,
      MusicCatalogCollectionKind.playlist => playlists,
      MusicCatalogCollectionKind.artist => const <MusicCatalogCollection>[],
    };
  }

  @override
  Future<List<MusicCatalogCollection>> browseDiscoveryCollections(
    MusicCatalogDiscoveryKind kind, {
    int limit = 6,
  }) async {
    discoveryCalls.add(kind);
    if (failDiscoveryKinds.contains(kind)) {
      throw StateError('private-discovery-error');
    }
    return discoveryCollections[kind] ?? const <MusicCatalogCollection>[];
  }

  @override
  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  ) async {
    return MusicCatalogDetail(collection: collection);
  }

  @override
  Future<Uint8List?> loadArtwork(
    String artworkId, {
    String? version,
    int maxWidth = 512,
  }) async {
    return null;
  }

  @override
  Future<List<Track>> search(String query) async => const <Track>[];

  @override
  Future<Uri?> resolveStream(Track track) async => null;
}
