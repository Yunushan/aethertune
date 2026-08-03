import 'package:aethertune/src/data/youtube_account_following_feed.dart';
import 'package:aethertune/src/data/youtube_account_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loads a bounded account subscription feed with isolated failures',
    () async {
      final requests = <Uri>[];
      final provider = YouTubeAccountProvider(
        accessTokenReader: () async => 'access-token',
        responseLoader: (uri, accessToken) async {
          requests.add(uri);
          if (uri.path.endsWith('/subscriptions')) {
            return '''
            {"items":[
              {"id":"subscription-1","snippet":{"title":"Orbit","resourceId":{"channelId":"channel-1"}}},
              {"id":"subscription-2","snippet":{"title":"North","resourceId":{"channelId":"channel-2"}}},
              {"id":"subscription-3","snippet":{"title":"Broken","resourceId":{"channelId":"channel-3"}}}
            ]}
          ''';
          }
          return switch (uri.queryParameters['channelId']) {
            'channel-1' => _videos('Earlier', 'shared', '2026-07-01T00:00:00Z'),
            'channel-2' => _videos('Latest', 'shared', '2026-07-02T00:00:00Z'),
            _ => throw StateError('unavailable'),
          };
        },
      );

      final feed = await loadYouTubeAccountFollowingFeed(
        provider,
        maxChannels: 2,
        limitPerChannel: 3,
      );

      expect(requests.first.path, '/youtube/v3/subscriptions');
      expect(requests.first.queryParameters['mine'], 'true');
      expect(requests.first.queryParameters['maxResults'], '2');
      expect(requests.where((uri) => uri.path.endsWith('/search')).length, 2);
      expect(
        requests
            .where((uri) => uri.path.endsWith('/search'))
            .map((uri) => uri.queryParameters['maxResults']),
        everyElement('3'),
      );
      expect(feed.requestedChannelCount, 2);
      expect(feed.failedChannelCount, 0);
      expect(feed.items.single.track.title, 'Earlier');
      expect(feed.items.single.channelTitle, 'Orbit');
    },
  );

  test(
    'keeps successful account channels when another channel fails',
    () async {
      final provider = YouTubeAccountProvider(
        accessTokenReader: () async => 'access-token',
        responseLoader: (uri, accessToken) async {
          if (uri.path.endsWith('/subscriptions')) {
            return '''
            {"items":[
              {"id":"subscription-1","snippet":{"title":"Orbit","resourceId":{"channelId":"channel-1"}}},
              {"id":"subscription-2","snippet":{"title":"Broken","resourceId":{"channelId":"channel-2"}}}
            ]}
          ''';
          }
          return uri.queryParameters['channelId'] == 'channel-1'
              ? _videos('Signal', 'signal', '2026-07-02T00:00:00Z')
              : throw StateError('unavailable');
        },
      );

      final feed = await loadYouTubeAccountFollowingFeed(provider);

      expect(feed.requestedChannelCount, 2);
      expect(feed.failedChannelCount, 1);
      expect(feed.items.single.track.title, 'Signal');
    },
  );

  test('rejects non-positive account feed limits', () async {
    final provider = YouTubeAccountProvider(
      accessTokenReader: () async => 'access-token',
    );

    await expectLater(
      loadYouTubeAccountFollowingFeed(provider, limitPerChannel: 0),
      throwsArgumentError,
    );
    await expectLater(
      loadYouTubeAccountFollowingFeed(provider, maxChannels: 0),
      throwsArgumentError,
    );
  });
}

String _videos(String title, String id, String publishedAt) =>
    '''
{
  "items": [{
    "id": {"videoId": "$id"},
    "snippet": {
      "title": "$title",
      "channelTitle": "Account channel",
      "publishedAt": "$publishedAt"
    }
  }]
}
''';
