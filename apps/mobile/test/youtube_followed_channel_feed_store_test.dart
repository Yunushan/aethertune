import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/youtube_channel_follow_store.dart';
import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';
import 'package:aethertune/src/data/youtube_followed_channel_feed_store.dart';

void main() {
  test('persists bounded public followed-channel metadata across restarts', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = YouTubeFollowedChannelFeedStore();
    await store.load();
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (_) async => _channelPage(),
    );

    await store.refresh(
      provider,
      const <YouTubeChannelFollow>[
        YouTubeChannelFollow(id: 'channel', title: 'Aether Radio'),
      ],
    );

    expect(store.items.single.track.title, 'Signal');
    expect(store.items.single.track.sourceId, 'youtube-data-metadata');
    expect(store.items.single.track.isPlayable, isFalse);
    expect(store.lastRefreshedAt, isNotNull);

    final reloaded = YouTubeFollowedChannelFeedStore();
    await reloaded.load();
    expect(reloaded.items.single.track.title, 'Signal');
    expect(reloaded.items.single.track.isPlayable, isFalse);
  });

  test('strips unsafe media and local fields from a persisted cache document', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.youtube_followed_feed.v1': jsonEncode(<String, Object?>{
        'version': 1,
        'items': <Object?>[
          <String, Object?>{
            'channelTitle': 'Aether Radio',
            'track': <String, Object?>{
              'id': 'video',
              'title': 'Signal',
              'sourceId': 'youtube-data-metadata',
              'localPath': 'C:/private/audio.mp3',
              'streamUrl': 'https://media.example.test/stream',
              'isFavorite': true,
              'rating': 5,
              'artworkUri': 'file:///private/art.png',
            },
          },
        ],
      }),
    });

    final store = YouTubeFollowedChannelFeedStore();
    await store.load();

    final track = store.items.single.track;
    expect(track.localPath, isNull);
    expect(track.streamUrl, isNull);
    expect(track.artworkUri, isNull);
    expect(track.isFavorite, isFalse);
    expect(track.rating, 0);
    expect(track.isPlayable, isFalse);
  });
}

String _channelPage() => '''
{
  "items": [{
    "id": {"videoId": "video"},
    "snippet": {
      "title": "Signal",
      "channelTitle": "Aether Radio",
      "publishedAt": "2026-07-02T00:00:00Z"
    }
  }]
}
''';
