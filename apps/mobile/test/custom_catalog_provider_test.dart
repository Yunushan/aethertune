import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/custom_catalog_provider.dart';
import 'package:aethertune/src/data/custom_catalog_store.dart';
import 'package:aethertune/src/domain/custom_catalog_definition.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('normalizes a declared custom catalog and rejects unconsented HTTP', () {
    final definition = CustomCatalogDefinition.create(
      id: 'catalog-001',
      name: '  Community mixes ',
      catalogUrl: 'HTTPS://Catalog.Example.test/music.json#ignored',
      mediaDomains: <String>['CDN.example.test', 'cdn.example.test'],
      allowInsecureHttp: false,
      description: ' Open music ',
    );

    expect(definition.name, 'Community mixes');
    expect(definition.catalogUri.scheme, 'https');
    expect(definition.catalogUri.host, 'catalog.example.test');
    expect(definition.catalogUri.path, '/music.json');
    expect(definition.mediaDomains, <String>['cdn.example.test']);
    expect(
      definition.declaredNetworkDomains,
      <String>['catalog.example.test', 'cdn.example.test'],
    );
    expect(
      () => CustomCatalogDefinition.create(
        id: 'catalog-002',
        name: 'LAN',
        catalogUrl: 'http://192.168.1.20/catalog.json',
        mediaDomains: const <String>[],
        allowInsecureHttp: false,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CustomCatalogDefinition.create(
        id: 'catalog-002b',
        name: 'Token catalog',
        catalogUrl: 'https://catalog.example.test/music.json?token=secret',
        mediaDomains: const <String>[],
        allowInsecureHttp: false,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('searches a declared catalog and only resolves declared media hosts',
      () async {
    final definition = CustomCatalogDefinition.create(
      id: 'catalog-003',
      name: 'Community mixes',
      catalogUrl: 'https://catalog.example.test/music.json',
      mediaDomains: const <String>['cdn.example.test'],
      allowInsecureHttp: false,
    );
    Uri? requestedUri;
    final provider = CustomCatalogProvider(
      definition,
      catalogLoader: (uri) async {
        requestedUri = uri;
        return jsonEncode(<String, Object?>{
          'version': 1,
          'tracks': <Object?>[
            <String, Object?>{
              'id': 'night-drive',
              'title': 'Night Drive',
              'artist': 'Open Artist',
              'album': 'City Lights',
              'genre': 'Electronic',
              'durationMs': 185000,
              'streamUrl': 'https://cdn.example.test/audio/night-drive.mp3',
              'artworkUrl': 'https://cdn.example.test/art/night-drive.jpg',
            },
          ],
        });
      },
    );

    final tracks = await provider.search('drive');

    expect(requestedUri, definition.catalogUri);
    expect(tracks, hasLength(1));
    expect(tracks.single.id, 'custom-catalog-catalog-003:night-drive');
    expect(tracks.single.sourceId, definition.providerId);
    expect(tracks.single.duration, const Duration(milliseconds: 185000));
    expect(
      await provider.resolveStream(tracks.single),
      Uri.parse('https://cdn.example.test/audio/night-drive.mp3'),
    );
    expect(
      provider.capabilities,
      containsAll(const <MusicSourceCapability>[
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.directPlayback,
      ]),
    );
    expect(provider.disclosure.networkDomains, definition.declaredNetworkDomains);
  });

  test('rejects catalog media URLs outside the user-declared domains', () {
    final definition = CustomCatalogDefinition.create(
      id: 'catalog-004',
      name: 'Bounded catalog',
      catalogUrl: 'https://catalog.example.test/music.json',
      mediaDomains: const <String>[],
      allowInsecureHttp: false,
    );

    expect(
      () => parseCustomCatalogTracks(
        jsonEncode(<String, Object?>{
          'version': 1,
          'tracks': <Object?>[
            <String, Object?>{
              'id': 'untrusted',
              'title': 'Untrusted host',
              'streamUrl': 'https://tracker.example.test/stream.mp3',
            },
          ],
        }),
        definition,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('pages and suggests bounded matching catalog tracks', () async {
    final definition = CustomCatalogDefinition.create(
      id: 'catalog-006',
      name: 'Paged catalog',
      catalogUrl: 'https://catalog.example.test/music.json',
      mediaDomains: const <String>['cdn.example.test'],
      allowInsecureHttp: false,
    );
    var requests = 0;
    final provider = CustomCatalogProvider(
      definition,
      catalogLoader: (_) async {
        requests += 1;
        return jsonEncode(<String, Object?>{
          'version': 1,
          'tracks': <Object?>[
            <String, Object?>{
              'id': 'night-drive',
              'title': 'Night Drive',
              'artist': 'Mira',
              'album': 'City Lights',
              'streamUrl': 'https://cdn.example.test/night-drive.mp3',
            },
            <String, Object?>{
              'id': 'day-drive',
              'title': 'Day Drive',
              'artist': 'Orbit',
              'album': 'Signals',
              'streamUrl': 'https://cdn.example.test/day-drive.mp3',
            },
          ],
        });
      },
    );

    final firstPage = await provider.searchPage(' drive ', limit: 1);
    expect(firstPage.totalCount, 2);
    expect(firstPage.tracks.single.title, 'Night Drive');
    expect(firstPage.nextCursor, '1');

    final secondPage = await provider.searchPage(
      'drive',
      cursor: firstPage.nextCursor,
      limit: 100,
    );
    expect(secondPage.tracks.single.title, 'Day Drive');
    expect(secondPage.nextCursor, isNull);

    final suggestions = await provider.suggest('drive', limit: 1);
    expect(suggestions, hasLength(1));
    expect(suggestions.single.value, 'Night Drive');
    expect(suggestions.single.kind, MusicSourceSearchSuggestionKind.track);
    expect(suggestions.single.subtitle, 'Mira - City Lights');
    expect(
      provider.capabilities,
      contains(MusicSourceCapability.searchSuggestions),
    );
    expect(await provider.suggest('  '), isEmpty);
    expect(requests, 3);
    await expectLater(provider.searchPage('drive', limit: 0), throwsArgumentError);
    await expectLater(provider.suggest('drive', limit: 0), throwsArgumentError);
  });

  test('persists bounded custom catalog definitions without provider secrets',
      () async {
    final store = CustomCatalogStore();
    await store.load();
    final definition = CustomCatalogDefinition.create(
      id: 'catalog-005',
      name: 'Stored catalog',
      catalogUrl: 'https://catalog.example.test/music.json',
      mediaDomains: const <String>['cdn.example.test'],
      allowInsecureHttp: false,
    );

    await store.save(definition);

    final preferences = await SharedPreferences.getInstance();
    final persisted = preferences.getString('aethertune.custom_catalogs.v1')!;
    expect(persisted, contains('catalog.example.test'));
    expect(persisted, isNot(contains('token')));
    final restored = CustomCatalogStore();
    await restored.load();
    final restoredDefinition = restored.definitions.single;
    expect(restoredDefinition.id, definition.id);
    expect(restoredDefinition.name, definition.name);
    expect(restoredDefinition.catalogUri.toString(), definition.catalogUri.toString());
    expect(restoredDefinition.mediaDomains, definition.mediaDomains);
    expect(restored.musicProviders.single.id, definition.providerId);

    await restored.remove(definition.id);
    expect(restored.definitions, isEmpty);
  });
}
