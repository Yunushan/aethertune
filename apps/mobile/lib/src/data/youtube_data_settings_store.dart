import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/music_source_provider.dart';
import 'provider_credential_vault.dart';
import 'youtube_data_metadata_provider.dart';

typedef YouTubeDataProviderFactory = YouTubeDataMetadataProvider Function(
  String apiKey,
);

/// Holds the optional, user-owned API key outside regular app preferences.
final class YouTubeDataSettingsStore extends ChangeNotifier {
  YouTubeDataSettingsStore({
    ProviderCredentialVault? credentialVault,
    YouTubeDataProviderFactory? providerFactory,
  }) : _credentialVault = credentialVault ?? SecureProviderCredentialVault(),
       _providerFactory = providerFactory ?? _createProvider;

  static const _credentialId = 'youtube-data-metadata';
  static const _preferredRegionKey = 'aethertune.youtube_data_region.v1';

  final ProviderCredentialVault _credentialVault;
  final YouTubeDataProviderFactory _providerFactory;
  String? _apiKey;
  YouTubeDataMetadataProvider? _provider;
  String _preferredRegion = 'US';
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  bool get isConfigured => (_apiKey ?? '').isNotEmpty;
  String get preferredRegion => _preferredRegion;

  List<MusicSourceProvider> get musicProviders {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      return const <MusicSourceProvider>[];
    }
    return <MusicSourceProvider>[
      _provider ??= _providerFactory(apiKey),
    ];
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      _apiKey = _normalize(await _credentialVault.read(_credentialId));
      _provider = null;
      _loadError = null;
    } on Object {
      _apiKey = null;
      _loadError = 'YouTube Data API key storage is unavailable.';
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _preferredRegion = normalizeYouTubeDataRegion(
        prefs.getString(_preferredRegionKey) ?? 'US',
      );
    } on Object {
      _preferredRegion = 'US';
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
    _provider = null;
    _loadError = null;
    notifyListeners();
  }

  Future<void> removeApiKey() async {
    await _credentialVault.delete(_credentialId);
    _apiKey = null;
    _provider = null;
    _loadError = null;
    notifyListeners();
  }

  Future<void> setPreferredRegion(String value) async {
    final normalized = normalizeYouTubeDataRegion(value);
    if (normalized == _preferredRegion) {
      return;
    }
    final previous = _preferredRegion;
    _preferredRegion = normalized;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(_preferredRegionKey, normalized);
      if (!saved) {
        throw StateError('Could not save the YouTube chart region.');
      }
    } on Object {
      _preferredRegion = previous;
      rethrow;
    }
    notifyListeners();
  }
}

YouTubeDataMetadataProvider _createProvider(String apiKey) {
  return YouTubeDataMetadataProvider(apiKey: apiKey);
}

String? _normalize(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String normalizeYouTubeDataRegion(String value) {
  final normalized = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(normalized)) {
    throw const FormatException('Enter a two-letter ISO region code.');
  }
  return normalized;
}
