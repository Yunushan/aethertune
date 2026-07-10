import 'dart:io';
import 'dart:typed_data';

import 'provider_error.dart';

typedef ProviderBinaryRequestLoader = Future<Uint8List> Function(
  Uri requestUri,
  Map<String, String> headers,
);

const maxProviderArtworkBytes = 10 * 1024 * 1024;

Future<Uint8List> loadProviderImageBytes(
  Uri uri,
  Map<String, String> headers, {
  int maxBytes = maxProviderArtworkBytes,
}) async {
  if (maxBytes <= 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'image/*');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderRequestException(
        'Artwork request failed with HTTP ${response.statusCode}.',
      );
    }
    final contentType = response.headers.contentType;
    if (contentType == null ||
        contentType.primaryType.toLowerCase() != 'image') {
      throw const ProviderRequestException(
        'Artwork response did not contain an image.',
      );
    }

    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxBytes) {
        throw ProviderRequestException(
          'Artwork response exceeded the $maxBytes byte safety limit.',
        );
      }
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) {
      throw const ProviderRequestException('Artwork response was empty.');
    }
    return Uint8List.fromList(bytes);
  } finally {
    client.close(force: true);
  }
}
