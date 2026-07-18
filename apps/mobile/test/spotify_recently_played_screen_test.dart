import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/spotify_metadata_provider.dart';
import 'package:aethertune/src/ui/spotify_recently_played_screen.dart';

void main() {
  testWidgets('pages and saves recently played Spotify metadata without playback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final requestedCursors = <String?>[];
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      recentlyPlayedLoader: (uri, token) async {
        requestedCursors.add(uri.queryParameters['before']);
        return uri.queryParameters['before'] == null
            ? _historyPage('first', 'cursor-one')
            : _historyPage('second', null);
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: SpotifyRecentlyPlayedScreen(provider: provider),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('History first'), findsOneWidget);
    expect(find.text('History second'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.text('Load older tracks'), findsOneWidget);

    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();
    expect(library.tracks.single.title, 'History first');
    expect(library.tracks.single.isPlayable, isFalse);

    await tester.tap(find.text('Load older tracks'));
    await tester.pumpAndSettle();

    expect(find.text('History second'), findsOneWidget);
    expect(find.text('Load older tracks'), findsNothing);
    expect(requestedCursors, <String?>[null, 'cursor-one']);
  });
}

String _historyPage(String suffix, String? before) {
  return '''
{
  "cursors": {"before": ${before == null ? 'null' : '"$before"'}},
  "items": [{
    "played_at": "2026-07-17T12:00:00Z",
    "track": {
      "id": "spotify-$suffix",
      "name": "History $suffix",
      "artists": [{"name": "Aether"}],
      "album": {"name": "Signals"}
    }
  }]
}
''';
}
