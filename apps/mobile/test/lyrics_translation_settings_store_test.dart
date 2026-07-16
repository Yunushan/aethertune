import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/lyrics_translation_settings_store.dart';
import 'package:aethertune/src/data/provider_credential_vault.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores only the translation API key in the credential vault', () async {
    final vault = _MemoryCredentialVault();
    final store = LyricsTranslationSettingsStore(credentialVault: vault);
    await store.load();

    await store.save(
      endpoint: 'https://translate.example.test/libre',
      targetLanguage: 'tr',
      apiKey: ' optional-secret ',
    );

    expect(store.endpoint, Uri.parse('https://translate.example.test/libre'));
    expect(store.targetLanguage, 'tr');
    expect(store.isConfigured, isTrue);
    expect(vault.values['lyrics-translation-api-key'], 'optional-secret');

    final reloaded = LyricsTranslationSettingsStore(credentialVault: vault);
    await reloaded.load();
    expect(reloaded.endpoint, store.endpoint);
    expect(reloaded.targetLanguage, 'tr');
    expect(reloaded.translator, isNotNull);

    await reloaded.remove();
    expect(reloaded.isConfigured, isFalse);
    expect(vault.values, isEmpty);
  });

  test('rejects invalid translation settings and reports unavailable vaults',
      () async {
    final store = LyricsTranslationSettingsStore(
      credentialVault: _FailingCredentialVault(),
    );
    await store.load();
    expect(store.loadError, isNotNull);
    await expectLater(
      store.save(
        endpoint: 'https://translate.example.test',
        targetLanguage: 'not-a-language',
      ),
      throwsFormatException,
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
