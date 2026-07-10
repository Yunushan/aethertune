import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/demo_source_provider.dart';
import 'package:aethertune/src/data/internet_archive_provider.dart';
import 'package:aethertune/src/data/jellyfin_provider.dart';
import 'package:aethertune/src/data/local_library_provider.dart';
import 'package:aethertune/src/data/podcast_rss_provider.dart';
import 'package:aethertune/src/data/radio_browser_provider.dart';
import 'package:aethertune/src/data/subsonic_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/track.dart';

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
      cachesMetadata: true,
      cachesMedia: true,
      supportsDownloads: true,
    );

    expect(disclosure.usesNetwork, isTrue);
    expect(disclosure.isLocalOnly, isFalse);
    expect(disclosure.cachesMetadata, isTrue);
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
    expect(OfflineMediaAction.cache.label, 'Offline cache');
    expect(OfflineMediaAction.download.label, 'Download');
  });

  test('current providers satisfy the shared capability contract', () {
    final providers = <MusicSourceProvider>[
      const LocalLibraryProvider(),
      const DemoSourceProvider(),
      InternetArchiveProvider(
        baseUri: Uri.parse('https://archive.example.test'),
      ),
      JellyfinProvider(
        baseUri: Uri.parse('https://jellyfin.example.test'),
        userId: 'user-1',
        apiKey: 'secret',
        requestLoader: (_) async => '{"Items":[]}',
      ),
      PodcastRssProvider(
        feedUri: Uri.parse('https://podcasts.example.test/feed.xml'),
      ),
      RadioBrowserProvider(
        baseUri: Uri.parse('https://radio.example.test'),
      ),
      SubsonicProvider(
        baseUri: Uri.parse('https://music.example.test'),
        username: 'user',
        password: 'secret',
        requestLoader: (_) async =>
            '{"subsonic-response":{"status":"ok","searchResult3":{}}}',
      ),
    ];
    final ids = <String>{};

    for (final provider in providers) {
      expect(provider.id.trim(), isNotEmpty);
      expect(provider.name.trim(), isNotEmpty);
      expect(provider.description.trim(), isNotEmpty);
      expect(provider.capabilities, isNotEmpty);
      expect(ids.add(provider.id), isTrue);

      final disclosure = provider.disclosure;
      expect(
        disclosure.networkDomains.every((domain) => domain.trim().isNotEmpty),
        isTrue,
      );
      expect(
        disclosure.dataSent.every((item) => item.trim().isNotEmpty),
        isTrue,
      );

      if (disclosure.requiresUserCredentials) {
        expect(
          provider.capabilities,
          contains(MusicSourceCapability.authentication),
        );
      }
      if (disclosure.cachesMedia) {
        expect(
          provider.capabilities,
          contains(MusicSourceCapability.offlineCache),
        );
      }
      if (disclosure.supportsDownloads) {
        expect(
          provider.capabilities,
          contains(MusicSourceCapability.downloads),
        );
      }
      if (provider.capabilities.contains(MusicSourceCapability.offlineCache)) {
        expect(disclosure.cachesMedia, isTrue);
      }
      if (provider.capabilities.contains(MusicSourceCapability.downloads)) {
        expect(disclosure.supportsDownloads, isTrue);
      }
    }
  });

  test('offline media policy allows local files without a provider', () {
    const policy = OfflineMediaPolicy(<MusicSourceProvider>[]);
    final track = Track(
      id: 'local-track',
      title: 'Local Track',
      localPath: '/music/local.mp3',
    );

    final cacheDecision = policy.evaluate(track, OfflineMediaAction.cache);
    final downloadDecision = policy.evaluate(track, OfflineMediaAction.download);

    expect(cacheDecision.isAllowed, isTrue);
    expect(cacheDecision.reason, contains('already available offline'));
    expect(downloadDecision.isAllowed, isTrue);
  });

  test('offline media policy requires provider capability and disclosure', () {
    const policy = OfflineMediaPolicy(<MusicSourceProvider>[
      _PolicyProvider(
        id: 'archive',
        name: 'Archive',
        capabilities: <MusicSourceCapability>{
          MusicSourceCapability.streamResolution,
          MusicSourceCapability.offlineCache,
          MusicSourceCapability.downloads,
        },
        disclosure: ProviderPrivacyDisclosure(
          cachesMedia: true,
          supportsDownloads: true,
        ),
      ),
      _PolicyProvider(
        id: 'radio',
        name: 'Radio',
        capabilities: <MusicSourceCapability>{
          MusicSourceCapability.streamResolution,
          MusicSourceCapability.directPlayback,
        },
      ),
      _PolicyProvider(
        id: 'silent-cache',
        name: 'Silent Cache',
        capabilities: <MusicSourceCapability>{
          MusicSourceCapability.streamResolution,
          MusicSourceCapability.offlineCache,
        },
      ),
      _PolicyProvider(
        id: 'metadata-only',
        name: 'Metadata Only',
        capabilities: <MusicSourceCapability>{
          MusicSourceCapability.offlineCache,
        },
        disclosure: ProviderPrivacyDisclosure(cachesMedia: true),
      ),
    ]);

    final archiveTrack = Track(
      id: 'archive-track',
      title: 'Archive Track',
      sourceId: 'archive',
    );
    final radioTrack = Track(
      id: 'radio-track',
      title: 'Radio Track',
      streamUrl: 'https://stream.example.test/live',
      sourceId: 'radio',
    );
    final silentCacheTrack = Track(
      id: 'silent-cache-track',
      title: 'Silent Cache Track',
      sourceId: 'silent-cache',
    );
    final metadataOnlyTrack = Track(
      id: 'metadata-only-track',
      title: 'Metadata Only Track',
      sourceId: 'metadata-only',
    );
    final unknownTrack = Track(
      id: 'unknown-track',
      title: 'Unknown Track',
      sourceId: 'missing-provider',
    );

    expect(policy.canCache(archiveTrack), isTrue);
    expect(policy.canDownload(archiveTrack), isTrue);
    expect(
      policy.evaluate(archiveTrack, OfflineMediaAction.cache).providerId,
      'archive',
    );

    final radioDecision = policy.evaluate(radioTrack, OfflineMediaAction.cache);
    expect(radioDecision.isAllowed, isFalse);
    expect(radioDecision.reason, contains('does not declare Offline cache'));

    final silentCacheDecision = policy.evaluate(
      silentCacheTrack,
      OfflineMediaAction.cache,
    );
    expect(silentCacheDecision.isAllowed, isFalse);
    expect(silentCacheDecision.reason, contains('has not disclosed'));

    final metadataOnlyDecision = policy.evaluate(
      metadataOnlyTrack,
      OfflineMediaAction.cache,
    );
    expect(metadataOnlyDecision.isAllowed, isFalse);
    expect(metadataOnlyDecision.reason, contains('cannot resolve'));

    final unknownDecision = policy.evaluate(
      unknownTrack,
      OfflineMediaAction.download,
    );
    expect(unknownDecision.isAllowed, isFalse);
    expect(unknownDecision.reason, contains('No provider is registered'));
  });
}

final class _PolicyProvider implements MusicSourceProvider {
  const _PolicyProvider({
    required this.id,
    required this.name,
    required this.capabilities,
    this.disclosure = const ProviderPrivacyDisclosure(),
  });

  @override
  final String id;

  @override
  final String name;

  @override
  final Set<MusicSourceCapability> capabilities;

  @override
  final ProviderPrivacyDisclosure disclosure;

  @override
  String get description => name;

  @override
  Future<List<Track>> search(String query) async => const <Track>[];

  @override
  Future<Uri?> resolveStream(Track track) async => null;
}
