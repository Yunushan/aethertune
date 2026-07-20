import 'dart:typed_data';

import 'package:aethertune/src/domain/video_frame_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copies a non-empty native PNG screenshot', () async {
    final frame = await captureVideoFramePng(
      () async => Uint8List.fromList(<int>[137, 80, 78, 71]),
    );

    expect(frame, <int>[137, 80, 78, 71]);
  });

  test('rejects unavailable or empty screenshots', () async {
    await expectLater(
      captureVideoFramePng(() async => null),
      throwsStateError,
    );
    await expectLater(
      captureVideoFramePng(() async => Uint8List(0)),
      throwsStateError,
    );
  });
}
