import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';

void main() {
  test('searches official video metadata without exposing a playable URI',
      () async {
    Uri? capturedUri;
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (uri) async {
        capturedUri = uri;
        return _searchJson;
      },
    );

    expect(
      provider.capabilities,
      const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.searchSuggestions,
        MusicSourceCapability.artwork,
      },
    );
    expect(provider.disclosure.cachesMedia, isFalse);
    expect(provider.disclosure.supportsDownloads, isFalse);

    final page = await provider.searchPage('  Aether song  ', limit: 75);

    expect(capturedUri!.host, 'www.googleapis.com');
    expect(capturedUri!.path, '/youtube/v3/search');
    expect(capturedUri!.queryParameters, <String, String>{
      'part': 'snippet',
      'type': 'video',
      'q': 'Aether song',
      'maxResults': '50',
      'key': 'project-key',
    });
    expect(page.totalCount, 87);
    expect(page.nextCursor, 'next-page');
    expect(page.tracks, hasLength(1));
    final track = page.tracks.single;
    expect(track.title, 'Aether Session');
    expect(track.artist, 'Aether Channel');
    expect(track.album, 'YouTube');
    expect(track.externalId, 'video-1');
    expect(track.artworkUri, Uri.parse('https://i.ytimg.com/high.jpg'));
    expect(track.isPlayable, isFalse);
    expect(await provider.resolveStream(track), isNull);
  });

  test('passes page tokens, skips malformed entries, and avoids empty queries',
      () async {
    final requests = <Uri>[];
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (uri) async {
        requests.add(uri);
        return '''
          {
            "items": [
              {"id": {"videoId": "valid"}, "snippet": {"title": "Valid", "thumbnails": {"default": {"url": "http://not-secure.example/image.jpg"}}}},
              {"id": {"channelId": "not-a-video"}, "snippet": {"title": "Skip"}}
            ]
          }
        ''';
      },
    );

    expect((await provider.searchPage('')).tracks, isEmpty);
    expect(requests, isEmpty);

    final page = await provider.searchPage('test', cursor: 'token', limit: 1);
    expect(requests.single.queryParameters['pageToken'], 'token');
    expect(page.tracks.single.title, 'Valid');
    expect(page.tracks.single.artworkUri, isNull);
  });

  test('loads paginated official music-chart metadata without a stream',
      () async {
    Uri? capturedUri;
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      videosLoader: (uri) async {
        capturedUri = uri;
        return '''
          {
            "nextPageToken": "chart-next",
            "pageInfo": {"totalResults": 2},
            "items": [{
              "id": "chart-video",
              "snippet": {
                "title": "Chart Signal",
                "channelTitle": "Aether Channel",
                "thumbnails": {"medium": {"url": "https://i.ytimg.com/chart.jpg"}}
              }
            }]
          }
        ''';
      },
    );

    final page = await provider.loadPopularMusicPage(
      regionCode: ' tr ',
      cursor: 'chart-cursor',
      limit: 100,
    );

    expect(capturedUri!.path, '/youtube/v3/videos');
    expect(capturedUri!.queryParameters, <String, String>{
      'part': 'snippet',
      'chart': 'mostPopular',
      'videoCategoryId': '10',
      'regionCode': 'TR',
      'maxResults': '50',
      'key': 'project-key',
      'pageToken': 'chart-cursor',
    });
    expect(page.nextPageToken, 'chart-next');
    expect(page.totalResults, 2);
    expect(page.tracks.single.title, 'Chart Signal');
    expect(page.tracks.single.externalId, 'chart-video');
    expect(page.tracks.single.isPlayable, isFalse);
    expect(await provider.resolveStream(page.tracks.single), isNull);
    await expectLater(
      provider.loadPopularMusicPage(regionCode: 'invalid'),
      throwsArgumentError,
    );
  });

  test('rejects unusable configuration and malformed API responses', () async {
    expect(() => YouTubeDataMetadataProvider(apiKey: ' '), throwsArgumentError);
    expect(
      () => parseYouTubeDataSearchPage('[]'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseYouTubeDataPopularPage('[]'),
      throwsA(isA<FormatException>()),
    );
  });

  test('returns bounded official video metadata suggestions', () async {
    final requests = <Uri>[];
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (uri) async {
        requests.add(uri);
        return '''
          {"items": [
            {"id":{"videoId":"one"},"snippet":{"title":"Aether Session","channelTitle":"Aether Channel"}},
            {"id":{"videoId":"two"},"snippet":{"title":"Aether Session","channelTitle":"Other Channel"}},
            {"id":{"videoId":"three"},"snippet":{"title":"Beyond","channelTitle":"Orbit"}}
          ]}
        ''';
      },
    );

    final suggestions = await provider.suggest('  aether  ', limit: 99);

    expect(requests.single.queryParameters, <String, String>{
      'part': 'snippet',
      'type': 'video',
      'q': 'aether',
      'maxResults': '10',
      'key': 'project-key',
    });
    expect(suggestions, hasLength(2));
    expect(suggestions.first.value, 'Aether Session');
    expect(suggestions.first.kind, MusicSourceSearchSuggestionKind.track);
    expect(suggestions.first.subtitle, 'Aether Channel');
    expect(suggestions.last.value, 'Beyond');
    expect(await provider.suggest('  '), isEmpty);
    expect(requests, hasLength(1));
    await expectLater(provider.suggest('aether', limit: 0), throwsArgumentError);
  });

  test('searches and pages public channel metadata only', () async {
    final requests = <Uri>[];
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (uri) async {
        requests.add(uri);
        return uri.queryParameters['pageToken'] == null
            ? '''
              {"nextPageToken":"next","pageInfo":{"totalResults":2},"items":[
                {"id":{"channelId":"channel-1"},"snippet":{"title":"Aether Radio","description":"Open sessions","thumbnails":{"high":{"url":"https://i.ytimg.com/channel-1.jpg"}}}},
                {"id":{"videoId":"not-a-channel"},"snippet":{"title":"Skip"}}
              ]}
            '''
            : '''
              {"pageInfo":{"totalResults":2},"items":[
                {"id":{"channelId":"channel-2"},"snippet":{"title":"Orbit","thumbnails":{"high":{"url":"http://unsafe.example/image.jpg"}}}}
              ]}
            ''';
      },
    );

    final first = await provider.searchChannelsPage('  aether  ');
    final second = await provider.searchChannelsPage('aether', cursor: 'next');

    expect(requests.first.queryParameters, <String, String>{
      'part': 'snippet',
      'type': 'channel',
      'q': 'aether',
      'maxResults': '20',
      'key': 'project-key',
    });
    expect(requests.last.queryParameters['pageToken'], 'next');
    expect(first.totalResults, 2);
    expect(first.nextPageToken, 'next');
    expect(first.channels.single.id, 'channel-1');
    expect(first.channels.single.title, 'Aether Radio');
    expect(first.channels.single.description, 'Open sessions');
    expect(
      first.channels.single.thumbnailUri,
      Uri.parse('https://i.ytimg.com/channel-1.jpg'),
    );
    expect(second.channels.single.thumbnailUri, isNull);
    expect((await provider.searchChannelsPage('  ')).channels, isEmpty);
    await expectLater(
      provider.searchChannelsPage('aether', limit: 0),
      throwsArgumentError,
    );
  });

  test('loads recent public channel video metadata without a stream', () async {
    Uri? capturedUri;
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (uri) async {
        capturedUri = uri;
        return '''
          {"nextPageToken":"channel-next","pageInfo":{"totalResults":2},"items":[
            {"id":{"videoId":"channel-video"},"snippet":{"title":"Channel Signal","channelTitle":"Aether Radio"}}
          ]}
        ''';
      },
    );

    final page = await provider.loadChannelVideosPage(
      ' channel-1 ',
      cursor: 'cursor',
      limit: 100,
    );

    expect(capturedUri!.queryParameters, <String, String>{
      'part': 'snippet',
      'type': 'video',
      'channelId': 'channel-1',
      'order': 'date',
      'maxResults': '50',
      'key': 'project-key',
      'pageToken': 'cursor',
    });
    expect(page.nextPageToken, 'channel-next');
    expect(page.totalResults, 2);
    expect(page.tracks.single.title, 'Channel Signal');
    expect(page.tracks.single.artist, 'Aether Radio');
    expect(page.tracks.single.isPlayable, isFalse);
    expect(await provider.resolveStream(page.tracks.single), isNull);
    await expectLater(provider.loadChannelVideosPage(' '), throwsArgumentError);
  });
}

const _searchJson = '''
{
  "nextPageToken": "next-page",
  "pageInfo": {"totalResults": 87},
  "items": [
    {
      "id": {"videoId": "video-1"},
      "snippet": {
        "title": "Aether Session",
        "channelTitle": "Aether Channel",
        "thumbnails": {
          "high": {"url": "https://i.ytimg.com/high.jpg"}
        }
      }
    }
  ]
}
''';
