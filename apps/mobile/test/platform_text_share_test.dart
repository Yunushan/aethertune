import 'package:aethertune/src/ui/platform_text_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes share text and carries optional presentation metadata', () {
    final request = PlatformTextShareRequest(
      text: '  A private-path-free share payload  ',
      title: 'Track share',
      subject: 'AetherTune track',
    );

    expect(request.text, 'A private-path-free share payload');
    expect(request.title, 'Track share');
    expect(request.subject, 'AetherTune track');
  });

  test('rejects empty native share requests', () {
    expect(
      () => PlatformTextShareRequest(text: '  '),
      throwsArgumentError,
    );
  });
}
