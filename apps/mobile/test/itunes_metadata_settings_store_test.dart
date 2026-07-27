import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/itunes_metadata_provider.dart';
import 'package:aethertune/src/data/itunes_metadata_settings_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists a validated storefront and recreates the search provider',
      () async {
    final countries = <String>[];
    final store = ItunesMetadataSettingsStore(
      providerFactory: (country) {
        countries.add(country);
        return ItunesMetadataProvider(country: country);
      },
    );

    await store.load();
    expect(store.storefront, 'US');
    expect(store.provider.country, 'us');
    final initialProvider = store.provider;

    await store.setStorefront(' tr ');

    expect(store.storefront, 'TR');
    expect(store.provider.country, 'tr');
    expect(identical(store.provider, initialProvider), isFalse);
    expect(countries, <String>['us', 'tr']);

    final restored = ItunesMetadataSettingsStore();
    await restored.load();
    expect(restored.storefront, 'TR');
    expect(restored.musicProviders.single.id, 'itunes-metadata');
    expect((restored.musicProviders.single as ItunesMetadataProvider).country, 'tr');
  });

  test('rejects malformed storefronts without replacing a saved value',
      () async {
    final store = ItunesMetadataSettingsStore();
    await store.load();
    await store.setStorefront('DE');

    await expectLater(
      store.setStorefront('germany'),
      throwsA(isA<FormatException>()),
    );

    expect(store.storefront, 'DE');
    final restored = ItunesMetadataSettingsStore();
    await restored.load();
    expect(restored.storefront, 'DE');
  });

  test('falls back safely when persisted storefront data is malformed',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.itunes_metadata.storefront.v1': 'not-a-country',
    });
    final store = ItunesMetadataSettingsStore();

    await store.load();

    expect(store.storefront, 'US');
    expect(store.loadError, isNotNull);
  });
}
