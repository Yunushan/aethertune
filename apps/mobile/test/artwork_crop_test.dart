import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/artwork_crop.dart';

void main() {
  test('normalizes unsafe artwork crop values and round-trips JSON', () {
    final crop = ArtworkCrop.normalized(
      alignmentX: 4,
      alignmentY: -4,
      zoom: 8,
    );

    expect(crop.alignmentX, 1);
    expect(crop.alignmentY, -1);
    expect(crop.zoom, ArtworkCrop.maximumZoom);

    final restored = ArtworkCrop.fromJson(crop.toJson());
    expect(restored.alignmentX, 1);
    expect(restored.alignmentY, -1);
    expect(restored.zoom, ArtworkCrop.maximumZoom);
    expect(ArtworkCrop.fromJson(<String, Object>{'zoom': 0}).zoom, 1);
    expect(ArtworkCrop.fromJson(null).isCentered, isTrue);
  });
}
