import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/jamendo_settings_store.dart';
import 'package:aethertune/src/data/provider_credential_vault.dart';

void main() {
  test('stores the Jamendo client ID only in the credential vault', () async {
    final vault = _MemoryCredentialVault();
    final store = JamendoSettingsStore(credentialVault: vault);

    await store.load();
    expect(store.isConfigured, isFalse);

    await store.saveClientId(' client-id ');

    expect(store.isConfigured, isTrue);
    expect(vault.values['jamendo-api-client-id'], 'client-id');
    expect(store.musicProviders.single.id, 'jamendo');

    final loadedAgain = JamendoSettingsStore(credentialVault: vault);
    await loadedAgain.load();
    expect(loadedAgain.isConfigured, isTrue);

    await loadedAgain.removeClientId();
    expect(loadedAgain.isConfigured, isFalse);
    expect(vault.values, isEmpty);
  });

  test('reports unavailable secure storage and rejects blank client IDs',
      () async {
    final store = JamendoSettingsStore(
      credentialVault: _FailingCredentialVault(),
    );

    await store.load();
    expect(store.loadError, isNotNull);
    expect(store.isConfigured, isFalse);
    expect(
      () => store.saveClientId('  '),
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
