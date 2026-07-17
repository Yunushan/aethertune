import 'dart:typed_data';
import 'dart:ui';

import 'package:aethertune/src/ui/platform_image_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copies valid in-memory PNG share data and presentation metadata', () {
    final bytes = Uint8List.fromList(<int>[1, 2, 3]);
    final request = PlatformImageShareRequest(
      bytes: bytes,
      fileName: 'aethertune-track.png',
      title: 'Track share',
      subject: 'AetherTune track',
      text: '  A private-path-free track caption  ',
      sharePositionOrigin: const Rect.fromLTWH(1, 2, 3, 4),
    );

    bytes[0] = 9;
    expect(request.bytes, <int>[1, 2, 3]);
    expect(request.fileName, 'aethertune-track.png');
    expect(request.text, 'A private-path-free track caption');
    expect(request.sharePositionOrigin, const Rect.fromLTWH(1, 2, 3, 4));
  });

  test('rejects empty data and unsafe PNG names', () {
    expect(
      () => PlatformImageShareRequest(
        bytes: Uint8List(0),
        fileName: 'share.png',
      ),
      throwsArgumentError,
    );
    expect(
      () => PlatformImageShareRequest(
        bytes: Uint8List.fromList(<int>[1]),
        fileName: '../share.png',
      ),
      throwsArgumentError,
    );
    expect(
      () => PlatformImageShareRequest(
        bytes: Uint8List.fromList(<int>[1]),
        fileName: 'share.jpg',
      ),
      throwsArgumentError,
    );
  });
}
