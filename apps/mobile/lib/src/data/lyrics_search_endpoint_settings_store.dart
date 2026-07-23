import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores an explicit, credential-free LRCLIB-compatible search endpoint.
///
/// A null endpoint intentionally means the public LRCLIB service remains in
/// use. A custom endpoint must use HTTPS so lyric search metadata is not sent
/// over cleartext transport.
final class LyricsSearchEndpointSettingsStore extends ChangeNotifier {
  static const _endpointKey = 'aethertune.lyrics_search.endpoint.v1';

  Uri? _endpoint;
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  Uri? get endpoint => _endpoint;
  bool get isConfigured => _endpoint != null;

  Future<void> load() async {
    if (_loaded) {
      return;
    }
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

  Future<void> save(String endpoint) async {
    final parsed = _parseEndpoint(endpoint);
    if (parsed == null) {
      throw const FormatException('Enter an HTTPS LRCLIB-compatible service URL.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_endpointKey, parsed.toString());
    _endpoint = parsed;
    _loadError = null;
    notifyListeners();
  }

  Future<void> remove() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_endpointKey);
    _endpoint = null;
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
