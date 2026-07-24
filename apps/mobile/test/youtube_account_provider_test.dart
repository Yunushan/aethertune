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

  test('loads account playlist metadata with a bounded continuation', () async {
    Uri? requestedUri;
    final provider = YouTubeAccountProvider(
      accessTokenReader: () async => 'access-token',
      responseLoader: (uri, accessToken) async {
        requestedUri = uri;
        expect(accessToken, 'access-token');
        return '''
          {"items":[{"snippet":{"resourceId":{"videoId":"video-1"},"title":"Account track","channelTitle":"Mira"}}]}
        ''';
      },
    );

    final page = await provider.loadPlaylistItemsPage(
      ' playlist-1 ',
      cursor: ' next ',
      limit: 99,
    );

    expect(requestedUri!.path, '/youtube/v3/playlistItems');
    expect(requestedUri!.queryParameters['playlistId'], 'playlist-1');
    expect(requestedUri!.queryParameters['pageToken'], 'next');
    expect(requestedUri!.queryParameters['maxResults'], '50');
    expect(page.tracks.single.externalId, 'video-1');
  });

  test('loads the newest metadata for an account subscription channel', () async {
    Uri? requestedUri;
    final provider = YouTubeAccountProvider(
      accessTokenReader: () async => 'access-token',
      responseLoader: (uri, accessToken) async {
        requestedUri = uri;
        expect(accessToken, 'access-token');
        return '''
          {"items":[{"id":{"videoId":"video-2"},"snippet":{"title":"Subscription Signal","channelTitle":"Mira"}}]}
        ''';
      },
    );

    final page = await provider.loadChannelVideosPage(
      ' channel-1 ',
      cursor: ' next ',
      limit: 99,
    );

    expect(requestedUri!.path, '/youtube/v3/search');
    expect(requestedUri!.queryParameters['channelId'], 'channel-1');
    expect(requestedUri!.queryParameters['type'], 'video');
    expect(requestedUri!.queryParameters['order'], 'date');
    expect(requestedUri!.queryParameters['pageToken'], 'next');
    expect(requestedUri!.queryParameters['maxResults'], '50');
    expect(page.videos.single.track.externalId, 'video-2');
  });
}
