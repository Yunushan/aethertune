import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/youtube_account_provider.dart';
import 'package:aethertune/src/data/youtube_channel_follow_store.dart';
import 'package:aethertune/src/ui/youtube_account_library_screen.dart';

void main() {
  testWidgets('browses and saves account playlist metadata without playback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final follows = YouTubeChannelFollowStore();
    await follows.load();
    addTearDown(follows.dispose);
    final provider = YouTubeAccountProvider(
      accessTokenReader: () async => 'access-token',
      responseLoader: (uri, accessToken) async {
        expect(accessToken, 'access-token');
        return switch (uri.path) {
          '/youtube/v3/playlists' => '''
            {"items":[{"id":"playlist-1","snippet":{"title":"My account mix","channelTitle":"Aether Radio"}}]}
          ''',
          '/youtube/v3/subscriptions' => '''
            {"items":[{"id":"subscription-1","snippet":{"title":"Orbit Channel","resourceId":{"channelId":"channel-1"}}}]}
          ''',
          '/youtube/v3/playlistItems' => '''
            {"items":[
              {"snippet":{"title":"Account Signal","channelTitle":"Aether Radio","resourceId":{"videoId":"video-1"}}},
              {"snippet":{"title":"Account Signal","channelTitle":"Aether Radio","resourceId":{"videoId":"video-1"}}}
            ]}
          ''',
          '/youtube/v3/search' => '''
            {"items":[{"id":{"videoId":"video-2"},"snippet":{"title":"Subscription Signal","channelTitle":"Orbit Channel"}}]}
          ''',
          _ => throw StateError('Unexpected endpoint: $uri'),
        };
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: ChangeNotifierProvider<YouTubeChannelFollowStore>.value(
          value: follows,
          child: MaterialApp(
            home: YouTubeAccountLibraryScreen(provider: provider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My account mix'), findsOneWidget);
    await tester.tap(find.text('My account mix'));
    await tester.pumpAndSettle();
    expect(find.text('Account Signal'), findsNWidgets(2));
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    await tester.tap(find.byTooltip('Save loaded metadata as local playlist'));
    await tester.pumpAndSettle();

    expect(library.tracks.single.isPlayable, isFalse);
    expect(library.playlists.single.name, 'My account mix');
    expect(library.playlists.single.trackIds, hasLength(2));
    expect(
      library.playlists.single.trackIds.first,
      library.playlists.single.trackIds.last,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscriptions'));
    await tester.pumpAndSettle();
    expect(find.text('Orbit Channel'), findsOneWidget);
    await tester.tap(find.byTooltip('Follow locally'));
    await tester.pumpAndSettle();
    expect(follows.isFollowed('channel-1'), isTrue);
    await tester.tap(find.text('Orbit Channel'));
    await tester.pumpAndSettle();
    expect(find.text('Subscription Signal'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();
    expect(library.tracks.map((track) => track.title), contains('Subscription Signal'));
  });
}
