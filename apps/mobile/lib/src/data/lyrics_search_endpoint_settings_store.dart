import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores an explicit, credential-free LRCLIB-compatible search endpoint.
///
/// A null endpoint intentionally means the public LRCLIB service remains in
/// use. A custom endpoint must use HTTPS so lyric search metadata is not sent
/// over cleartext transport.
final class LyricsSearchEndpointSettingsStore extends ChangeNotifier {
  static const _endpointKey = 'aethertune.lyrics_search.endpoint.v1';
  static const configurationDocumentFormat =
      'aethertune.lyrics_search_endpoint';
  static const configurationDocumentVersion = 1;

  Uri? _endpoint;
  bool _loaded = false;
  String? _loadError;
  Future<void>? _loadFuture;
  Future<void> _mutationTail = Future<void>.value();

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  Uri? get endpoint => _endpoint;
  bool get isConfigured => _endpoint != null;

  /// Produces the portable section used by authenticated provider sync.
  /// The endpoint is credential-free by construction and no cached searches
  /// are included.
  Map<String, Object?> exportConfiguration() {
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw StateError(
        'Configure a lyrics search service before uploading it.',
      );
    }
    return <String, Object?>{
      'format': configurationDocumentFormat,
      'version': configurationDocumentVersion,
      'endpoint': endpoint.toString(),
    };
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
      _endpoint = _parseEndpoint(prefs.getString(_endpointKey));
      _loadError = null;
    } on Object {
      _endpoint = null;
      _loadError = 'Lyrics search endpoint settings are unavailable.';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(String endpoint) => _serialize(() async {
    final parsed = _parseEndpoint(endpoint);
    if (parsed == null) {
      throw const FormatException(
        'Enter an HTTPS LRCLIB-compatible service URL.',
      );
    }
    await load();
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = await prefs.setString(_endpointKey, parsed.toString());
      if (!saved) {
        throw StateError('Could not save the lyrics search endpoint.');
      }
    } on Object {
      try {
        await prefs.reload();
      } on Object {
        // Preserve the original write failure.
      }
      rethrow;
    }
    _endpoint = parsed;
    _loadError = null;
    notifyListeners();
  });

  Future<void> remove() => _serialize(() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.remove(_endpointKey);
      await prefs.reload();
      if (prefs.containsKey(_endpointKey)) {
        throw StateError('Could not remove the lyrics search endpoint.');
      }
    } on Object {
      try {
        await prefs.reload();
      } on Object {
        // Preserve the original removal failure.
      }
      rethrow;
    }
    _endpoint = null;
    _loadError = null;
    notifyListeners();
  });

  Future<T> _serialize<T>(Future<T> Function() mutation) {
    final result = _mutationTail.then((_) => mutation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// Replaces this device's configured service with a validated synced value.
  Future<void> importConfiguration(Map<String, Object?> document) async {
    const allowedKeys = <String>{'format', 'version', 'endpoint'};
    if (document.keys.any((key) => !allowedKeys.contains(key)) ||
        document['format'] != configurationDocumentFormat ||
        document['version'] != configurationDocumentVersion ||
        document['endpoint'] is! String) {
      throw const FormatException(
        'Lyrics search endpoint configuration is invalid.',
      );
    }
    await save(document['endpoint'] as String);
  }
}

Uri? _parseEndpoint(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
      'Use an HTTPS service URL without credentials or query parameters.',
    );
  }
  return uri.replace(fragment: null, query: null);
}
