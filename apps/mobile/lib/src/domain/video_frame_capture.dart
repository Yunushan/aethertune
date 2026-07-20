import 'dart:typed_data';

typedef VideoFrameCapture = Future<Uint8List?> Function();

/// Returns a non-empty PNG frame or a clear user-facing capture failure.
Future<Uint8List> captureVideoFramePng(VideoFrameCapture capture) async {
  final bytes = await capture();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('No video frame is available yet.');
  }
  return Uint8List.fromList(bytes);
}
