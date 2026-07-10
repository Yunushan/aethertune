import 'dart:convert';

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

  testWidgets('loads authenticated provider artwork as memory bytes', (
    tester,
  ) async {
    var calls = 0;
    int? requestedWidth;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackArtwork(
            artworkUri: null,
            providerId: 'self-hosted-provider',
            providerArtworkId: 'cover-1',
            providerArtworkVersion: 'v1',
            size: 80,
            loadProviderArtwork: (maxWidth) async {
              calls += 1;
              requestedWidth = maxWidth;
              return base64Decode(_tinyPngBase64);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(calls, 1);
    expect(requestedWidth, greaterThanOrEqualTo(80));

    await tester.pump();
    expect(calls, 1);
  });
}

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAA'
    'CklEQVR4nGMAAQAABQABDQotxAAAAABJRU5ErkJggg==';
