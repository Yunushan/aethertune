import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/data/self_hosted_provider_store.dart';
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

    final secondStore = SelfHostedProviderStore(
      credentialVault: vault,
      connectionTester: (account, secret) async {},
    );
    await secondStore.load();
    expect(secondStore.accounts.single.name, 'Home music');
    expect(secondStore.hasCredential(account.id), isTrue);

    final resolved = await secondStore.resolveTrack(
      Track(
        id: 'song',
        title: 'Song',
        sourceId: account.providerId,
        externalId: 'song-1',
      ),
    );
    expect(resolved.streamUrl, contains('/rest/stream.view'));
    expect(resolved.streamUrl, contains('super-secret'.codeUnits
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()));
    expect(resolved.streamUrlIsEphemeral, isTrue);
    expect(resolved.toJson()['streamUrl'], isNull);

    await secondStore.remove(account.id);
    expect(secondStore.accounts, isEmpty);
    expect(secondStore.musicProviders, isEmpty);
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
