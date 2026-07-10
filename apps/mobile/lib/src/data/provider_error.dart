import 'dart:convert';

final class ProviderRequestException implements Exception {
  const ProviderRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

String safeProviderErrorMessage(
  Object error, {
  required String providerName,
  Iterable<String> secrets = const <String>[],
}) {
  final detail = error.toString().trim();
  var message = '$providerName request failed: '
      '${detail.isEmpty ? 'Unknown error.' : detail}';
  for (final secret in secrets.where((value) => value.isNotEmpty)) {
    final encodedSecret = Uri.encodeQueryComponent(secret);
    final hexSecret = utf8
        .encode(secret)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    for (final candidate in <String>{secret, encodedSecret, hexSecret}) {
      if (candidate.isNotEmpty) {
        message = message.replaceAll(candidate, '[redacted]');
      }
    }
  }
  message = message.replaceAllMapped(
    RegExp(
      r'([?&](?:api_key|p|t|password|token|access_token)=)[^&\s]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[redacted]',
  );
  return message;
}
