import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:aethertune/src/data/lyrics_search_endpoint_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists a credential-free HTTPS lyrics search endpoint', () async {
    final store = LyricsSearchEndpointSettingsStore();
    await store.load();

    expect(store.isConfigured, isFalse);
    await store.save('https://lyrics.example.test/api');

    expect(store.endpoint, Uri.parse('https://lyrics.example.test/api'));
    expect(store.isConfigured, isTrue);

    final restored = LyricsSearchEndpointSettingsStore();
    await restored.load();
    expect(restored.endpoint, store.endpoint);

    await restored.remove();
    expect(restored.isConfigured, isFalse);
  });

  test(
    'rejects insecure and credential-bearing lyrics search endpoints',
    () async {
      final store = LyricsSearchEndpointSettingsStore();
      await store.load();

      await expectLater(
        store.save('http://lyrics.example.test'),
        throwsFormatException,
      );
      await expectLater(
        store.save('https://person:secret@lyrics.example.test'),
        throwsFormatException,
      );
      await expectLater(
        store.save('https://lyrics.example.test/api?q=track'),
        throwsFormatException,
      );
    },
  );

  test(
    'exports and imports only the validated endpoint configuration',
    () async {
      final source = LyricsSearchEndpointSettingsStore();
      await source.load();
      await source.save('https://lyrics.example.test/api');

      final document = source.exportConfiguration();
      expect(document, <String, Object?>{
        'format': 'aethertune.lyrics_search_endpoint',
        'version': 1,
        'endpoint': 'https://lyrics.example.test/api',
      });

      final target = LyricsSearchEndpointSettingsStore();
      await target.load();
      await target.importConfiguration(document);
      expect(target.endpoint, source.endpoint);

      await expectLater(
        target.importConfiguration(<String, Object?>{
          'format': 'aethertune.lyrics_search_endpoint',
          'version': 1,
          'endpoint': 'http://lyrics.example.test',
        }),
        throwsFormatException,
      );
    },
  );

  test('rejected saves and removals keep the durable endpoint', () async {
    final backend = _FaultyEndpointPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final store = LyricsSearchEndpointSettingsStore();
    await store.save('https://old.example.test/api');

    backend.rejectWrites = true;
    await expectLater(
      store.save('https://new.example.test/api'),
      throwsStateError,
    );
    expect(store.endpoint, Uri.parse('https://old.example.test/api'));
    final afterRejectedSave = LyricsSearchEndpointSettingsStore();
    await afterRejectedSave.load();
    expect(afterRejectedSave.endpoint, store.endpoint);

    backend.rejectWrites = false;
    backend.throwWrites = true;
    await expectLater(
      store.save('https://new.example.test/api'),
      throwsStateError,
    );
    expect(store.endpoint, Uri.parse('https://old.example.test/api'));

    backend.throwWrites = false;
    backend.rejectRemoval = true;
    await expectLater(store.remove(), throwsStateError);
    expect(store.endpoint, Uri.parse('https://old.example.test/api'));
    final afterRejectedRemoval = LyricsSearchEndpointSettingsStore();
    await afterRejectedRemoval.load();
    expect(afterRejectedRemoval.endpoint, store.endpoint);

    backend.rejectRemoval = false;
    await store.remove();
    final restored = LyricsSearchEndpointSettingsStore();
    await restored.load();
    expect(restored.endpoint, isNull);
  });
}

final class _FaultyEndpointPreferences extends InMemorySharedPreferencesStore {
  _FaultyEndpointPreferences() : super.empty();

  bool rejectWrites = false;
  bool throwWrites = false;
  bool rejectRemoval = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith('aethertune.lyrics_search.endpoint.v1')) {
      if (rejectWrites) {
        return false;
      }
      if (throwWrites) {
        throw StateError('Endpoint write failed.');
      }
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (rejectRemoval && key.endsWith('aethertune.lyrics_search.endpoint.v1')) {
      return false;
    }
    return super.remove(key);
  }
}
