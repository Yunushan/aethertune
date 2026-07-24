import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/youtube_channel_follow_store.dart';
import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';

void main() {
  test('persists normalized public channel follows on this device', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.youtube_channel_follows.v1': '''
        [
          {"id":"channel-2","title":"Orbit","thumbnailUri":"http://unsafe.example/image.jpg"},
          {"id":"channel-1","title":"Aether Radio","description":"Sessions","thumbnailUri":"https://i.ytimg.com/channel-1.jpg"},
          {"id":"channel-1","title":"Duplicate"},
          {"id":"","title":"Invalid"}
        ]
      ''',
    });
    final store = YouTubeChannelFollowStore();
    await store.load();
    addTearDown(store.dispose);

    expect(
      store.follows.map((follow) => follow.id),
      <String>['channel-1', 'channel-2'],
    );
    expect(
      store.follows.first.thumbnailUri,
      Uri.parse('https://i.ytimg.com/channel-1.jpg'),
    );
    expect(store.follows.last.thumbnailUri, isNull);
    expect(store.isFollowed('channel-1'), isTrue);
    expect(
      await store.setFollowed(
        const YouTubeDataChannel(id: 'channel-3', title: 'Mira'),
        true,
      ),
      isTrue,
    );
    expect(
      await store.setFollowed(
        const YouTubeDataChannel(id: 'channel-3', title: 'Mira'),
        true,
      ),
      isFalse,
    );
    expect(
      await store.setFollowed(
        const YouTubeDataChannel(id: 'channel-1', title: 'Aether Radio'),
        false,
      ),
      isTrue,
    );

    final restored = YouTubeChannelFollowStore();
    await restored.load();
    addTearDown(restored.dispose);
    expect(
      restored.follows.map((follow) => follow.id),
      <String>['channel-3', 'channel-2'],
    );
  });

  test('exports and imports bounded public follows without account data',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = YouTubeChannelFollowStore();
    await store.load();
    addTearDown(store.dispose);
    await store.setFollowed(
      const YouTubeDataChannel(id: 'existing', title: 'Existing channel'),
      true,
    );

    final changed = await store.importFollowDocument(
      jsonEncode(<String, Object?>{
        'version': 1,
        'follows': <Object?>[
          <String, Object?>{
            'id': 'existing',
            'title': 'Updated channel',
            'description': 'Public metadata',
          },
          <String, Object?>{
            'id': 'new-channel',
            'title': 'New channel',
            'thumbnailUri': 'https://i.ytimg.com/new.jpg',
          },
        ],
      }),
    );

    expect(changed, 2);
    expect(
      store.follows.map((follow) => follow.id),
      <String>['new-channel', 'existing'],
    );
    expect(store.follows.last.title, 'Updated channel');
    final exported = jsonDecode(store.exportFollowDocument())
        as Map<String, Object?>;
    expect(exported['version'], 1);
    expect(exported['follows'], hasLength(2));
    expect(jsonEncode(exported), isNot(contains('credential')));
    expect(jsonEncode(exported), isNot(contains('playback')));

    final replaced = await store.importFollowDocument(
      jsonEncode(<String, Object?>{
        'version': 1,
        'follows': <Object?>[
          <String, Object?>{
            'id': 'only-channel',
            'title': 'Only channel',
          },
        ],
      }),
      replace: true,
    );
    expect(replaced, 3);
    expect(store.follows.map((follow) => follow.id), <String>['only-channel']);

    await expectLater(
      store.importFollowDocument('{"version":2,"follows":[]}'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.importFollowDocument('{"version":1,"follows":[{}]}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('follows account channels in one device-local update', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = YouTubeChannelFollowStore();
    await store.load();
    addTearDown(store.dispose);

    expect(
      await store.followAll(const <YouTubeDataChannel>[
        YouTubeDataChannel(id: 'channel-2', title: 'Orbit'),
        YouTubeDataChannel(id: 'channel-1', title: 'Aether'),
        YouTubeDataChannel(id: 'channel-1', title: 'Aether'),
        YouTubeDataChannel(id: '', title: 'Ignored'),
      ]),
      2,
    );
    expect(store.follows.map((follow) => follow.id), <String>[
      'channel-1',
      'channel-2',
    ]);
    expect(await store.followAll(const <YouTubeDataChannel>[]), 0);
  });
}
