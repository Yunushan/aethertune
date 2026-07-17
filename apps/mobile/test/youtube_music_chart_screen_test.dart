import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';
import 'package:aethertune/src/ui/youtube_music_chart_screen.dart';

void main() {
  testWidgets('pages and saves official chart metadata without playback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final cursors = <String?>[];
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      videosLoader: (uri) async {
        cursors.add(uri.queryParameters['pageToken']);
        return uri.queryParameters['pageToken'] == null
            ? _chartPage('first', 'next')
            : _chartPage('second', null);
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(home: YouTubeMusicChartScreen(provider: provider)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chart first'), findsOneWidget);
    expect(find.text('Chart second'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.text('Load more chart results (1 remaining)'), findsOneWidget);

    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();
    expect(library.tracks.single.title, 'Chart first');
    expect(library.tracks.single.isPlayable, isFalse);

    await tester.tap(find.text('Load more chart results (1 remaining)'));
    await tester.pumpAndSettle();

    expect(find.text('Chart second'), findsOneWidget);
    expect(find.text('All 2 chart results loaded.'), findsOneWidget);
    expect(cursors, <String?>[null, 'next']);
  });
}

String _chartPage(String suffix, String? nextPageToken) {
  return '''
{
  "nextPageToken": ${nextPageToken == null ? 'null' : '"$nextPageToken"'},
  "pageInfo": {"totalResults": 2},
  "items": [{
    "id": "chart-$suffix",
    "snippet": {
      "title": "Chart $suffix",
      "channelTitle": "Aether Channel"
    }
  }]
}
''';
}
