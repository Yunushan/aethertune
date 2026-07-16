import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/lyrics_translator.dart';

class LyricsTranslationResponse {
  const LyricsTranslationResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

typedef LyricsTranslationResponseLoader =
    Future<LyricsTranslationResponse> Function(
      Uri uri,
      Map<String, String> headers,
      String body,
    );

/// Translates lyric text through a user-configured LibreTranslate endpoint.
final class LibreTranslateLyricsTranslator implements LyricsTranslator {
  LibreTranslateLyricsTranslator({
    required Uri baseUri,
    String? apiKey,
    LyricsTranslationResponseLoader? responseLoader,
  })  : baseUri = _validateBaseUri(baseUri),
        _apiKey = apiKey?.trim(),
        _responseLoader = responseLoader ?? _loadTranslationResponse;

  static const maxInputLength = 30000;
  static const userAgent =
      'AetherTune/0.1.0 (+https://github.com/Yunushan/aethertune)';

  final Uri baseUri;
  final String? _apiKey;
  final LyricsTranslationResponseLoader _responseLoader;

  @override
  Future<String> translate(
    String text, {
    required String targetLanguage,
    String sourceLanguage = 'auto',
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      throw const FormatException('Lyrics must contain text to translate.');
    }
    if (normalizedText.length > maxInputLength) {
      throw const FormatException(
        'Lyrics must be at most $maxInputLength characters to translate.',
      );
    }

    final target = normalizeTranslationLanguage(targetLanguage);
    final source = normalizeTranslationLanguage(
      sourceLanguage,
      allowAuto: true,
    );
    final payload = <String, Object?>{
      'q': normalizedText,
      'source': source,
      'target': target,
      'format': 'text',
    };
    final apiKey = _apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      payload['api_key'] = apiKey;
    }

    final response = await _responseLoader(
      _translateUri(baseUri),
      const <String, String>{
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.userAgentHeader: userAgent,
      },
      jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Translation service returned HTTP ${response.statusCode}.',
        uri: _translateUri(baseUri),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'Translation response must be a JSON object with translatedText.',
      );
    }
    final translated = decoded['translatedText'] as String?;
    if (translated == null || translated.trim().isEmpty) {
      throw const FormatException(
        'Translation response did not include translatedText.',
      );
    }
    return translated.trim();
  }
}

Uri _validateBaseUri(Uri value) {
  if (!value.hasScheme ||
      (value.scheme != 'https' && value.scheme != 'http') ||
      value.host.isEmpty ||
      value.userInfo.isNotEmpty ||
      value.hasFragment) {
    throw const FormatException('Use an http or https translation service URL.');
  }
  return value.replace(query: null, fragment: null);
}

Uri _translateUri(Uri baseUri) {
  final basePath = baseUri.path.endsWith('/')
      ? baseUri.path.substring(0, baseUri.path.length - 1)
      : baseUri.path;
  return baseUri.replace(path: '$basePath/translate');
}

Future<LyricsTranslationResponse> _loadTranslationResponse(
  Uri uri,
  Map<String, String> headers,
  String body,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.postUrl(uri);
    headers.forEach(request.headers.set);
    request.add(utf8.encode(body));
    final response = await request.close().timeout(const Duration(seconds: 20));
    final responseBody = await utf8.decoder.bind(response).join();
    return LyricsTranslationResponse(
      statusCode: response.statusCode,
      body: responseBody,
    );
  } finally {
    client.close(force: true);
  }
}
