import 'package:aethertune/src/domain/legal_video_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLegalVideoUrl', () {
    test('accepts credential-free HTTPS media and removes fragments', () {
      expect(
        parseLegalVideoUrl('https://media.example.test/video.mp4?quality=high#t=4'),
        Uri.parse('https://media.example.test/video.mp4?quality=high'),
      );
    });

    test('rejects insecure, credential-bearing, and non-network URLs', () {
      for (final value in <String>[
        '',
        'http://media.example.test/video.mp4',
        'https://token@media.example.test/video.mp4',
        'file:///video.mp4',
        'data:video/mp4;base64,AAAA',
      ]) {
        expect(parseLegalVideoUrl(value), isNull, reason: value);
      }
    });
  });

  test('localVideoUri accepts a selected file path only', () {
    expect(localVideoUri('   '), isNull);
    expect(localVideoUri(r'C:\\Music\\concert.mp4')?.scheme, 'file');
  });
}
