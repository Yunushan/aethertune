import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/provider_error.dart';

void main() {
  test('redacts raw, encoded, and credential query values', () {
    const secret = 'a b';
    final message = safeProviderErrorMessage(
      StateError(
        'https://example.test/search?api_key=a%20b&p=enc%3A612062'
        '&t=abcdef0123456789',
      ),
      providerName: secret,
      secrets: const <String>[secret],
    );

    expect(message, contains('[redacted]'));
    expect(message, isNot(contains(secret)));
    expect(message, isNot(contains('a%20b')));
    expect(message, isNot(contains('612062')));
    expect(message, isNot(contains('abcdef0123456789')));
  });
}
