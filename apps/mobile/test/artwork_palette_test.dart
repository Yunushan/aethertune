import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/artwork_palette.dart';

void main() {
  test('chooses the largest opaque artwork color field', () {
    final palette = artworkPaletteFromRgba(
      Uint8List.fromList(<int>[
        220, 30, 40, 255,
        220, 30, 40, 255,
        220, 30, 40, 255,
        220, 30, 40, 255,
        20, 90, 220, 255,
        20, 90, 220, 255,
      ]),
    );

    expect(palette?.dominant, const Color(0xffdc1e28));
  });

  test('ignores transparent pixels and returns no palette when none remain', () {
    expect(
      artworkPaletteFromRgba(
        Uint8List.fromList(<int>[220, 30, 40, 127, 20, 90, 220, 0]),
      ),
      isNull,
    );
  });

  test('tints the fallback surface only when artwork has a palette', () {
    const fallback = Color(0xff202124);
    expect(
      artworkPaletteSurfaceColor(fallback: fallback),
      fallback,
    );
    expect(
      artworkPaletteSurfaceColor(
        fallback: fallback,
        palette: const ArtworkPalette(dominant: Color(0xffdc1e28)),
      ),
      isNot(fallback),
    );
  });
}
