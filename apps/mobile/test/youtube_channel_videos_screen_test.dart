import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';
import 'package:aethertune/src/ui/youtube_channel_videos_screen.dart';

void main() {
  testWidgets('pages and saves public channel metadata without playback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final cursors = <String?>[];
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (uri) async {
        cursors.add(uri.queryParameters['pageToken']);
        return uri.queryParameters['pageToken'] == null
            ? _channelVideoPage('Channel first', 'first', 'next')
            : _channelVideoPage('Channel second', 'second', null);
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: YouTubeChannelVideosScreen(
            provider: provider,
            channel: const YouTubeDataChannel(
              id: 'channel-1',
              title: 'Aether Radio',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Channel first'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(
      find.text('Load more public channel videos (1 remaining)'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();
    expect(library.tracks.single.title, 'Channel first');
    expect(library.tracks.single.isPlayable, isFalse);

    await tester.tap(find.text('Load more public channel videos (1 remaining)'));
    await tester.pumpAndSettle();
    expect(find.text('Channel second'), findsOneWidget);
    expect(cursors, <String?>[null, 'next']);
  });
}

String _channelVideoPage(String title, String id, String? nextPageToken) => '''
{
  "nextPageToken": ${nextPageToken == null ? 'null' : '"$nextPageToken"'},
  "pageInfo": {"totalResults": 2},
  "items": [{
    "id": {"videoId": "$id"},
    "snippet": {"title": "$title", "channelTitle": "Aether Radio"}
  }]
}
''';
