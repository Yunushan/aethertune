import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('rejects insecure and credential-bearing lyrics search endpoints', () async {
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
  });

  test('exports and imports only the validated endpoint configuration',
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
  });
}
