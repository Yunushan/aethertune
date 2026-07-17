import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/spotify_metadata_provider.dart';
import 'package:aethertune/src/ui/spotify_saved_playlists_screen.dart';

void main() {
  testWidgets('opens and saves Spotify playlist metadata without playback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      playlistsLoader: (uri, token) async => _playlistsJson,
      playlistItemsLoader: (uri, token) async {
        expect(uri.path, '/v1/playlists/playlist-id/items');
        return _playlistItemsJson;
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(home: SpotifySavedPlaylistsScreen(provider: provider)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Signal Queue'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    await tester.tap(find.text('Signal Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Playlist Signal'), findsNWidgets(2));
    await tester.tap(
      find.byTooltip('Save loaded metadata as local playlist'),
    );
    await tester.pumpAndSettle();

    expect(library.playlists.single.name, 'Signal Queue');
    expect(library.playlists.single.trackIds, <String>[
      library.tracks.single.id,
      library.tracks.single.id,
    ]);

    expect(library.tracks.single.title, 'Playlist Signal');
    expect(library.tracks.single.isPlayable, isFalse);
  });
}

const _playlistsJson = '''
{
  "offset": 0,
  "total": 1,
  "next": null,
  "items": [{
    "id": "playlist-id",
    "name": "Signal Queue",
    "owner": {"display_name": "Mira"},
    "tracks": {"total": 1}
  }]
}
''';

const _playlistItemsJson = '''
{
  "offset": 0,
  "total": 2,
  "next": null,
  "items": [
    {
      "item": {
        "id": "playlist-track-id",
        "name": "Playlist Signal",
        "artists": [{"name": "Aether"}],
        "album": {"name": "Signals"}
      }
    },
    {
      "item": {
        "id": "playlist-track-id",
        "name": "Playlist Signal",
        "artists": [{"name": "Aether"}],
        "album": {"name": "Signals"}
      }
    }
  ]
}
''';
