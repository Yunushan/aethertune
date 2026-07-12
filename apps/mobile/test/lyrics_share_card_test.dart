import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/ui/widgets/lyrics_share_card.dart';

void main() {
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
}
