import 'package:flutter/foundation.dart';

import '../domain/music_source_provider.dart';
import 'jamendo_chart_cache.dart';
import 'jamendo_provider.dart';
import 'provider_credential_vault.dart';

typedef JamendoProviderFactory = JamendoProvider Function(String clientId);

/// Holds a user-owned Jamendo developer client ID outside app preferences.
final class JamendoSettingsStore extends ChangeNotifier {
  JamendoSettingsStore({
    ProviderCredentialVault? credentialVault,
    JamendoProviderFactory? providerFactory,
    JamendoChartCache? chartCache,
  }) : _credentialVault = credentialVault ?? SecureProviderCredentialVault(),
       _providerFactory = providerFactory ?? _createProvider,
       _chartCache = chartCache ?? SharedPreferencesJamendoChartCache();

  static const _credentialId = 'jamendo-api-client-id';

  static JamendoProvider _createProvider(String clientId) {
    return JamendoProvider(clientId: clientId);
  }

  final ProviderCredentialVault _credentialVault;
  final JamendoProviderFactory _providerFactory;
  final JamendoChartCache _chartCache;
  String? _clientId;
  JamendoProvider? _provider;
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  bool get isConfigured => (_clientId ?? '').isNotEmpty;

  List<MusicSourceProvider> get musicProviders {
    final clientId = _clientId;
    if (clientId == null || clientId.isEmpty) {
      return const <MusicSourceProvider>[];
    }
    return <MusicSourceProvider>[_provider ??= _providerFactory(clientId)];
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      _clientId = _normalize(await _credentialVault.read(_credentialId));
      _provider = null;
      _loadError = null;
    } on Object {
      _clientId = null;
      _loadError = 'Jamendo client ID storage is unavailable.';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveClientId(String clientId) async {
    final normalized = _normalize(clientId);
    if (normalized == null) {
      throw const FormatException('Enter a Jamendo developer client ID.');
    }
    await _credentialVault.write(_credentialId, normalized);
    _clientId = normalized;
    _provider = null;
    _loadError = null;
    notifyListeners();
  }

  Future<void> removeClientId() async {
    await _credentialVault.delete(_credentialId);
    await _chartCache.clear();
    _clientId = null;
    _provider = null;
    _loadError = null;
    notifyListeners();
  }
}

String? _normalize(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
