import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/youtube_data_metadata_provider.dart';
import 'package:aethertune/src/ui/youtube_public_playlists_screen.dart';

void main() {
  testWidgets('browses and imports loaded public playlist metadata without playback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final provider = YouTubeDataMetadataProvider(
      apiKey: 'project-key',
      searchLoader: (_) async => '''
        {"items":[{"id":{"playlistId":"playlist-1"},"snippet":{"title":"Open Mix","channelTitle":"Aether Radio"}}]}
      ''',
      playlistItemsLoader: (_) async => '''
        {"pageInfo":{"totalResults":2},"items":[
          {"snippet":{"title":"Playlist Signal","channelTitle":"Aether Radio","resourceId":{"videoId":"video-1"}}},
          {"snippet":{"title":"Playlist Signal","channelTitle":"Aether Radio","resourceId":{"videoId":"video-1"}}}
        ]}
      ''',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(home: YouTubePublicPlaylistsScreen(provider: provider)),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('youtube-playlist-search')),
      'open mix',
    );
    await tester.tap(find.byTooltip('Search YouTube playlists'));
    await tester.pumpAndSettle();

    expect(find.text('Open Mix'), findsOneWidget);
    await tester.tap(find.text('Open Mix'));
    await tester.pumpAndSettle();
    expect(find.text('Playlist Signal'), findsNWidgets(2));
    expect(find.byIcon(Icons.play_arrow), findsNothing);

    await tester.tap(find.byTooltip('Save loaded metadata as local playlist'));
    await tester.pumpAndSettle();
    expect(library.tracks.single.isPlayable, isFalse);
    expect(library.playlists.single.name, 'Open Mix');
    expect(library.playlists.single.trackIds, hasLength(2));
    expect(
      library.playlists.single.trackIds.first,
      library.playlists.single.trackIds.last,
    );
  });
}
