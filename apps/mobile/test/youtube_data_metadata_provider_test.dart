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

  test('enriches submitted search metadata with official video durations',
      () async {
    Uri? detailsUri;
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      enrichSearchDurations: true,
      searchLoader: (_) async => _searchJson,
      videosLoader: (uri) async {
        detailsUri = uri;
        return '''
          {"items":[
            {"id":"video-1","contentDetails":{"duration":"PT1H2M3.5S"}},
            {"id":"skip","contentDetails":{"duration":"P1M"}}
          ]}
        ''';
      },
    );

    final page = await provider.searchPage('aether');

    expect(detailsUri!.path, '/youtube/v3/videos');
    expect(detailsUri!.queryParameters, <String, String>{
      'part': 'contentDetails',
      'id': 'video-1',
      'key': 'project-key',
    });
    expect(
      page.tracks.single.duration,
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
    );
    expect(page.tracks.single.isPlayable, isFalse);
  });

  test('keeps search rows when optional duration metadata fails', () async {
    var detailRequests = 0;
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      enrichSearchDurations: true,
      searchLoader: (_) async => _searchJson,
      videosLoader: (_) async {
        detailRequests += 1;
        throw StateError('temporary YouTube details failure');
      },
    );

    final suggestions = await provider.suggest('aether');
    final page = await provider.searchPage('aether');

    expect(suggestions, hasLength(1));
    expect(detailRequests, 1);
    expect(page.tracks.single.duration, Duration.zero);
  });

  test('parses bounded YouTube ISO 8601 durations', () {
    expect(
      parseYouTubeDataDuration('P1DT2H3M4.25S'),
      const Duration(
        days: 1,
        hours: 2,
        minutes: 3,
        seconds: 4,
        milliseconds: 250,
      ),
    );
    expect(parseYouTubeDataDuration('P1M'), isNull);
    expect(parseYouTubeDataDuration('PT'), isNull);
    expect(parseYouTubeDataDuration('P367D'), isNull);
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
              "contentDetails": {"duration": "PT3M4S"},
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
      'part': 'snippet,contentDetails',
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
    expect(page.tracks.single.duration, const Duration(minutes: 3, seconds: 4));
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
            {"id":{"videoId":"channel-video"},"snippet":{"title":"Channel Signal","channelTitle":"Aether Radio","publishedAt":"2026-07-17T12:34:56Z"}}
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
    expect(page.videos.single.publishedAt, DateTime.utc(2026, 7, 17, 12, 34, 56));
    expect(page.tracks.single.isPlayable, isFalse);
    expect(await provider.resolveStream(page.tracks.single), isNull);
    await expectLater(provider.loadChannelVideosPage(' '), throwsArgumentError);
  });

  test('searches public playlists and pages their item metadata', () async {
    Uri? searchUri;
    Uri? playlistItemsUri;
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (uri) async {
        searchUri = uri;
        return '''
          {"nextPageToken":"playlist-next","pageInfo":{"totalResults":1},"items":[
            {"id":{"playlistId":"playlist-1"},"snippet":{"title":"Open Mix","channelTitle":"Aether Radio","thumbnails":{"high":{"url":"https://i.ytimg.com/playlist.jpg"}}}}
          ]}
        ''';
      },
      playlistItemsLoader: (uri) async {
        playlistItemsUri = uri;
        return '''
          {"nextPageToken":"item-next","pageInfo":{"totalResults":1},"items":[
            {"snippet":{"title":"Playlist Signal","channelTitle":"Aether Radio","resourceId":{"videoId":"playlist-video"}}}
          ]}
        ''';
      },
    );

    final playlists = await provider.searchPlaylistsPage('  open mix  ');
    final items = await provider.loadPlaylistItemsPage(
      ' playlist-1 ',
      cursor: 'item-cursor',
      limit: 100,
    );

    expect(searchUri!.queryParameters, <String, String>{
      'part': 'snippet',
      'type': 'playlist',
      'q': 'open mix',
      'maxResults': '20',
      'key': 'project-key',
    });
    expect(playlists.nextPageToken, 'playlist-next');
    expect(playlists.playlists.single.id, 'playlist-1');
    expect(playlists.playlists.single.channelTitle, 'Aether Radio');
    expect(
      playlists.playlists.single.thumbnailUri,
      Uri.parse('https://i.ytimg.com/playlist.jpg'),
    );
    expect(playlistItemsUri!.path, '/youtube/v3/playlistItems');
    expect(playlistItemsUri!.queryParameters, <String, String>{
      'part': 'snippet',
      'playlistId': 'playlist-1',
      'maxResults': '50',
      'key': 'project-key',
      'pageToken': 'item-cursor',
    });
    expect(items.nextPageToken, 'item-next');
    expect(items.tracks.single.title, 'Playlist Signal');
    expect(items.tracks.single.artist, 'Aether Radio');
    expect(items.tracks.single.isPlayable, isFalse);
    expect(await provider.resolveStream(items.tracks.single), isNull);
    expect((await provider.searchPlaylistsPage('  ')).playlists, isEmpty);
    await expectLater(provider.loadPlaylistItemsPage(' '), throwsArgumentError);
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
