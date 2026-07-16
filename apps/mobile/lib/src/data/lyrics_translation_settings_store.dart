import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/lyrics_translator.dart';
import 'libretranslate_lyrics_translator.dart';
import 'provider_credential_vault.dart';

typedef LyricsTranslatorFactory = LyricsTranslator Function(
  Uri endpoint,
  String? apiKey,
);

/// Persists only a self-hosted translation endpoint and language preference.
final class LyricsTranslationSettingsStore extends ChangeNotifier {
  LyricsTranslationSettingsStore({
    ProviderCredentialVault? credentialVault,
    LyricsTranslatorFactory? translatorFactory,
  })  : _credentialVault = credentialVault ?? SecureProviderCredentialVault(),
        _translatorFactory = translatorFactory ??
            ((endpoint, apiKey) =>
                LibreTranslateLyricsTranslator(baseUri: endpoint, apiKey: apiKey));

  static const _endpointKey = 'aethertune.lyrics_translation.endpoint.v1';
  static const _targetLanguageKey =
      'aethertune.lyrics_translation.target_language.v1';
  static const _credentialId = 'lyrics-translation-api-key';

  final ProviderCredentialVault _credentialVault;
  final LyricsTranslatorFactory _translatorFactory;
  Uri? _endpoint;
  String _targetLanguage = 'en';
  String? _apiKey;
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  Uri? get endpoint => _endpoint;
  String get targetLanguage => _targetLanguage;
  bool get isConfigured => _endpoint != null;

  LyricsTranslator? get translator {
    final endpoint = _endpoint;
    if (endpoint == null) {
      return null;
    }
    return _translatorFactory(endpoint, _apiKey);
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _endpoint = _parseEndpoint(prefs.getString(_endpointKey));
      _targetLanguage = _readLanguage(
        prefs.getString(_targetLanguageKey),
        fallback: 'en',
      );
      _apiKey = _normalizeApiKey(
        await _credentialVault.read(_credentialId),
      );
      _loadError = null;
    } on Object {
      _endpoint = null;
      _apiKey = null;
      _loadError = 'Lyrics translation settings are unavailable.';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save({
    required String endpoint,
    required String targetLanguage,
    String apiKey = '',
  }) async {
    final parsedEndpoint = _parseEndpoint(endpoint);
    if (parsedEndpoint == null) {
      throw const FormatException('Enter an http or https translation service URL.');
    }
    final normalizedTarget = normalizeTranslationLanguage(targetLanguage);
    final normalizedApiKey = _normalizeApiKey(apiKey);
    final prefs = await SharedPreferences.getInstance();
    if (normalizedApiKey == null) {
      await _credentialVault.delete(_credentialId);
    } else {
      await _credentialVault.write(_credentialId, normalizedApiKey);
    }
    await prefs.setString(_endpointKey, parsedEndpoint.toString());
    await prefs.setString(_targetLanguageKey, normalizedTarget);
    _endpoint = parsedEndpoint;
    _targetLanguage = normalizedTarget;
    _apiKey = normalizedApiKey;
    _loadError = null;
    notifyListeners();
  }

  Future<void> remove() async {
    final prefs = await SharedPreferences.getInstance();
    await _credentialVault.delete(_credentialId);
    await prefs.remove(_endpointKey);
    await prefs.remove(_targetLanguageKey);
    _endpoint = null;
    _apiKey = null;
    _targetLanguage = 'en';
    _loadError = null;
    notifyListeners();
  }
}

Uri? _parseEndpoint(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    throw const FormatException('Use an http or https translation service URL.');
  }
  return LibreTranslateLyricsTranslator(baseUri: uri).baseUri;
}

String _readLanguage(String? value, {required String fallback}) {
  try {
    return normalizeTranslationLanguage(value ?? fallback);
  } on FormatException {
    return fallback;
  }
}

String? _normalizeApiKey(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
