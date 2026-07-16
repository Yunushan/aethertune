abstract interface class LyricsTranslator {
  Future<String> translate(
    String text, {
    required String targetLanguage,
    String sourceLanguage = 'auto',
  });
}

String normalizeTranslationLanguage(String value, {bool allowAuto = false}) {
  final normalized = value.trim().toLowerCase();
  if ((allowAuto && normalized == 'auto') ||
      RegExp(r'^[a-z]{2,3}(?:-[a-z0-9]{2,8})?$').hasMatch(normalized)) {
    return normalized;
  }
  throw const FormatException('Use a BCP-47 language code such as en or tr.');
}
