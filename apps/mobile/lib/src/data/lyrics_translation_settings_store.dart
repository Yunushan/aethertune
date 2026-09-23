import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/lyrics_translator.dart';
import 'libretranslate_lyrics_translator.dart';
import 'provider_credential_vault.dart';

typedef LyricsTranslatorFactory =
    LyricsTranslator Function(Uri endpoint, String? apiKey);

/// Persists only a self-hosted translation endpoint and language preference.
final class LyricsTranslationSettingsStore extends ChangeNotifier {
  LyricsTranslationSettingsStore({
    ProviderCredentialVault? credentialVault,
    LyricsTranslatorFactory? translatorFactory,
  }) : _credentialVault = credentialVault ?? SecureProviderCredentialVault(),
       _translatorFactory =
           translatorFactory ??
           ((endpoint, apiKey) => LibreTranslateLyricsTranslator(
             baseUri: endpoint,
             apiKey: apiKey,
           ));

  static const _endpointKey = 'aethertune.lyrics_translation.endpoint.v1';
  static const _targetLanguageKey =
      'aethertune.lyrics_translation.target_language.v1';
  static const _settingsKey = 'aethertune.lyrics_translation.settings.v2';
  static const _credentialId = 'lyrics-translation-api-key';
  static const _credentialPrefix =
      'aethertune.lyrics_translation.credential.v1:';

  final ProviderCredentialVault _credentialVault;
  final LyricsTranslatorFactory _translatorFactory;
  Uri? _endpoint;
  String _targetLanguage = 'en';
  String? _apiKey;
  bool _loaded = false;
  String? _loadError;
  Future<void>? _loadFuture;
  Future<void> _mutationTail = Future<void>.value();

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

  Future<void> load() {
    if (_loaded) {
      return Future<void>.value();
    }
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final document = prefs.getString(_settingsKey);
      Uri? endpoint;
      String targetLanguage;
      if (document == null) {
        endpoint = _parseEndpoint(prefs.getString(_endpointKey));
        targetLanguage = _readLanguage(
          prefs.getString(_targetLanguageKey),
          fallback: 'en',
        );
      } else {
        final decoded = jsonDecode(document);
        if (decoded is! Map || decoded['version'] != 2) {
          throw const FormatException(
            'Lyrics translation settings are invalid.',
          );
        }
        if (decoded['disabled'] == true) {
          endpoint = null;
          targetLanguage = 'en';
        } else {
          if (decoded['endpoint'] is! String ||
              decoded['targetLanguage'] is! String) {
            throw const FormatException(
              'Lyrics translation settings are invalid.',
            );
          }
          endpoint = _parseEndpoint(decoded['endpoint'] as String);
          targetLanguage = normalizeTranslationLanguage(
            decoded['targetLanguage'] as String,
          );
          if (endpoint == null) {
            throw const FormatException(
              'Lyrics translation endpoint is missing.',
            );
          }
        }
      }
      final credential = _readCredential(
        await _credentialVault.read(_credentialId),
        endpoint,
        requireBound: document != null && endpoint != null,
      );
      _endpoint = credential.disabled ? null : endpoint;
      _targetLanguage = credential.disabled ? 'en' : targetLanguage;
      _apiKey = credential.disabled || endpoint == null
          ? null
          : credential.apiKey;
      _loadError = null;
    } on Object {
      _endpoint = null;
      _targetLanguage = 'en';
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
  }) => _serialize(() async {
    final parsedEndpoint = _parseEndpoint(endpoint);
    if (parsedEndpoint == null) {
      throw const FormatException(
        'Enter an http or https translation service URL.',
      );
    }
    final normalizedTarget = normalizeTranslationLanguage(targetLanguage);
    final normalizedApiKey = _normalizeApiKey(apiKey);
    await load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final previousDocument = prefs.getString(_settingsKey);
    final previousCredential = await _credentialVault.read(_credentialId);
    final document = jsonEncode(<String, Object?>{
      'version': 2,
      'endpoint': parsedEndpoint.toString(),
      'targetLanguage': normalizedTarget,
    });
    var credentialWriteAttempted = false;
    try {
      credentialWriteAttempted = true;
      await _credentialVault.write(
        _credentialId,
        _boundCredential(parsedEndpoint, normalizedApiKey),
      );
      final saved = await prefs.setString(_settingsKey, document);
      if (!saved) {
        throw StateError('Could not save lyrics translation settings.');
      }
    } on Object {
      var restored = false;
      try {
        await prefs.reload();
        restored = prefs.getString(_settingsKey) == previousDocument;
      } on Object {
        // A failed reload leaves the durable endpoint unknown.
      }
      if (credentialWriteAttempted) {
        try {
          if (previousCredential == null) {
            await _credentialVault.delete(_credentialId);
          } else {
            await _credentialVault.write(_credentialId, previousCredential);
          }
        } on Object {
          restored = false;
        }
      }
      if (!restored) {
        _endpoint = null;
        _apiKey = null;
        _loadError = 'Lyrics translation settings could not be restored.';
        notifyListeners();
      }
      rethrow;
    }
    _endpoint = parsedEndpoint;
    _targetLanguage = normalizedTarget;
    _apiKey = normalizedApiKey;
    _loadError = null;
    notifyListeners();
  });

  Future<void> remove() => _serialize(() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    const disabledDocument = '{"version":2,"disabled":true}';
    try {
      // The vault marker prevents an old endpoint from becoming active if a
      // preferences removal fails or the app exits between the two stores.
      await _credentialVault.write(
        _credentialId,
        '$_credentialPrefix{"version":1,"disabled":true}',
      );
      final saved = await prefs.setString(_settingsKey, disabledDocument);
      if (!saved) {
        throw StateError('Could not remove lyrics translation settings.');
      }
      for (final key in <String>[_endpointKey, _targetLanguageKey]) {
        await prefs.remove(key);
        await prefs.reload();
        if (prefs.containsKey(key)) {
          throw StateError('Could not remove lyrics translation settings.');
        }
      }
      _loadError = null;
    } on Object {
      _loadError = 'Lyrics translation settings could not be fully removed.';
      rethrow;
    } finally {
      _endpoint = null;
      _apiKey = null;
      _targetLanguage = 'en';
      notifyListeners();
    }
  });

  Future<T> _serialize<T>(Future<T> Function() mutation) {
    final result = _mutationTail.then((_) => mutation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }
}

String _boundCredential(Uri endpoint, String? apiKey) =>
    '${LyricsTranslationSettingsStore._credentialPrefix}'
    '${jsonEncode(<String, Object?>{'version': 1, 'endpoint': endpoint.toString(), 'apiKey': apiKey})}';

_TranslationCredential _readCredential(
  String? value,
  Uri? endpoint, {
  required bool requireBound,
}) {
  if (value == null) {
    if (requireBound) {
      throw const FormatException('Lyrics translation credential is missing.');
    }
    return const _TranslationCredential();
  }
  if (!value.startsWith(LyricsTranslationSettingsStore._credentialPrefix)) {
    if (requireBound) {
      throw const FormatException('Lyrics translation credential is unbound.');
    }
    return _TranslationCredential(apiKey: _normalizeApiKey(value));
  }
  final decoded = jsonDecode(
    value.substring(LyricsTranslationSettingsStore._credentialPrefix.length),
  );
  if (decoded is! Map || decoded['version'] != 1) {
    throw const FormatException('Lyrics translation credential is invalid.');
  }
  if (decoded['disabled'] == true) {
    return const _TranslationCredential(disabled: true);
  }
  if (endpoint == null || decoded['endpoint'] != endpoint.toString()) {
    throw const FormatException(
      'Lyrics translation credential does not match.',
    );
  }
  final apiKey = decoded['apiKey'];
  if (apiKey != null && apiKey is! String) {
    throw const FormatException('Lyrics translation credential is invalid.');
  }
  return _TranslationCredential(apiKey: _normalizeApiKey(apiKey as String?));
}

final class _TranslationCredential {
  const _TranslationCredential({this.disabled = false, this.apiKey});

  final bool disabled;
  final String? apiKey;
}

Uri? _parseEndpoint(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    throw const FormatException(
      'Use an http or https translation service URL.',
    );
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
