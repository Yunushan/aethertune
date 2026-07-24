import 'package:aethertune/src/data/youtube_account_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads a bounded page of account playlists with a bearer token', () async {
    Uri? requestedUri;
    String? token;
    final provider = YouTubeAccountProvider(
      accessTokenReader: () async => 'access-token',
      responseLoader: (uri, accessToken) async {
        requestedUri = uri;
        token = accessToken;
        return '''
          {"items":[{"id":"playlist-1","snippet":{"title":"My mix","channelTitle":"Mira"}}],"nextPageToken":"next"}
        ''';
      },
    );

    final page = await provider.loadMyPlaylistsPage(limit: 100);

    expect(token, 'access-token');
    expect(requestedUri!.queryParameters['mine'], 'true');
    expect(requestedUri!.queryParameters['maxResults'], '50');
    expect(page.playlists.single.id, 'playlist-1');
    expect(page.nextPageToken, 'next');
  });

  test('loads a bounded page of account subscriptions with a bearer token',
      () async {
    Uri? requestedUri;
    final provider = YouTubeAccountProvider(
      accessTokenReader: () async => 'access-token',
      responseLoader: (uri, accessToken) async {
        requestedUri = uri;
        return '''
          {"items":[{"id":"subscription-1","snippet":{"title":"Open Radio","resourceId":{"channelId":"channel-1"}}}]}
        ''';
      },
    );

    final page = await provider.loadMySubscriptionsPage(limit: 6);

    expect(requestedUri!.queryParameters['mine'], 'true');
    expect(requestedUri!.queryParameters['order'], 'alphabetical');
    expect(requestedUri!.queryParameters['maxResults'], '6');
    expect(page.channels.single.id, 'channel-1');
  });
}
