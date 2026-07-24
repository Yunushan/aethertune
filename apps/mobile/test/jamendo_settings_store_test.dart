import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/jamendo_chart_cache.dart';
import 'package:aethertune/src/data/jamendo_settings_store.dart';
import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  test('stores the Jamendo client ID only in the credential vault', () async {
    final vault = _MemoryCredentialVault();
    final cache = _MemoryChartCache();
    final store = JamendoSettingsStore(
      credentialVault: vault,
      chartCache: cache,
    );

    await store.load();
    expect(store.isConfigured, isFalse);

    await store.saveClientId(' client-id ');

    expect(store.isConfigured, isTrue);
    expect(vault.values['jamendo-api-client-id'], 'client-id');
    expect(store.musicProviders.single.id, 'jamendo');

    final loadedAgain = JamendoSettingsStore(
      credentialVault: vault,
      chartCache: cache,
    );
    await loadedAgain.load();
    expect(loadedAgain.isConfigured, isTrue);

    await loadedAgain.removeClientId();
    expect(loadedAgain.isConfigured, isFalse);
    expect(vault.values, isEmpty);
    expect(cache.clearCount, 1);
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

final class _MemoryChartCache implements JamendoChartCache {
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
  }

  @override
  Future<JamendoCachedChart?> read(String key) async => null;

  @override
  Future<void> write(String key, List<Track> tracks) async {}
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
