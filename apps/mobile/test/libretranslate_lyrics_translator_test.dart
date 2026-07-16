import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/libretranslate_lyrics_translator.dart';
import 'package:aethertune/src/domain/lyrics_translator.dart';

void main() {
  test('sends a bounded LibreTranslate request and returns translated text',
      () async {
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    Map<String, Object?>? requestedBody;
    final translator = LibreTranslateLyricsTranslator(
      baseUri: Uri.parse('https://translate.example.test/api'),
      apiKey: 'secret',
      responseLoader: (uri, headers, body) async {
        requestedUri = uri;
        requestedHeaders = headers;
        requestedBody = Map<String, Object?>.from(jsonDecode(body) as Map);
        return const LyricsTranslationResponse(
          statusCode: 200,
          body: '{"translatedText":"Merhaba dunya"}',
        );
      },
    );

    final translated = await translator.translate(
      'Hello world',
      sourceLanguage: 'en',
      targetLanguage: 'tr',
    );

    expect(translated, 'Merhaba dunya');
    expect(requestedUri, Uri.parse('https://translate.example.test/api/translate'));
    expect(requestedHeaders!['content-type'], contains('application/json'));
    expect(requestedBody, <String, Object?>{
      'q': 'Hello world',
      'source': 'en',
      'target': 'tr',
      'format': 'text',
      'api_key': 'secret',
    });
  });

  test('rejects invalid endpoints, languages, responses, and oversized lyrics',
      () async {
    expect(
      () => LibreTranslateLyricsTranslator(
        baseUri: Uri.parse('ftp://translate.example.test'),
      ),
      throwsFormatException,
    );
    expect(() => normalizeTranslationLanguage('english'), throwsFormatException);

    final translator = LibreTranslateLyricsTranslator(
      baseUri: Uri.parse('https://translate.example.test'),
      responseLoader: (_, __, ___) async => const LyricsTranslationResponse(
        statusCode: 200,
        body: '{}',
      ),
    );
    await expectLater(
      translator.translate('', targetLanguage: 'en'),
      throwsFormatException,
    );
    await expectLater(
      translator.translate(
        'x' * (LibreTranslateLyricsTranslator.maxInputLength + 1),
        targetLanguage: 'en',
      ),
      throwsFormatException,
    );
    await expectLater(
      translator.translate('hello', targetLanguage: 'en'),
      throwsFormatException,
    );
  });
}
