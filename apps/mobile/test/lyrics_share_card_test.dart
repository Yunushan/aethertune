import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/ui/widgets/lyrics_share_card.dart';

void main() {
  test('accepts only explicit user-managed local files as card backgrounds', () {
    expect(
      localLyricsShareCardBackgroundImageProvider(
        artworkIsUserManaged: true,
        artworkUri: Uri.file('/music/cover.png'),
      ),
      isA<FileImage>(),
    );
    expect(
      localLyricsShareCardBackgroundImageProvider(
        artworkIsUserManaged: false,
        artworkUri: Uri.file('/music/cover.png'),
      ),
      isNull,
    );
    expect(
      localLyricsShareCardBackgroundImageProvider(
        artworkIsUserManaged: true,
        artworkUri: Uri.parse('https://example.test/cover.png'),
      ),
      isNull,
    );
    expect(
      localLyricsShareCardBackgroundImageProvider(
        artworkIsUserManaged: true,
        artworkUri: Uri.parse('data:image/png;base64,AA=='),
      ),
      isNull,
    );
  });

  testWidgets('renders a fixed-size bounded lyrics share card', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LyricsShareCard(
            title: 'A title that fits into the lyric card',
            artist: 'Artist',
            shareText: 'One lyric line\nTwo lyric line\nThree lyric line',
          ),
        ),
      ),
    );

    expect(find.text('AetherTune lyrics'), findsOneWidget);
    expect(find.text('Artist'), findsOneWidget);
    expect(tester.getSize(find.byType(LyricsShareCard)), const Size(360, 450));
  });

  testWidgets('renders an opted-in artwork background behind the share card', (
    tester,
  ) async {
    final artwork = MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADElEQVR42mNk+M/wHwAF/gL+qv48AAAAAElFTkSuQmCC',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LyricsShareCard(
            title: 'Signal',
            artist: 'Mira',
            shareText: 'A line worth sharing',
            backgroundImage: artwork,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('lyrics-share-card-artwork-background')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
