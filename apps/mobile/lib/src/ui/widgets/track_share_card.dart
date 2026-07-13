import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../domain/track.dart';
import 'track_artwork.dart';

const double trackShareCardWidth = 360;
const double trackShareCardHeight = 450;

class TrackShareCard extends StatelessWidget {
  const TrackShareCard({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: trackShareCardWidth,
      height: trackShareCardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF14161A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3B4048)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.music_note, color: Color(0xFF67D8C3)),
                  SizedBox(width: 8),
                  Text('AetherTune track', style: TextStyle(color: Color(0xFFF5F7FA), fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: TrackArtwork(
                  artworkUri: track.artworkUri,
                  providerId: track.sourceId,
                  providerArtworkId: track.providerArtworkId,
                  providerArtworkVersion: track.providerArtworkVersion,
                  size: 184,
                  borderRadius: 12,
                ),
              ),
              const SizedBox(height: 20),
              Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFF5F7FA), fontSize: 25, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFB8C0C8), fontSize: 15)),
              const Spacer(),
              Text('${track.album} · ${track.genre}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9DA7B0), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Uint8List> captureTrackShareCardPng(GlobalKey boundaryKey) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary || renderObject.debugNeedsPaint) {
    throw StateError('The track share card is not ready to capture.');
  }
  final image = await renderObject.toImage(pixelRatio: 3);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('Flutter could not encode the track share PNG.');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}
