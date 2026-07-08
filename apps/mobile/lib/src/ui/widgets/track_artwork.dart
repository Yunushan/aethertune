import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    required this.artworkUri,
    this.size = 44,
    this.borderRadius = 8,
    this.fallbackIcon = Icons.music_note,
    super.key,
  });

  final Uri? artworkUri;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final imageProvider = _imageProvider(artworkUri);

    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: imageProvider == null
            ? _TrackArtworkFallback(icon: fallbackIcon)
            : Image(
                image: imageProvider,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _TrackArtworkFallback(icon: fallbackIcon);
                },
              ),
      ),
    );
  }

  ImageProvider? _imageProvider(Uri? uri) {
    if (uri == null) {
      return null;
    }

    switch (uri.scheme.toLowerCase()) {
      case 'http':
      case 'https':
        return NetworkImage(uri.toString());
      case 'file':
        return FileImage(File(uri.toFilePath()));
      case 'data':
        final data = uri.data;
        if (data == null || !data.mimeType.toLowerCase().startsWith('image/')) {
          return null;
        }

        return MemoryImage(Uint8List.fromList(data.contentAsBytes()));
    }

    if (!uri.hasScheme && uri.path.trim().isNotEmpty) {
      return FileImage(File(uri.path));
    }

    return null;
  }
}

class _TrackArtworkFallback extends StatelessWidget {
  const _TrackArtworkFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.secondaryContainer,
      child: Icon(
        icon,
        color: colorScheme.onSecondaryContainer,
      ),
    );
  }
}
