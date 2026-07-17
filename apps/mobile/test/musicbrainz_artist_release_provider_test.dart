import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/musicbrainz_artist_release_provider.dart';
import 'package:aethertune/src/data/musicbrainz_metadata_provider.dart';

void main() {
  test(
    'loads dated album, EP, and single updates for exact followed artists',
    () async {
      final requests = <Uri>[];
      Map<String, String>? headers;
      final provider = MusicBrainzArtistReleaseProvider(
        limiter: _instantLimiter(),
        loader: (uri, requestHeaders) async {
          requests.add(uri);
          headers = requestHeaders;
          if (uri.path.endsWith('/artist')) {
            return '''
            {"artists":[
              {"id":"11111111-1111-1111-1111-111111111111","name":"Mira"},
              {"id":"22222222-2222-2222-2222-222222222222","name":"Mirae"}
            ]}
          ''';
          }
          return '''
          {"release-groups":[
            {"id":"33333333-3333-3333-3333-333333333333","title":"Future EP","first-release-date":"2027-01-02","primary-type":"EP"},
            {"id":"44444444-4444-4444-4444-444444444444","title":"Older Album","first-release-date":"2025-02-01","primary-type":"Album"},
            {"id":"55555555-5555-5555-5555-555555555555","title":"Compilation","first-release-date":"2026-03-01","primary-type":"Compilation"}
          ]}
        ''';
        },
      );

      final feed = await provider.loadFollowedArtistReleases(
        artistNames: <String>[' Mira ', 'mira'],
        artistLimit: 4,
        releasesPerArtist: 3,
      );

      expect(requests, hasLength(2));
      expect(requests.first.host, 'musicbrainz.org');
      expect(requests.first.path, '/ws/2/artist');
      expect(requests.first.queryParameters['limit'], '5');
      expect(requests.last.path, '/ws/2/release-group');
      expect(
        requests.last.queryParameters['artist'],
        '11111111-1111-1111-1111-111111111111',
      );
      expect(headers!['user-agent'], MusicBrainzMetadataProvider.userAgent);
      expect(headers!['accept'], 'application/json');
      expect(feed.releases.map((release) => release.title), <String>[
        'Future EP',
        'Older Album',
      ]);
      expect(feed.releases.first.artistName, 'Mira');
      expect(
        feed.releases.first.detailsUri.path,
        '/release-group/33333333-3333-3333-3333-333333333333',
      );
    },
  );

  test(
    'isolates individual artist failures and retains successful updates',
    () async {
      final provider = MusicBrainzArtistReleaseProvider(
        limiter: _instantLimiter(),
        loader: (uri, _) async {
          final query = uri.queryParameters['query'] ?? '';
          if (uri.path.endsWith('/artist') && query.contains('Ari')) {
            throw StateError('temporary failure');
          }
          if (uri.path.endsWith('/artist')) {
            return '{"artists":[{"id":"11111111-1111-1111-1111-111111111111","name":"Mira"}]}';
          }
          return '{"release-groups":[{"id":"33333333-3333-3333-3333-333333333333","title":"New single","first-release-date":"2026-03-01","primary-type":"Single"}]}';
        },
      );

      final feed = await provider.loadFollowedArtistReleases(
        artistNames: <String>['Ari', 'Mira'],
      );

      expect(feed.failedArtistCount, 1);
      expect(feed.hasCompleteFailure, isFalse);
      expect(feed.releases.single.title, 'New single');
    },
  );

  test('returns no feed when no exact MusicBrainz artist matches', () async {
    final provider = MusicBrainzArtistReleaseProvider(
      limiter: _instantLimiter(),
      loader: (_, __) async =>
          '{"artists":[{"id":"11111111-1111-1111-1111-111111111111","name":"Different"}]}',
    );

    final feed = await provider.loadFollowedArtistReleases(
      artistNames: <String>['Mira'],
    );

    expect(feed.releases, isEmpty);
    expect(feed.failedArtistCount, 0);
  });
}

MusicBrainzRequestLimiter _instantLimiter() {
  return MusicBrainzRequestLimiter(
    clock: () => DateTime.utc(2026),
    delay: (_) async {},
  );
}
