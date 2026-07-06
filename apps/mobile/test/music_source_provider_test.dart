import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/demo_source_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';

void main() {
  test('demo provider declares capabilities and no network access', () {
    const provider = DemoSourceProvider();

    expect(
      provider.capabilities,
      <MusicSourceCapability>{MusicSourceCapability.metadataSearch},
    );
    expect(provider.disclosure.usesNetwork, isFalse);
    expect(provider.disclosure.isLocalOnly, isTrue);
    expect(provider.disclosure.networkSummary, 'No network domains declared');
  });

  test('provider privacy disclosure exposes declared network behavior', () {
    const disclosure = ProviderPrivacyDisclosure(
      networkDomains: <String>['api.example.test', 'media.example.test'],
      dataSent: <String>['search query', 'library id'],
      requiresUserCredentials: true,
      cachesMedia: true,
      supportsDownloads: true,
    );

    expect(disclosure.usesNetwork, isTrue);
    expect(disclosure.isLocalOnly, isFalse);
    expect(
      disclosure.networkSummary,
      'api.example.test, media.example.test',
    );
  });

  test('capabilities have user-facing labels', () {
    expect(MusicSourceCapability.metadataSearch.label, 'Search');
    expect(MusicSourceCapability.radioDirectory.label, 'Radio directory');
    expect(MusicSourceCapability.offlineCache.label, 'Offline cache');
    expect(MusicSourceCapability.authentication.label, 'Authentication');
  });
}
