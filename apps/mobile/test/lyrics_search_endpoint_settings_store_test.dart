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
}
