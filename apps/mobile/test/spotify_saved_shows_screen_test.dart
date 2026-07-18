import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/spotify_metadata_provider.dart';
import 'package:aethertune/src/ui/spotify_saved_shows_screen.dart';

void main() {
  testWidgets('browses saved shows then saves selected-show metadata locally', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      savedShowsLoader: (_, _) async => _savedShowsPage,
      showEpisodesLoader: (_, _) async => _showEpisodesPage,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(home: SpotifySavedShowsScreen(provider: provider)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Signal Show'), findsOneWidget);
    expect(find.text('Aether Radio - 1 episode'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    await tester.tap(find.text('Signal Show'));
    await tester.pumpAndSettle();
    expect(find.text('Show Episode'), findsOneWidget);

    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();
    expect(library.tracks.single.title, 'Show Episode');
    expect(library.tracks.single.externalId, 'episode:show-episode');
    expect(library.tracks.single.isPlayable, isFalse);
  });
}

const _savedShowsPage = '''
{
  "offset": 0,
  "total": 1,
  "next": null,
  "items": [{
    "added_at": "2026-07-17T12:00:00Z",
    "show": {
      "id": "signal-show",
      "name": "Signal Show",
      "publisher": "Aether Radio",
      "total_episodes": 1,
      "images": [{"url": "https://i.scdn.co/image/show"}]
    }
  }]
}
''';

const _showEpisodesPage = '''
{
  "offset": 0,
  "total": 1,
  "next": null,
  "items": [{
    "id": "show-episode",
    "name": "Show Episode",
    "duration_ms": 62000,
    "images": [{"url": "https://i.scdn.co/image/episode"}]
  }]
}
''';
