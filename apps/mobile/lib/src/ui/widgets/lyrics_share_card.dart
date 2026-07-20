import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../domain/artwork_crop.dart';

const double lyricsShareCardWidth = 360;
const double lyricsShareCardHeight = 450;

ImageProvider? localLyricsShareCardBackgroundImageProvider({
  required bool artworkIsUserManaged,
  required Uri? artworkUri,
}) {
  if (!artworkIsUserManaged ||
      artworkUri == null ||
      artworkUri.scheme.toLowerCase() != 'file') {
    return null;
  }
  return FileImage(File.fromUri(artworkUri));
}

class LyricsShareCard extends StatelessWidget {
  const LyricsShareCard({
    super.key,
    required this.title,
    required this.artist,
    required this.shareText,
    this.backgroundImage,
    this.artworkCrop = ArtworkCrop.centered,
  });

  final String title;
  final String artist;
  final String shareText;
  final ImageProvider? backgroundImage;
  final ArtworkCrop artworkCrop;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: lyricsShareCardWidth,
      height: lyricsShareCardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF14161A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF3B4048)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (backgroundImage != null)
                Transform.scale(
                  scale: artworkCrop.zoom,
                  alignment: Alignment(
                    artworkCrop.alignmentX,
                    artworkCrop.alignmentY,
                  ),
                  child: Image(
                    key: const Key('lyrics-share-card-artwork-background'),
                    image: backgroundImage!,
                    fit: BoxFit.cover,
                    alignment: Alignment(
                      artworkCrop.alignmentX,
                      artworkCrop.alignmentY,
                    ),
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.expand(),
                  ),
                ),
              const ColoredBox(color: Color(0xD914161A)),
              Padding(
                padding: const EdgeInsets.all(24),
                child: DefaultTextStyle(
                  style: const TextStyle(color: Color(0xFFF5F7FA)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Row(
                        children: <Widget>[
                          Icon(Icons.lyrics_outlined, color: Color(0xFF67D8C3)),
                          SizedBox(width: 8),
                          Text(
                            'AetherTune lyrics',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (artist.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFB8C0C8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Expanded(
                        child: Text(
                          shareText,
                          maxLines: 11,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFE6EAEE),
                            fontSize: 17,
                            height: 1.38,
                          ),
                        ),
                      ),
                      const Text(
                        'Shared from a private local library',
                        style: TextStyle(
                          color: Color(0xFF9DA7B0),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Uint8List> captureLyricsShareCardPng(
  GlobalKey boundaryKey, {
  double pixelRatio = 3,
}) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary || renderObject.debugNeedsPaint) {
    throw StateError('The lyrics share card is not ready to capture.');
  }
  final image = await renderObject.toImage(pixelRatio: pixelRatio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Flutter could not encode the lyrics share PNG.');
    }
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}
