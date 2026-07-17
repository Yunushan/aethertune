import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/spotify_metadata_provider.dart';
import 'package:aethertune/src/ui/spotify_saved_tracks_screen.dart';

void main() {
  testWidgets('pages and saves Spotify metadata without a playback action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final requestedOffsets = <String?>[];
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      savedTracksLoader: (uri, token) async {
        requestedOffsets.add(uri.queryParameters['offset']);
        return uri.queryParameters['offset'] == '0'
            ? _savedTracksPage('first', 0, true)
            : _savedTracksPage('second', 1, false);
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(home: SpotifySavedTracksScreen(provider: provider)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved first'), findsOneWidget);
    expect(find.text('Saved second'), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.text('Load more saved tracks (1 remaining)'), findsOneWidget);

    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();
    expect(library.tracks.single.title, 'Saved first');
    expect(library.tracks.single.isPlayable, isFalse);

    await tester.tap(find.text('Load more saved tracks (1 remaining)'));
    await tester.pumpAndSettle();

    expect(find.text('Saved second'), findsOneWidget);
    expect(find.text('All 2 saved tracks loaded.'), findsOneWidget);
    expect(requestedOffsets, <String?>['0', '1']);
  });
}

String _savedTracksPage(String suffix, int offset, bool hasMore) {
  return '''
{
  "offset": $offset,
  "total": 2,
  "next": ${hasMore ? '"https://api.spotify.com/v1/me/tracks?offset=1"' : 'null'},
  "items": [{
    "added_at": "2026-07-17T12:00:00Z",
    "track": {
      "id": "spotify-$suffix",
      "name": "Saved $suffix",
      "artists": [{"name": "Aether"}],
      "album": {"name": "Signals"}
    }
  }]
}
''';
}
