import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/data/self_hosted_provider_store.dart';
import 'package:aethertune/src/domain/music_catalog_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/self_hosted_provider_account.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('validates URLs and requires explicit consent for HTTP', () {
    final secure = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.jellyfin,
      name: '',
      baseUrl: 'HTTPS://MEDIA.EXAMPLE.TEST/jellyfin/',
      identity: ' user-1 ',
      allowInsecureHttp: false,
    );

    expect(secure.name, 'Jellyfin');
    expect(secure.baseUri, Uri.parse('https://media.example.test/jellyfin'));
    expect(secure.identity, 'user-1');
    expect(secure.usesSecureTransport, isTrue);
    final caseSensitivePath = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.jellyfin,
      name: '',
      baseUrl: 'https://media.example.test/Jellyfin',
      identity: 'user-1',
      allowInsecureHttp: false,
    );
    expect(caseSensitivePath.id, isNot(secure.id));
    expect(
      () => createSelfHostedProviderAccount(
        kind: SelfHostedProviderKind.subsonic,
        name: 'LAN music',
        baseUrl: 'http://192.168.1.10:4533',
        identity: 'yunus',
        allowInsecureHttp: false,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => normalizeSelfHostedBaseUri(
        'https://user:secret@example.test/music?token=leak',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('stores secrets only in the vault and reconstructs providers', () async {
    final vault = _MemoryCredentialVault();
    final tested = <String>[];
    final store = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {
        tested.add('${account.providerId}:$secret');
      },
    );
    await store.load();
    final account = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.subsonic,
      name: 'Home music',
      baseUrl: 'https://music.example.test/navidrome',
      identity: 'yunus',
      allowInsecureHttp: false,
    );

    await store.testAndSave(account, 'super-secret');

    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getString('aethertune.self_hosted_accounts.v1')!;
    expect(persisted, contains('music.example.test'));
    expect(persisted, contains('yunus'));
    expect(persisted, isNot(contains('super-secret')));
    expect(vault.values[account.id], 'super-secret');
    expect(tested.single, '${account.providerId}:super-secret');
    expect(store.musicProviders.single.id, account.providerId);
    expect(
      store.catalogProviderFor(account.id),
      isA<MusicCatalogProvider>(),
    );
    expect(store.catalogProviderFor('missing-account'), isNull);

    final secondStore = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {},
    );
    await secondStore.load();
    expect(secondStore.accounts.single.name, 'Home music');
    expect(secondStore.hasCredential(account.id), isTrue);
    expect(secondStore.catalogProviderFor(account.id)!.id, account.providerId);

    final resolved = await secondStore.resolveTrack(
      Track(
        id: 'song',
        title: 'Song',
        sourceId: account.providerId,
        externalId: 'song-1',
      ),
    );
    expect(resolved.streamUrl, contains('/rest/stream.view'));
    final resolvedUri = Uri.parse(resolved.streamUrl!);
    expect(resolvedUri.queryParameters['t'], hasLength(32));
    expect(resolvedUri.queryParameters['s'], isNotEmpty);
    expect(resolvedUri.queryParameters.containsKey('p'), isFalse);
    expect(resolved.streamUrl, isNot(contains('super-secret')));
    expect(resolved.streamUrlIsEphemeral, isTrue);
    expect(resolved.toJson()['streamUrl'], isNull);

    await secondStore.remove(account.id);
    expect(secondStore.accounts, isEmpty);
    expect(secondStore.musicProviders, isEmpty);
    expect(secondStore.catalogProviderFor(account.id), isNull);
    expect(vault.values.containsKey(account.id), isFalse);
  });

  test('keeps the existing secure secret when an edit leaves it blank', () async {
    final vault = _MemoryCredentialVault();
    final testedSecrets = <String>[];
    final store = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {
        testedSecrets.add(secret);
      },
    );
    await store.load();
    final account = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.jellyfin,
      name: 'Jellyfin',
      baseUrl: 'https://media.example.test',
      identity: 'user-1',
      allowInsecureHttp: false,
    );
    await store.testAndSave(account, 'api-key');
    await store.testAndSave(account.copyWith(name: 'Living room'), '');

    expect(testedSecrets, <String>['api-key', 'api-key']);
    expect(vault.values[account.id], 'api-key');
    expect(store.accounts.single.name, 'Living room');
  });

  test('does not persist failed connection attempts or expose secrets', () async {
    final vault = _MemoryCredentialVault();
    final store = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {
        throw StateError(
          'Could not open ${account.baseUri}?api_key=$secret',
        );
      },
    );
    await store.load();
    final account = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.jellyfin,
      name: 'Private server',
      baseUrl: 'https://media.example.test',
      identity: 'user-1',
      allowInsecureHttp: false,
    );

    await expectLater(
      store.testAndSave(account, 'super-secret'),
      throwsA(
        predicate<Object>((error) {
          final message = error.toString();
          return message.contains('[redacted]') &&
              !message.contains('super-secret');
        }),
      ),
    );

    expect(store.accounts, isEmpty);
    expect(store.musicProviders, isEmpty);
    expect(vault.values, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('aethertune.self_hosted_accounts.v1'), isNull);
  });

  test('caches safe artwork bytes and invalidates them with the account',
      () async {
    final vault = _MemoryCredentialVault();
    final provider = _ArtworkCatalogProvider('self-hosted-artwork');
    final factorySecrets = <String>[];
    final store = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {},
      providerFactory: (account, secret) {
        factorySecrets.add(secret);
        return provider;
      },
    );
    await store.load();
    final account = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.jellyfin,
      name: 'Artwork server',
      baseUrl: 'https://media.example.test',
      identity: 'user-1',
      allowInsecureHttp: false,
    );
    provider.providerId = account.providerId;
    await store.testAndSave(account, 'api-secret');

    final first = await store.loadArtwork(
      sourceId: account.providerId,
      artworkId: 'cover-1',
      version: 'v1',
      maxWidth: 300,
    );
    final second = await store.loadArtwork(
      sourceId: account.providerId,
      artworkId: 'cover-1',
      version: 'v1',
      maxWidth: 300,
    );

    expect(first, <int>[7, 8, 9]);
    expect(second, <int>[7, 8, 9]);
    expect(provider.artworkCalls, <String>['cover-1|v1|300']);
    expect(factorySecrets, <String>['api-secret']);
    expect(store.hasCredentialForProvider(account.providerId), isTrue);

    await store.remove(account.id);
    expect(
      await store.loadArtwork(
        sourceId: account.providerId,
        artworkId: 'cover-1',
      ),
      isNull,
    );
    expect(store.hasCredentialForProvider(account.providerId), isFalse);
  });
}

class _MemoryCredentialVault implements ProviderCredentialVault {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String accountId) async => values[accountId];

  @override
  Future<void> write(String accountId, String secret) async {
    values[accountId] = secret;
  }

  @override
  Future<void> delete(String accountId) async {
    values.remove(accountId);
  }
}

class _ArtworkCatalogProvider implements MusicCatalogProvider {
  _ArtworkCatalogProvider(this.providerId);

  String providerId;
  final List<String> artworkCalls = <String>[];

  @override
  String get id => providerId;

  @override
  String get name => 'Artwork provider';

  @override
  String get description => 'Artwork provider fixture';

  @override
  Set<MusicSourceCapability> get capabilities =>
      const <MusicSourceCapability>{MusicSourceCapability.artwork};

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
        networkDomains: <String>['media.example.test'],
        requiresUserCredentials: true,
        cachesMetadata: true,
      );

  @override
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  ) async =>
      const <MusicCatalogCollection>[];

  @override
  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  ) async =>
      MusicCatalogDetail(collection: collection);

  @override
  Future<Uint8List?> loadArtwork(
    String artworkId, {
    String? version,
    int maxWidth = 512,
  }) async {
    artworkCalls.add('$artworkId|${version ?? ''}|$maxWidth');
    return Uint8List.fromList(<int>[7, 8, 9]);
  }

  @override
  Future<List<Track>> search(String query) async => const <Track>[];

  @override
  Future<Uri?> resolveStream(Track track) async => null;
}
