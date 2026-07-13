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

    final bytes = await tester.runAsync(() => captureTrackShareCardPng(boundaryKey));
    final codec = await ui.instantiateImageCodec(bytes!);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, (trackShareCardWidth * 3).toInt());
    expect(frame.image.height, (trackShareCardHeight * 3).toInt());
    frame.image.dispose();
    codec.dispose();
  });
}
