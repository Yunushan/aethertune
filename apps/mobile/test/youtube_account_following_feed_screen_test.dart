import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/youtube_account_provider.dart';
import 'package:aethertune/src/ui/youtube_account_following_feed_screen.dart';

void main() {
  testWidgets('refreshes account subscriptions only after an explicit action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final requests = <Uri>[];
    final provider = YouTubeAccountProvider(
      accessTokenReader: () async => 'access-token',
      responseLoader: (uri, accessToken) async {
        requests.add(uri);
        if (uri.path.endsWith('/subscriptions')) {
          return '''
            {"items":[{"id":"subscription-1","snippet":{"title":"Orbit","resourceId":{"channelId":"channel-1"}}}]}
          ''';
        }
        return '''
          {"items":[{"id":{"videoId":"video-1"},"snippet":{"title":"Account Signal","channelTitle":"Orbit","publishedAt":"2026-07-02T00:00:00Z"}}]}
        ''';
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: YouTubeAccountFollowingFeedScreen(provider: provider),
        ),
      ),
    );
    expect(requests, isEmpty);

    await tester.tap(find.text('Refresh account subscriptions'));
    await tester.pumpAndSettle();

    expect(requests.length, 2);
    expect(find.text('Account Signal'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();
    expect(library.tracks.single.title, 'Account Signal');
    expect(library.tracks.single.isPlayable, isFalse);
  });
}
