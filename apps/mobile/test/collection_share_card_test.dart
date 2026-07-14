import 'dart:ui' as ui;

import 'package:aethertune/src/ui/widgets/collection_share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders and captures a collection share card PNG', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: const CollectionShareCard(
              kind: 'playlist',
              title: 'Night Drive',
              subtitle: 'Electronic essentials',
              itemCount: 12,
              totalDuration: Duration(minutes: 42),
              artwork: ColoredBox(
                color: Color(0xFF67D8C3),
                child: Center(child: Icon(Icons.queue_music)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Night Drive'), findsOneWidget);
    expect(find.text('12 track(s) - 42 min'), findsOneWidget);

    final capture = await tester.runAsync<List<int>>(() async {
      final bytes = await captureCollectionShareCardPng(boundaryKey);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final result = <int>[frame.image.width, frame.image.height];
      frame.image.dispose();
      codec.dispose();
      return result;
    });
    expect(capture, <int>[
      (collectionShareCardWidth * 3).toInt(),
      (collectionShareCardHeight * 3).toInt(),
    ]);
  });
}
