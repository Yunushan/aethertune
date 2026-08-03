import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/music_source_provider.dart';
import 'itunes_metadata_provider.dart';

typedef ItunesMetadataProviderFactory =
    ItunesMetadataProvider Function(String country);

/// Persists the credential-free iTunes Store storefront used for metadata
/// searches. A storefront choice affects only future public API requests.
final class ItunesMetadataSettingsStore extends ChangeNotifier {
  ItunesMetadataSettingsStore({ItunesMetadataProviderFactory? providerFactory})
    : _providerFactory = providerFactory ?? _createProvider;

  static const _storefrontKey = 'aethertune.itunes_metadata.storefront.v1';

  final ItunesMetadataProviderFactory _providerFactory;
  String _country = 'us';
  ItunesMetadataProvider? _provider;
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;

  /// The selected ISO 3166-1 alpha-2 storefront in display form.
  String get storefront => _country.toUpperCase();

  ItunesMetadataProvider get provider =>
      _provider ??= _providerFactory(_country);

  List<MusicSourceProvider> get musicProviders => <MusicSourceProvider>[
    provider,
  ];

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      _country = _normalizeStorefront(
        preferences.getString(_storefrontKey) ?? 'us',
      );
      _loadError = null;
    } on Object {
      _country = 'us';
      _loadError = 'iTunes Store storefront settings are unavailable.';
    }
    _provider = null;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setStorefront(String value) async {
    final normalized = _normalizeStorefront(value);
    if (normalized == _country) {
      return;
    }
    final previous = _country;
    _country = normalized;
    _provider = null;
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(_storefrontKey, normalized);
      if (!saved) {
        throw StateError('Could not save the iTunes Store storefront.');
      }
      _loadError = null;
    } on Object {
      _country = previous;
      _provider = null;
      rethrow;
    }
    notifyListeners();
  }
}

ItunesMetadataProvider _createProvider(String country) =>
    ItunesMetadataProvider(country: country);

String _normalizeStorefront(String value) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z]{2}$').hasMatch(normalized)) {
    throw const FormatException(
      'Enter a two-letter ISO iTunes Store storefront code.',
    );
  }
  return normalized;
}
