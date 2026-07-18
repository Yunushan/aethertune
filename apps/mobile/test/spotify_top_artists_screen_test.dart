import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/spotify_metadata_provider.dart';
import 'package:aethertune/src/ui/spotify_top_artists_screen.dart';

void main() {
  testWidgets('loads affinity ranges and follows a top artist locally', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final ranges = <String>[];
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      topArtistsLoader: (uri, token) async {
        ranges.add(uri.queryParameters['time_range']!);
        return '''
          {"items": [{"id": "artist", "name": "Aether"}]}
        ''';
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(home: SpotifyTopArtistsScreen(provider: provider)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aether'), findsOneWidget);
    expect(ranges, <String>['medium_term']);

    await tester.tap(find.text('1 year'));
    await tester.pumpAndSettle();
    expect(ranges, <String>['medium_term', 'long_term']);

    await tester.tap(find.byTooltip('Follow local artist'));
    await tester.pumpAndSettle();
    expect(library.isArtistFollowed('Aether'), isTrue);
    expect(find.byTooltip('Unfollow local artist'), findsOneWidget);
  });
}
