import 'package:flutter/foundation.dart';

import '../domain/music_source_provider.dart';
import 'provider_credential_vault.dart';
import 'youtube_data_metadata_provider.dart';

/// Holds the optional, user-owned API key outside regular app preferences.
final class YouTubeDataSettingsStore extends ChangeNotifier {
  YouTubeDataSettingsStore({ProviderCredentialVault? credentialVault})
    : _credentialVault = credentialVault ?? SecureProviderCredentialVault();

  static const _credentialId = 'youtube-data-metadata';

  final ProviderCredentialVault _credentialVault;
  String? _apiKey;
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  bool get isConfigured => (_apiKey ?? '').isNotEmpty;

  List<MusicSourceProvider> get musicProviders => isConfigured
      ? <MusicSourceProvider>[YouTubeDataMetadataProvider(apiKey: _apiKey!)]
      : const <MusicSourceProvider>[];

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      _apiKey = _normalize(await _credentialVault.read(_credentialId));
      _loadError = null;
    } on Object {
      _apiKey = null;
      _loadError = 'YouTube Data API key storage is unavailable.';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveApiKey(String apiKey) async {
    final normalized = _normalize(apiKey);
    if (normalized == null) {
      throw const FormatException('Enter a Google Cloud API key.');
    }
    await _credentialVault.write(_credentialId, normalized);
    _apiKey = normalized;
    _loadError = null;
    notifyListeners();
  }

  Future<void> removeApiKey() async {
    await _credentialVault.delete(_credentialId);
    _apiKey = null;
    _loadError = null;
    notifyListeners();
  }
}

String? _normalize(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
