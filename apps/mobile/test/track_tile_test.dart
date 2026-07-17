import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/track_tile.dart';

void main() {
  testWidgets('shows and invokes the optional artwork action', (tester) async {
    var artworkEdits = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackTile(
            track: Track(id: 'local', title: 'Local track'),
            onPlay: () {},
            onFavorite: () {},
            onAddToPlaylist: () {},
            onLyrics: () {},
            onEditMetadata: () {},
            onEditArtwork: () => artworkEdits += 1,
            onRemove: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Artwork'), findsOneWidget);

    await tester.tap(find.text('Artwork'));
    await tester.pumpAndSettle();

    expect(artworkEdits, 1);
  });

  testWidgets('offers Play Next and Add to queue from the track menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackTile(
            track: Track(id: 'night-drive', title: 'Night Drive'),
            onPlay: () {},
            onFavorite: () {},
            onAddToPlaylist: () {},
            onLyrics: () {},
            onEditMetadata: () {},
            onRemove: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
  });
}
