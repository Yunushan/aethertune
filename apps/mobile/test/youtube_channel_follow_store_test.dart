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
}
