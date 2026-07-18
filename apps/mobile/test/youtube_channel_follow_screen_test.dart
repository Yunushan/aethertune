import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/youtube_channel_follow_store.dart';
import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';
import 'package:aethertune/src/ui/youtube_channel_follow_screen.dart';

void main() {
  testWidgets(
    'searches, pages, and locally follows public channels without playback',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final library = LibraryStore();
      final follows = YouTubeChannelFollowStore();
      await Future.wait<void>(<Future<void>>[library.load(), follows.load()]);
      addTearDown(library.dispose);
      addTearDown(follows.dispose);
      final cursors = <String?>[];
      final provider = YouTubeDataMetadataProvider(
        apiKey: 'project-key',
        searchLoader: (uri) async {
          cursors.add(uri.queryParameters['pageToken']);
          return uri.queryParameters['pageToken'] == null
              ? _channelPage('Aether Radio', 'channel-1', 'next')
              : _channelPage('Orbit', 'channel-2', null);
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
            home: YouTubeChannelFollowScreen(provider: provider),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('youtube-channel-search')),
        'aether',
      );
      await tester.tap(find.byTooltip('Search YouTube channels'));
      await tester.pumpAndSettle();

      expect(find.text('Aether Radio'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.text('Load more channels (1 remaining)'), findsOneWidget);

      await tester.tap(find.byTooltip('Follow channel'));
      await tester.pumpAndSettle();
      expect(follows.isFollowed('channel-1'), isTrue);
      expect(find.text('Followed on this device'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('youtube-channel-follow-import')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('youtube-channel-follow-import-document')),
        jsonEncode(<String, Object?>{
          'version': 1,
          'follows': <Object?>[
            <String, Object?>{'id': 'channel-3', 'title': 'Imported channel'},
          ],
        }),
      );
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(follows.isFollowed('channel-1'), isTrue);
      expect(follows.isFollowed('channel-3'), isTrue);
      expect(find.text('Imported 1 followed channel(s).'), findsOneWidget);

      await tester.tap(find.text('Load more channels (1 remaining)'));
      await tester.pumpAndSettle();
      expect(find.text('Orbit'), findsOneWidget);
      expect(cursors, <String?>[null, 'next']);
    },
  );

  testWidgets('opens a public channel video shelf from a channel row', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    final follows = YouTubeChannelFollowStore();
    await Future.wait<void>(<Future<void>>[library.load(), follows.load()]);
    addTearDown(library.dispose);
    addTearDown(follows.dispose);
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (uri) async => uri.queryParameters['channelId'] == null
          ? _channelPage('Aether Radio', 'channel-1', null)
          : '''
              {"items":[{"id":{"videoId":"video-1"},"snippet":{"title":"Channel signal","channelTitle":"Aether Radio"}}]}
            ''',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: library),
          ChangeNotifierProvider<YouTubeChannelFollowStore>.value(
            value: follows,
          ),
        ],
        child: MaterialApp(home: YouTubeChannelFollowScreen(provider: provider)),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('youtube-channel-search')),
      'aether',
    );
    await tester.tap(find.byTooltip('Search YouTube channels'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aether Radio'));
    await tester.pumpAndSettle();
    expect(find.text('Recent public video metadata'), findsOneWidget);
    expect(find.text('Channel signal'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });
}

String _channelPage(String title, String id, String? nextPageToken) => '''
{
  "nextPageToken": ${nextPageToken == null ? 'null' : '"$nextPageToken"'},
  "pageInfo": {"totalResults": 2},
  "items": [{
    "id": {"channelId": "$id"},
    "snippet": {"title": "$title", "description": "Public channel"}
  }]
}
''';
