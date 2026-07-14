import 'dart:math' as math;

/// A non-destructive square artwork crop expressed as normalized alignment
/// coordinates plus a viewport zoom level.
class ArtworkCrop {
  const ArtworkCrop({
    this.alignmentX = 0,
    this.alignmentY = 0,
    this.zoom = 1,
  }) : assert(alignmentX >= -1 && alignmentX <= 1),
       assert(alignmentY >= -1 && alignmentY <= 1),
       assert(zoom >= 1 && zoom <= maximumZoom);

  static const maximumZoom = 3.0;
  static const centered = ArtworkCrop();

  final double alignmentX;
  final double alignmentY;
  final double zoom;

  bool get isCentered => alignmentX == 0 && alignmentY == 0 && zoom == 1;

  ArtworkCrop copyWith({
    double? alignmentX,
    double? alignmentY,
    double? zoom,
  }) {
    return ArtworkCrop.normalized(
      alignmentX: alignmentX ?? this.alignmentX,
      alignmentY: alignmentY ?? this.alignmentY,
      zoom: zoom ?? this.zoom,
    );
  }

  factory ArtworkCrop.normalized({
    double alignmentX = 0,
    double alignmentY = 0,
    double zoom = 1,
  }) {
    return ArtworkCrop(
      alignmentX: math.max(-1.0, math.min(1.0, alignmentX)).toDouble(),
      alignmentY: math.max(-1.0, math.min(1.0, alignmentY)).toDouble(),
      zoom: math.max(1.0, math.min(maximumZoom, zoom)).toDouble(),
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'alignmentX': alignmentX,
      'alignmentY': alignmentY,
      'zoom': zoom,
    };
  }

  factory ArtworkCrop.fromJson(Object? value) {
    if (value is! Map) {
      return centered;
    }
    return ArtworkCrop.normalized(
      alignmentX: (value['alignmentX'] as num?)?.toDouble() ?? 0,
      alignmentY: (value['alignmentY'] as num?)?.toDouble() ?? 0,
      zoom: (value['zoom'] as num?)?.toDouble() ?? 1,
    );
  }
}
