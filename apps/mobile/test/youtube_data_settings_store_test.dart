import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/data/youtube_data_settings_store.dart';

void main() {
  test('stores the API key only in the credential vault', () async {
    final vault = _MemoryCredentialVault();
    final store = YouTubeDataSettingsStore(credentialVault: vault);

    await store.load();
    expect(store.isConfigured, isFalse);
    await store.saveApiKey(' project-key ');

    expect(store.isConfigured, isTrue);
    expect(vault.values['youtube-data-metadata'], 'project-key');
    expect(store.musicProviders.single.id, 'youtube-data-metadata');

    final loadedAgain = YouTubeDataSettingsStore(credentialVault: vault);
    await loadedAgain.load();
    expect(loadedAgain.isConfigured, isTrue);

    await loadedAgain.removeApiKey();
    expect(loadedAgain.isConfigured, isFalse);
    expect(vault.values, isEmpty);
  });

  test('reports unavailable secure storage and rejects blank keys', () async {
    final store = YouTubeDataSettingsStore(
      credentialVault: _FailingCredentialVault(),
    );

    await store.load();
    expect(store.loadError, isNotNull);
    expect(store.isConfigured, isFalse);
    expect(
      () => store.saveApiKey('  '),
      throwsA(isA<FormatException>()),
    );
  });
}

final class _MemoryCredentialVault implements ProviderCredentialVault {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String accountId) async {
    values.remove(accountId);
  }

  @override
  Future<String?> read(String accountId) async => values[accountId];

  @override
  Future<void> write(String accountId, String secret) async {
    values[accountId] = secret;
  }
}

final class _FailingCredentialVault implements ProviderCredentialVault {
  @override
  Future<void> delete(String accountId) async => throw StateError('unavailable');

  @override
  Future<String?> read(String accountId) async => throw StateError('unavailable');

  @override
  Future<void> write(String accountId, String secret) async =>
      throw StateError('unavailable');
}
