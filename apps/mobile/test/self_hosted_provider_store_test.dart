import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/data/provider_artwork_file_cache.dart';
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

  test('exports only secure account configuration without credentials', () async {
    final vault = _MemoryCredentialVault();
    final store = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {},
    );
    await store.load();
    final secureAccount = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.jellyfin,
      name: 'Home media',
      baseUrl: 'https://media.example.test',
      identity: 'user-1',
      allowInsecureHttp: false,
    );
    final insecureAccount = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.subsonic,
      name: 'LAN music',
      baseUrl: 'http://192.168.1.10:4533',
      identity: 'yunus',
      allowInsecureHttp: true,
    );
    await store.testAndSave(secureAccount, 'secure-api-key');
    await store.testAndSave(insecureAccount, 'local-password');

    final export = store.exportAccountConfiguration();

    expect(export.exportedAccountCount, 1);
    expect(export.skippedInsecureAccountCount, 1);
    expect(export.json, contains('aethertune.self_hosted_accounts'));
    expect(export.json, contains('media.example.test'));
    expect(export.json, isNot(contains('secure-api-key')));
    expect(export.json, isNot(contains('local-password')));
    expect(export.json, isNot(contains('192.168.1.10')));
  });

  test('imports secure account configuration without credentials', () async {
    final sourceVault = _MemoryCredentialVault();
    final source = SelfHostedProviderStore(
      credentialVault: sourceVault,
      connectionTester: (account, secret) async {},
    );
    await source.load();
    final account = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.subsonic,
      name: 'Home music',
      baseUrl: 'https://music.example.test/navidrome',
      identity: 'yunus',
      allowInsecureHttp: false,
    );
    await source.testAndSave(account, 'source-password');

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final destinationVault = _MemoryCredentialVault();
    final destination = SelfHostedProviderStore(
      credentialVault: destinationVault,
      connectionTester: (account, secret) async {},
    );
    await destination.load();

    final result = await destination.importAccountConfiguration(
      source.exportAccountConfiguration().json,
    );

    expect(result.importedAccountCount, 1);
    expect(result.skippedExistingAccountCount, 0);
    expect(destination.accounts.single.id, account.id);
    expect(destination.accounts.single.name, account.name);
    expect(destination.hasCredential(account.id), isFalse);
    expect(destination.musicProviders, isEmpty);
    expect(destinationVault.values, isEmpty);
  });

  test('does not overwrite existing accounts during configuration import',
      () async {
    final vault = _MemoryCredentialVault();
    final store = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {},
    );
    await store.load();
    final account = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.jellyfin,
      name: 'Media server',
      baseUrl: 'https://media.example.test',
      identity: 'user-1',
      allowInsecureHttp: false,
    );
    await store.testAndSave(account.copyWith(name: 'Local name'), 'local-key');
    final document = jsonEncode(<String, Object?>{
      'format': SelfHostedProviderStore.accountMigrationDocumentFormat,
      'version': SelfHostedProviderStore.accountMigrationDocumentVersion,
      'accounts': <Map<String, Object?>>[account.toJson()],
    });

    final result = await store.importAccountConfiguration(document);

    expect(result.importedAccountCount, 0);
    expect(result.skippedExistingAccountCount, 1);
    expect(store.accounts.single.name, 'Local name');
    expect(vault.values[account.id], 'local-key');
  });

  test('rejects malformed documents and skips insecure imported accounts',
      () async {
    final store = SelfHostedProviderStore(
      credentialVault: _MemoryCredentialVault(),
      connectionTester: (account, secret) async {},
    );
    await store.load();
    final insecure = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.subsonic,
      name: 'LAN music',
      baseUrl: 'http://192.168.1.10:4533',
      identity: 'yunus',
      allowInsecureHttp: true,
    );
    final document = jsonEncode(<String, Object?>{
      'format': SelfHostedProviderStore.accountMigrationDocumentFormat,
      'version': SelfHostedProviderStore.accountMigrationDocumentVersion,
      'accounts': <Map<String, Object?>>[insecure.toJson()],
    });

    final result = await store.importAccountConfiguration(document);

    expect(result.importedAccountCount, 0);
    expect(result.skippedInsecureAccountCount, 1);
    expect(store.accounts, isEmpty);
    await expectLater(
      store.importAccountConfiguration('{"format":"unknown"}'),
      throwsA(isA<FormatException>()),
    );
    expect(store.accounts, isEmpty);
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

  test('rotates credentials atomically and clears private artwork', () async {
    final vault = _MemoryCredentialVault();
    final testedSecrets = <String>[];
    final factorySecrets = <String>[];
    final cacheRoot = await Directory.systemTemp.createTemp(
      'aethertune-rotation-test-',
    );
    addTearDown(() async {
      if (await cacheRoot.exists()) {
        await cacheRoot.delete(recursive: true);
      }
    });
    final artworkFileCache = ProviderArtworkFileCache(
      cacheRootLoader: () async => cacheRoot,
    );
    final provider = _ArtworkCatalogProvider('rotation-provider');
    final store = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {
        testedSecrets.add(secret);
        if (secret == 'rejected-secret') {
          throw StateError('Rejected ${account.baseUri}?token=$secret');
        }
      },
      providerFactory: (account, secret) {
        factorySecrets.add(secret);
        return provider;
      },
      artworkFileCache: artworkFileCache,
    );
    await store.load();
    final account = createSelfHostedProviderAccount(
      kind: SelfHostedProviderKind.jellyfin,
      name: 'Rotation server',
      baseUrl: 'https://media.example.test',
      identity: 'user-1',
      allowInsecureHttp: false,
    );
    provider.providerId = account.providerId;
    await store.testAndSave(account, 'old-secret');
    final artworkUri = await artworkFileCache.materialize(
      sourceId: account.providerId,
      artworkId: 'cover-1',
      bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 1]),
    );
    final artworkFile = File.fromUri(artworkUri);
    final initialRevision = store.artworkRevision;

    await expectLater(
      store.rotateCredential(account.id, 'rejected-secret'),
      throwsA(
        predicate<Object>((error) {
          final message = error.toString();
          return message.contains('[redacted]') &&
              !message.contains('rejected-secret');
        }),
      ),
    );
    expect(vault.values[account.id], 'old-secret');
    expect(await artworkFile.exists(), isTrue);

    vault.failNextWriteForSecret = 'write-failure-secret';
    await expectLater(
      store.rotateCredential(account.id, 'write-failure-secret'),
      throwsA(
        predicate<Object>((error) {
          final message = error.toString();
          return message.contains('[redacted]') &&
              !message.contains('write-failure-secret');
        }),
      ),
    );
    expect(vault.values[account.id], 'old-secret');
    expect(await artworkFile.exists(), isTrue);

    await store.rotateCredential(account.id, 'new-secret');

    expect(vault.values[account.id], 'new-secret');
    expect(store.artworkRevision, greaterThan(initialRevision));
    expect(await artworkFile.exists(), isFalse);
    expect(store.catalogProviderFor(account.id), same(provider));
    expect(factorySecrets.last, 'new-secret');
    expect(testedSecrets, <String>[
      'old-secret',
      'rejected-secret',
      'write-failure-secret',
      'new-secret',
    ]);
    await expectLater(
      store.rotateCredential(account.id, 'new-secret'),
      throwsA(isA<FormatException>()),
    );
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
    final cacheRoot = await Directory.systemTemp.createTemp(
      'aethertune-provider-store-artwork-',
    );
    addTearDown(() async {
      if (await cacheRoot.exists()) {
        await cacheRoot.delete(recursive: true);
      }
    });
    final store = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {},
      providerFactory: (account, secret) {
        factorySecrets.add(secret);
        return provider;
      },
      artworkFileCache: ProviderArtworkFileCache(
        cacheRootLoader: () async => cacheRoot,
      ),
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

    final resolved = await store.resolveTrack(
      Track(
        id: 'remote-track',
        title: 'Remote track',
        sourceId: account.providerId,
        externalId: 'song-1',
        providerArtworkId: 'cover-1',
        providerArtworkVersion: 'v1',
      ),
    );
    expect(resolved.streamUrl, 'https://media.example.test/stream/song-1');
    expect(resolved.streamUrlIsEphemeral, isTrue);
    expect(resolved.artworkUri?.scheme, 'file');
    expect(resolved.artworkUriIsEphemeral, isTrue);
    expect(await File.fromUri(resolved.artworkUri!).exists(), isTrue);
    expect(resolved.toJson()['artworkUri'], isNull);
    expect(resolved.toJson()['providerArtworkId'], 'cover-1');
    expect(provider.artworkCalls, <String>[
      'cover-1|v1|300',
      'cover-1|v1|512',
    ]);
    expect(factorySecrets, <String>['api-secret', 'api-secret', 'api-secret']);
    final resolvedArtworkFile = File.fromUri(resolved.artworkUri!);

    provider.failArtwork = true;
    final resolvedWithoutArtwork = await store.resolveTrack(
      Track(
        id: 'remote-track-with-broken-art',
        title: 'Remote track with broken art',
        sourceId: account.providerId,
        externalId: 'song-2',
        providerArtworkId: 'broken-cover',
      ),
    );
    expect(
      resolvedWithoutArtwork.streamUrl,
      'https://media.example.test/stream/song-2',
    );
    expect(resolvedWithoutArtwork.artworkUri, isNull);
    expect(factorySecrets, hasLength(5));
    expect(factorySecrets.every((secret) => secret == 'api-secret'), isTrue);

    await store.remove(account.id);
    expect(await resolvedArtworkFile.exists(), isFalse);
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
  String? failNextWriteForSecret;

  @override
  Future<String?> read(String accountId) async => values[accountId];

  @override
  Future<void> write(String accountId, String secret) async {
    values[accountId] = secret;
    if (failNextWriteForSecret == secret) {
      failNextWriteForSecret = null;
      throw StateError('Could not store $secret.');
    }
  }

  @override
  Future<void> delete(String accountId) async {
    values.remove(accountId);
  }
}

class _ArtworkCatalogProvider implements MusicCatalogProvider {
  _ArtworkCatalogProvider(this.providerId);

  String providerId;
  bool failArtwork = false;
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
    if (failArtwork) {
      throw StateError('Artwork is unavailable.');
    }
    return Uint8List.fromList(<int>[7, 8, 9]);
  }

  @override
  Future<List<Track>> search(String query) async => const <Track>[];

  @override
  Future<Uri?> resolveStream(Track track) async {
    return Uri.parse(
      'https://media.example.test/stream/${track.externalId}',
    );
  }
}
