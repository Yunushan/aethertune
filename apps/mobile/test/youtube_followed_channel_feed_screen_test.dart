import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/youtube_channel_follow_store.dart';
import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';
import 'package:aethertune/src/ui/youtube_followed_channel_feed_screen.dart';

void main() {
  testWidgets('refreshes followed public channel metadata manually and isolates failures', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    final follows = YouTubeChannelFollowStore();
    await Future.wait<void>(<Future<void>>[library.load(), follows.load()]);
    addTearDown(library.dispose);
    addTearDown(follows.dispose);
    await follows.setFollowed(
      const YouTubeDataChannel(id: 'channel-one', title: 'One'),
      true,
    );
    await follows.setFollowed(
      const YouTubeDataChannel(id: 'channel-two', title: 'Two'),
      true,
    );
    await follows.setFollowed(
      const YouTubeDataChannel(id: 'channel-three', title: 'Three'),
      true,
    );
    final requests = <String>[];
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (uri) async {
        final channelId = uri.queryParameters['channelId']!;
        requests.add(channelId);
        return switch (channelId) {
          'channel-one' => _channelPage('Earlier signal', 'one', '2026-07-01T00:00:00Z'),
          'channel-two' => throw StateError('unavailable'),
          _ => _channelPage('Latest signal', 'three', '2026-07-02T00:00:00Z'),
        };
      },
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: library),
          ChangeNotifierProvider<YouTubeChannelFollowStore>.value(
            value: follows,
          ),
        ],
        child: MaterialApp(
          home: YouTubeFollowedChannelFeedScreen(provider: provider),
        ),
      ),
    );
    expect(requests, isEmpty);

    await tester.tap(find.text('Refresh followed channels'));
    await tester.pumpAndSettle();

    expect(requests.toSet(), <String>{'channel-one', 'channel-two', 'channel-three'});
    expect(find.text('1 followed channel(s) could not refresh'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(
      tester.getTopLeft(find.text('Latest signal')).dy,
      lessThan(tester.getTopLeft(find.text('Earlier signal')).dy),
    );

    await tester.tap(find.byTooltip('Save metadata to library').first);
    await tester.pumpAndSettle();
    expect(library.tracks.single.title, 'Latest signal');
    expect(library.tracks.single.isPlayable, isFalse);
  });
}

String _channelPage(String title, String id, String publishedAt) => '''
{
  "items": [{
    "id": {"videoId": "$id"},
    "snippet": {
      "title": "$title",
      "channelTitle": "Aether Radio",
      "publishedAt": "$publishedAt"
    }
  }]
}
''';
