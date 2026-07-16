import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A small, deterministic palette extracted from already-rendered artwork.
class ArtworkPalette {
  const ArtworkPalette({required this.dominant});

  final Color dominant;
}

/// Finds the most representative opaque color in RGBA pixel data.
///
/// Pixels are bucketed first so a small bright detail cannot outweigh the
/// artwork's larger color fields. The bounded sampling keeps extraction cheap
/// for high resolution cover images.
ArtworkPalette? artworkPaletteFromRgba(Uint8List bytes) {
  const maxSamples = 4096;
  const minimumAlpha = 128;
  if (bytes.length < 4) {
    return null;
  }

  final pixelCount = bytes.length ~/ 4;
  final step = math.max(1, (pixelCount / maxSamples).ceil());
  final buckets = <int, _ArtworkColorBucket>{};

  for (var pixel = 0; pixel < pixelCount; pixel += step) {
    final offset = pixel * 4;
    final alpha = bytes[offset + 3];
    if (alpha < minimumAlpha) {
      continue;
    }

    final red = bytes[offset];
    final green = bytes[offset + 1];
    final blue = bytes[offset + 2];
    final key = ((red >> 4) << 8) | ((green >> 4) << 4) | (blue >> 4);
    final bucket = buckets.putIfAbsent(key, _ArtworkColorBucket.new);
    bucket.add(red, green, blue);
  }

  _ArtworkColorBucket? dominant;
  for (final bucket in buckets.values) {
    if (dominant == null || bucket.count > dominant.count) {
      dominant = bucket;
    }
  }
  if (dominant == null) {
    return null;
  }

  return ArtworkPalette(dominant: dominant.color);
}

/// Tints a Material surface with the extracted color while preserving legible
/// foreground contrast from the existing theme.
Color artworkPaletteSurfaceColor({
  required Color fallback,
  ArtworkPalette? palette,
}) {
  final dominant = palette?.dominant;
  if (dominant == null) {
    return fallback;
  }
  return Color.alphaBlend(dominant.withValues(alpha: 0.16), fallback);
}

class _ArtworkColorBucket {
  var _red = 0;
  var _green = 0;
  var _blue = 0;
  var count = 0;

  void add(int red, int green, int blue) {
    _red += red;
    _green += green;
    _blue += blue;
    count += 1;
  }

  Color get color => Color.fromARGB(
    255,
    (_red / count).round(),
    (_green / count).round(),
    (_blue / count).round(),
  );
}
