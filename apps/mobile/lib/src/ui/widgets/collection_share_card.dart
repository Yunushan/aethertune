import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const double collectionShareCardWidth = 360;
const double collectionShareCardHeight = 450;

class CollectionShareCard extends StatelessWidget {
  const CollectionShareCard({
    super.key,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.itemCount,
    required this.totalDuration,
    required this.artwork,
  });

  final String kind;
  final String title;
  final String subtitle;
  final int itemCount;
  final Duration totalDuration;
  final Widget artwork;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: collectionShareCardWidth,
      height: collectionShareCardHeight,
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
              Row(
                children: <Widget>[
                  const Icon(Icons.auto_awesome, color: Color(0xFF67D8C3)),
                  const SizedBox(width: 8),
                  Text(
                    'AetherTune $kind',
                    style: const TextStyle(
                      color: Color(0xFFF5F7FA),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: SizedBox.square(dimension: 184, child: artwork),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF5F7FA),
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFB8C0C8), fontSize: 15),
              ),
              const Spacer(),
              Text(
                '$itemCount track(s) - ${_formatDuration(totalDuration)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF9DA7B0), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Uint8List> captureCollectionShareCardPng(GlobalKey boundaryKey) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary || renderObject.debugNeedsPaint) {
    throw StateError('The collection share card is not ready to capture.');
  }
  final image = await renderObject.toImage(pixelRatio: 3);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Flutter could not encode the collection share PNG.');
    }
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}

String _formatDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours > 0) {
    return '$hours h ${minutes.toString().padLeft(2, '0')} min';
  }
  return '$minutes min';
}
