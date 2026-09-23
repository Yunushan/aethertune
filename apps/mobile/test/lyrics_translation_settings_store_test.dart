import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:aethertune/src/data/libretranslate_lyrics_translator.dart';
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
    expect(
      vault.values['lyrics-translation-api-key'],
      allOf(contains('optional-secret'), contains('translate.example.test')),
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        'aethertune.lyrics_translation.settings.v2',
      ),
      isNot(contains('optional-secret')),
    );

    final reloaded = LyricsTranslationSettingsStore(credentialVault: vault);
    await reloaded.load();
    expect(reloaded.endpoint, store.endpoint);
    expect(reloaded.targetLanguage, 'tr');
    expect(reloaded.translator, isNotNull);

    await reloaded.remove();
    expect(reloaded.isConfigured, isFalse);
    expect(vault.values['lyrics-translation-api-key'], contains('disabled'));
    expect(
      vault.values['lyrics-translation-api-key'],
      isNot(contains('optional-secret')),
    );
  });

  test(
    'rejected endpoint write cannot pair old endpoint with new key',
    () async {
      final backend = _FaultyPreferences();
      SharedPreferencesStorePlatform.instance = backend;
      final vault = _MemoryCredentialVault();
      final store = LyricsTranslationSettingsStore(credentialVault: vault);
      await store.save(
        endpoint: 'https://old.example.test',
        targetLanguage: 'tr',
        apiKey: 'old-key',
      );

      backend.rejectSettingsWrite = true;
      await expectLater(
        store.save(
          endpoint: 'https://new.example.test',
          targetLanguage: 'de',
          apiKey: 'new-key',
        ),
        throwsStateError,
      );
      expect(store.endpoint, Uri.parse('https://old.example.test'));
      expect(store.targetLanguage, 'tr');
      expect(vault.values['lyrics-translation-api-key'], contains('old-key'));
      expect(
        vault.values['lyrics-translation-api-key'],
        isNot(contains('new-key')),
      );

      Uri? translatedAt;
      String? translatedWith;
      final restored = LyricsTranslationSettingsStore(
        credentialVault: vault,
        translatorFactory: (endpoint, apiKey) {
          translatedAt = endpoint;
          translatedWith = apiKey;
          return LibreTranslateLyricsTranslator(
            baseUri: endpoint,
            apiKey: apiKey,
          );
        },
      );
      await restored.load();
      expect(restored.translator, isNotNull);
      expect(translatedAt, Uri.parse('https://old.example.test'));
      expect(translatedWith, 'old-key');
    },
  );

  test('failed credential rollback disables translation on restart', () async {
    final backend = _FaultyPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final vault = _MemoryCredentialVault();
    final store = LyricsTranslationSettingsStore(credentialVault: vault);
    await store.save(
      endpoint: 'https://old.example.test',
      targetLanguage: 'tr',
      apiKey: 'old-key',
    );
    backend.throwSettingsWrite = true;
    vault.failWriteContaining = 'old.example.test';

    await expectLater(
      store.save(
        endpoint: 'https://new.example.test',
        targetLanguage: 'de',
        apiKey: 'new-key',
      ),
      throwsStateError,
    );

    expect(store.translator, isNull);
    expect(store.loadError, isNotNull);
    final restored = LyricsTranslationSettingsStore(credentialVault: vault);
    await restored.load();
    expect(restored.translator, isNull);
    expect(restored.loadError, isNotNull);
  });

  test('mismatched stored endpoint and credential fail closed on load', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.lyrics_translation.settings.v2':
          '{"version":2,"endpoint":"https://old.example.test","targetLanguage":"tr"}',
    });
    final vault = _MemoryCredentialVault()
      ..values['lyrics-translation-api-key'] =
          'aethertune.lyrics_translation.credential.v1:{"version":1,"endpoint":"https://new.example.test","apiKey":"new-key"}';
    final store = LyricsTranslationSettingsStore(credentialVault: vault);

    await store.load();

    expect(store.endpoint, isNull);
    expect(store.translator, isNull);
    expect(store.loadError, isNotNull);
  });

  test('rejected removal leaves a fail-closed vault marker', () async {
    final backend = _FaultyPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final vault = _MemoryCredentialVault();
    final store = LyricsTranslationSettingsStore(credentialVault: vault);
    await store.save(
      endpoint: 'https://old.example.test',
      targetLanguage: 'tr',
      apiKey: 'old-key',
    );
    backend.rejectSettingsWrite = true;

    await expectLater(store.remove(), throwsStateError);

    expect(store.translator, isNull);
    expect(vault.values['lyrics-translation-api-key'], contains('disabled'));
    expect(
      vault.values['lyrics-translation-api-key'],
      isNot(contains('old-key')),
    );
    final restored = LyricsTranslationSettingsStore(credentialVault: vault);
    await restored.load();
    expect(restored.translator, isNull);
  });

  test(
    'legacy settings load, and rejected legacy removal stays disabled',
    () async {
      final backend = _FaultyPreferences();
      SharedPreferencesStorePlatform.instance = backend;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'aethertune.lyrics_translation.endpoint.v1',
        'https://old.example.test',
      );
      await preferences.setString(
        'aethertune.lyrics_translation.target_language.v1',
        'tr',
      );
      final vault = _MemoryCredentialVault()
        ..values['lyrics-translation-api-key'] = 'legacy-key';
      final store = LyricsTranslationSettingsStore(credentialVault: vault);
      await store.load();
      expect(store.endpoint, Uri.parse('https://old.example.test'));
      expect(store.targetLanguage, 'tr');
      backend.rejectLegacyRemoval = true;

      await expectLater(store.remove(), throwsStateError);

      expect(store.translator, isNull);
      final restored = LyricsTranslationSettingsStore(credentialVault: vault);
      await restored.load();
      expect(restored.translator, isNull);
      expect(
        vault.values['lyrics-translation-api-key'],
        isNot(contains('legacy-key')),
      );
    },
  );

  test(
    'rejects invalid translation settings and reports unavailable vaults',
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
    },
  );
}

final class _MemoryCredentialVault implements ProviderCredentialVault {
  final Map<String, String> values = <String, String>{};
  String? failWriteContaining;

  @override
  Future<void> delete(String accountId) async {
    values.remove(accountId);
  }

  @override
  Future<String?> read(String accountId) async => values[accountId];

  @override
  Future<void> write(String accountId, String secret) async {
    final blocked = failWriteContaining;
    if (blocked != null && secret.contains(blocked)) {
      throw StateError('Credential write failed.');
    }
    values[accountId] = secret;
  }
}

final class _FaultyPreferences extends InMemorySharedPreferencesStore {
  _FaultyPreferences() : super.empty();

  bool rejectSettingsWrite = false;
  bool throwSettingsWrite = false;
  bool rejectLegacyRemoval = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('aethertune.lyrics_translation.settings.v2')) {
      if (rejectSettingsWrite) {
        return false;
      }
      if (throwSettingsWrite) {
        throw StateError('Settings write failed.');
      }
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (rejectLegacyRemoval &&
        key.endsWith('aethertune.lyrics_translation.endpoint.v1')) {
      return false;
    }
    return super.remove(key);
  }
}

final class _FailingCredentialVault implements ProviderCredentialVault {
  @override
  Future<void> delete(String accountId) async =>
      throw StateError('unavailable');

  @override
  Future<String?> read(String accountId) async =>
      throw StateError('unavailable');

  @override
  Future<void> write(String accountId, String secret) async =>
      throw StateError('unavailable');
}
