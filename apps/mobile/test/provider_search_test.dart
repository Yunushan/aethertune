import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/local_library_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/provider_search.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  test('fans out to searchable providers and ranks mixed results', () async {
    final coordinator = ProviderSearchCoordinator(
      <MusicSourceProvider>[
        _FakeProvider(
          id: 'first',
          name: 'First',
          tracks: <Track>[
            Track(
              id: 'artist-hit',
              title: 'Quiet Field',
              artist: 'Aether Tune',
              streamUrl: 'https://example.test/artist.mp3',
              sourceId: 'first',
            ),
          ],
        ),
        _FakeProvider(
          id: 'skip',
          name: 'Skip',
          capabilities: const <MusicSourceCapability>{},
          tracks: <Track>[
            Track(id: 'skipped', title: 'Aether Tune', sourceId: 'skip'),
          ],
        ),
        _FakeProvider(
          id: 'second',
          name: 'Second',
          tracks: <Track>[
            Track(
              id: 'title-hit',
              title: 'Aether Tune',
              artist: 'Open Artist',
              streamUrl: 'https://example.test/title.mp3',
              sourceId: 'second',
            ),
          ],
        ),
      ],
    );

    final response = await coordinator.search('aether tune');

    expect(response.query, 'aether tune');
    expect(response.errors, isEmpty);
    expect(response.results.map((result) => result.providerId), <String>[
      'second',
      'first',
    ]);
    expect(response.results.first.track.title, 'Aether Tune');
  });

  test('merges local library results with provider catalog results', () async {
    final localTrack = Track(
      id: 'local-hit',
      title: 'Aether Tune',
      artist: 'Saved Artist',
      album: 'Saved Album',
      localPath: '/music/aether-tune.mp3',
    );
    final coordinator = ProviderSearchCoordinator(
      <MusicSourceProvider>[
        LocalLibraryProvider(tracks: <Track>[localTrack]),
        _FakeProvider(
          id: 'remote',
          name: 'Remote',
          tracks: <Track>[
            Track(
              id: 'remote-hit',
              title: 'Aether Tune Live',
              artist: 'Remote Artist',
              sourceId: 'remote',
              streamUrl: 'https://stream.example.test/aether-live.mp3',
            ),
          ],
        ),
      ],
    );

    final response = await coordinator.search('aether tune');

    expect(response.errors, isEmpty);
    expect(response.results.map((result) => result.providerId), <String>[
      LocalLibraryProvider.providerId,
      'remote',
    ]);
    expect(response.results.first.providerName, 'Local Library');
    expect(response.results.first.track.id, localTrack.id);
    expect(response.results.first.track.isPlayable, isTrue);
  });

  test('captures provider failures without dropping successful results', () async {
    final coordinator = ProviderSearchCoordinator(
      <MusicSourceProvider>[
        _FakeProvider(
          id: 'ok',
          name: 'OK',
          tracks: <Track>[
            Track(
              id: 'ok-track',
              title: 'Ambient Result',
              sourceId: 'ok',
            ),
          ],
        ),
        _FakeProvider(
          id: 'fail',
          name: 'Failing Provider',
          error: StateError('network offline'),
        ),
      ],
    );

    final response = await coordinator.search('ambient');

    expect(response.results.single.providerId, 'ok');
    expect(response.hasErrors, isTrue);
    expect(response.errors.single.providerName, 'Failing Provider');
    expect(response.errors.single.message, contains('network offline'));
  });

  test('empty searches do not call providers', () async {
    final provider = _FakeProvider(
      id: 'provider',
      name: 'Provider',
      tracks: <Track>[
        Track(id: 'track', title: 'Track', sourceId: 'provider'),
      ],
    );
    final coordinator = ProviderSearchCoordinator(<MusicSourceProvider>[
      provider,
    ]);

    final response = await coordinator.search('   ');

    expect(response.results, isEmpty);
    expect(response.errors, isEmpty);
    expect(provider.searchCount, 0);
  });

  test('limits results per provider before merging', () async {
    final coordinator = ProviderSearchCoordinator(
      <MusicSourceProvider>[
        _FakeProvider(
          id: 'provider',
          name: 'Provider',
          tracks: <Track>[
            Track(id: 'one', title: 'Aether One', sourceId: 'provider'),
            Track(id: 'two', title: 'Aether Two', sourceId: 'provider'),
            Track(id: 'three', title: 'Aether Three', sourceId: 'provider'),
          ],
        ),
      ],
      maxResultsPerProvider: 2,
    );

    final response = await coordinator.search('aether');

    expect(response.results.map((result) => result.track.id), <String>[
      'one',
      'two',
    ]);
  });

  test('resolves metadata-only provider results when supported', () async {
    final track = Track(
      id: 'resolved-track',
      title: 'Resolved Track',
      sourceId: 'resolver',
    );
    final coordinator = ProviderSearchCoordinator(
      <MusicSourceProvider>[
        _FakeProvider(
          id: 'resolver',
          name: 'Resolver',
          capabilities: const <MusicSourceCapability>{
            MusicSourceCapability.metadataSearch,
            MusicSourceCapability.streamResolution,
          },
          resolvedStreamUri: Uri.parse('https://example.test/resolved.mp3'),
        ),
      ],
    );

    expect(coordinator.canResolve(track), isTrue);

    final resolved = await coordinator.resolvePlayableTrack(track);

    expect(resolved.streamUrl, 'https://example.test/resolved.mp3');
    expect(resolved.isPlayable, isTrue);
  });

  test('exposes provider offline cache and download policy decisions', () {
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
    final coordinator = ProviderSearchCoordinator(
      <MusicSourceProvider>[
        _FakeProvider(
          id: 'archive',
          name: 'Archive',
          capabilities: const <MusicSourceCapability>{
            MusicSourceCapability.metadataSearch,
            MusicSourceCapability.streamResolution,
            MusicSourceCapability.offlineCache,
            MusicSourceCapability.downloads,
          },
          disclosure: const ProviderPrivacyDisclosure(
            cachesMedia: true,
            supportsDownloads: true,
          ),
        ),
        _FakeProvider(
          id: 'radio',
          name: 'Radio',
          capabilities: const <MusicSourceCapability>{
            MusicSourceCapability.metadataSearch,
            MusicSourceCapability.streamResolution,
            MusicSourceCapability.directPlayback,
          },
        ),
      ],
    );

    expect(coordinator.canCacheOffline(archiveTrack), isTrue);
    expect(coordinator.canDownload(archiveTrack), isTrue);
    expect(coordinator.canCacheOffline(radioTrack), isFalse);
    expect(
      coordinator.offlineDecision(radioTrack, OfflineMediaAction.cache).reason,
      contains('does not declare Offline cache'),
    );
  });
}

final class _FakeProvider implements MusicSourceProvider {
  _FakeProvider({
    required this.id,
    required this.name,
    this.tracks = const <Track>[],
    this.capabilities = const <MusicSourceCapability>{
      MusicSourceCapability.metadataSearch,
    },
    this.error,
    this.resolvedStreamUri,
    this.disclosure = const ProviderPrivacyDisclosure(),
  });

  @override
  final String id;

  @override
  final String name;

  final List<Track> tracks;
  final Object? error;
  final Uri? resolvedStreamUri;
  @override
  final ProviderPrivacyDisclosure disclosure;
  int searchCount = 0;

  @override
  final Set<MusicSourceCapability> capabilities;

  @override
  String get description => name;

  @override
  Future<List<Track>> search(String query) async {
    searchCount += 1;
    final error = this.error;
    if (error != null) {
      throw error;
    }

    return tracks;
  }

  @override
  Future<Uri?> resolveStream(Track track) async => resolvedStreamUri;
}
