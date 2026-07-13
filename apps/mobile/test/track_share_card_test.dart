import 'dart:ui' as ui;

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/track_share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders and captures a track share card PNG', (tester) async {
    final boundaryKey = GlobalKey();
    final track = Track(
      id: 'night-spark',
      title: 'Night Spark',
      artist: 'Orion',
      album: 'Voltage',
      genre: 'Rock',
      localPath: '/music/night-spark.mp3',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(key: boundaryKey, child: TrackShareCard(track: track)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Night Spark'), findsOneWidget);

    final capture = await tester.runAsync<List<int>>(() async {
      final bytes = await captureTrackShareCardPng(boundaryKey);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final result = <int>[frame.image.width, frame.image.height];
      frame.image.dispose();
      codec.dispose();
      return result;
    });
    expect(capture, <int>[
      (trackShareCardWidth * 3).toInt(),
      (trackShareCardHeight * 3).toInt(),
    ]);
  });
}
