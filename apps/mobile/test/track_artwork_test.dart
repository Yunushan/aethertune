import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/ui/widgets/track_artwork.dart';

void main() {
  testWidgets('renders data artwork and falls back without art', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              TrackArtwork(
                artworkUri: Uri.parse(
                  'data:image/png;base64,'
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA'
                  'CklEQVR4nGMAAQAABQABDQotxAAAAABJRU5ErkJggg==',
                ),
              ),
              const TrackArtwork(artworkUri: null),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsOneWidget);
  });
}
