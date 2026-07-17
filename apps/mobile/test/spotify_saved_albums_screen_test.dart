import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/spotify_metadata_provider.dart';
import 'package:aethertune/src/ui/spotify_saved_albums_screen.dart';

void main() {
  testWidgets('opens saved album tracks and saves metadata without playback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      savedAlbumsLoader: (uri, token) async => _savedAlbumsJson,
      albumTracksLoader: (uri, token) async {
        expect(uri.path, '/v1/albums/album-id/tracks');
        return _albumTracksJson;
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(home: SpotifySavedAlbumsScreen(provider: provider)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Signal Archive'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    await tester.tap(find.text('Signal Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Album Signal'), findsOneWidget);
    await tester.tap(find.byTooltip('Save metadata to library'));
    await tester.pumpAndSettle();

    expect(library.tracks.single.title, 'Album Signal');
    expect(library.tracks.single.album, 'Signal Archive');
    expect(library.tracks.single.isPlayable, isFalse);
  });
}

const _savedAlbumsJson = '''
{
  "offset": 0,
  "total": 1,
  "next": null,
  "items": [{
    "added_at": "2026-07-17T12:00:00Z",
    "album": {
      "id": "album-id",
      "name": "Signal Archive",
      "total_tracks": 1,
      "artists": [{"name": "Aether"}]
    }
  }]
}
''';

const _albumTracksJson = '''
{
  "offset": 0,
  "total": 1,
  "next": null,
  "items": [{
    "id": "album-track-id",
    "name": "Album Signal",
    "artists": [{"name": "Aether"}]
  }]
}
''';
