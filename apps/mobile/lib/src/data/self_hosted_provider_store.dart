import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/music_catalog_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/self_hosted_provider_account.dart';
import '../domain/track.dart';
import 'jellyfin_provider.dart';
import 'provider_credential_vault.dart';
import 'provider_error.dart';
import 'subsonic_provider.dart';

typedef SelfHostedConnectionTester = Future<void> Function(
  SelfHostedProviderAccount account,
  String secret,
);
typedef SelfHostedProviderFactory = MusicCatalogProvider Function(
  SelfHostedProviderAccount account,
  String secret,
);

final class SelfHostedProviderStore extends ChangeNotifier {
  SelfHostedProviderStore({
    ProviderCredentialVault? credentialVault,
    SelfHostedConnectionTester? connectionTester,
    SelfHostedProviderFactory? providerFactory,
  })  : _credentialVault =
            credentialVault ?? SecureProviderCredentialVault(),
        _connectionTester = connectionTester ?? _testConnection,
        _providerFactory = providerFactory ?? _createProvider;

  static const _accountsKey = 'aethertune.self_hosted_accounts.v1';

  final ProviderCredentialVault _credentialVault;
  final SelfHostedConnectionTester _connectionTester;
  final SelfHostedProviderFactory _providerFactory;
  final List<SelfHostedProviderAccount> _accounts =
      <SelfHostedProviderAccount>[];
  final Map<String, String> _secrets = <String, String>{};
  final Map<String, Future<Uint8List?>> _artworkRequests =
      <String, Future<Uint8List?>>{};
  bool _loaded = false;
  String? _loadError;
  int _artworkRevision = 0;

  List<SelfHostedProviderAccount> get accounts => List.unmodifiable(_accounts);
  bool get loaded => _loaded;
  String? get loadError => _loadError;
  int get artworkRevision => _artworkRevision;

  List<MusicSourceProvider> get musicProviders {
    return <MusicSourceProvider>[
      for (final account in _accounts)
        if ((_secrets[account.id] ?? '').isNotEmpty)
          _providerFactory(account, _secrets[account.id]!),
    ];
  }

  bool hasCredential(String accountId) =>
      (_secrets[accountId] ?? '').isNotEmpty;

  bool hasCredentialForProvider(String providerId) {
    for (final account in _accounts) {
      if (account.providerId == providerId) {
        return hasCredential(account.id);
      }
    }
    return false;
  }

  MusicCatalogProvider? catalogProviderFor(String accountId) {
    SelfHostedProviderAccount? account;
    for (final candidate in _accounts) {
      if (candidate.id == accountId) {
        account = candidate;
        break;
      }
    }
    final secret = _secrets[accountId];
    if (account == null || secret == null || secret.isEmpty) {
      return null;
    }
    return _providerFactory(account, secret);
  }

  Future<Uint8List?> loadArtwork({
    required String sourceId,
    required String artworkId,
    String? version,
    int maxWidth = 512,
  }) {
    final normalizedArtworkId = artworkId.trim();
    if (normalizedArtworkId.isEmpty) {
      return Future<Uint8List?>.value(null);
    }
    SelfHostedProviderAccount? account;
    for (final candidate in _accounts) {
      if (candidate.providerId == sourceId) {
        account = candidate;
        break;
      }
    }
    final secret = account == null ? null : _secrets[account.id];
    if (account == null || secret == null || secret.isEmpty) {
      return Future<Uint8List?>.value(null);
    }

    final normalizedVersion = version?.trim() ?? '';
    final normalizedWidth = maxWidth.clamp(32, 2048) as int;
    final cacheKey = '${account.id}|$normalizedArtworkId|'
        '$normalizedVersion|$normalizedWidth';
    final cached = _artworkRequests[cacheKey];
    if (cached != null) {
      return cached;
    }
    if (_artworkRequests.length >= 128) {
      _artworkRequests.remove(_artworkRequests.keys.first);
    }

    late final Future<Uint8List?> request;
    request = () async {
      try {
        return await _providerFactory(account!, secret).loadArtwork(
          normalizedArtworkId,
          version: normalizedVersion,
          maxWidth: normalizedWidth,
        );
      } on Object {
        if (identical(_artworkRequests[cacheKey], request)) {
          _artworkRequests.remove(cacheKey);
        }
        rethrow;
      }
    }();
    _artworkRequests[cacheKey] = request;
    return request;
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_accountsKey);
      final decoded = raw == null || raw.isEmpty
          ? const <Object?>[]
          : jsonDecode(raw) as List<dynamic>;
      final accounts = <SelfHostedProviderAccount>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          accounts.add(
            SelfHostedProviderAccount.fromJson(
              Map<String, Object?>.from(item),
            ),
          );
        } on Object {
          // Skip only the malformed account; other secure entries remain usable.
        }
      }

      final secrets = <String, String>{};
      for (final account in accounts) {
        final secret = await _credentialVault.read(account.id);
        if (secret != null && secret.isNotEmpty) {
          secrets[account.id] = secret;
        }
      }
      _accounts
        ..clear()
        ..addAll(accounts);
      _secrets
        ..clear()
        ..addAll(secrets);
      _loadError = null;
    } on Object catch (error) {
      _loadError = error.toString();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> testAndSave(
    SelfHostedProviderAccount account,
    String secret,
  ) async {
    final validated = validateSelfHostedProviderAccount(account);
    final normalizedSecret = secret.isEmpty
        ? _secrets[validated.id] ?? ''
        : secret;
    if (normalizedSecret.isEmpty) {
      throw FormatException('${validated.kind.secretLabel} is required.');
    }

    try {
      await _connectionTester(validated, normalizedSecret);
    } on Object catch (error) {
      throw ProviderRequestException(
        safeProviderErrorMessage(
          error,
          providerName: validated.name,
          secrets: <String>[normalizedSecret],
        ),
      );
    }
    final oldSecret = _secrets[validated.id];
    await _credentialVault.write(validated.id, normalizedSecret);
    final oldAccounts = List<SelfHostedProviderAccount>.from(_accounts);
    try {
      final index = _accounts.indexWhere((item) => item.id == validated.id);
      if (index == -1) {
        _accounts.add(validated);
      } else {
        _accounts[index] = validated;
      }
      _accounts.sort((left, right) => left.name.compareTo(right.name));
      _secrets[validated.id] = normalizedSecret;
      await _saveMetadata();
    } on Object {
      _accounts
        ..clear()
        ..addAll(oldAccounts);
      if (oldSecret == null) {
        _secrets.remove(validated.id);
        await _credentialVault.delete(validated.id);
      } else {
        _secrets[validated.id] = oldSecret;
        await _credentialVault.write(validated.id, oldSecret);
      }
      rethrow;
    }
    _clearArtworkRequests(validated.id);
    notifyListeners();
  }

  Future<void> remove(String accountId) async {
    final oldAccounts = List<SelfHostedProviderAccount>.from(_accounts);
    final oldSecret = _secrets[accountId];
    if (!_accounts.any((item) => item.id == accountId)) {
      return;
    }
    _accounts.removeWhere((item) => item.id == accountId);
    _secrets.remove(accountId);
    try {
      await _credentialVault.delete(accountId);
      await _saveMetadata();
    } on Object {
      _accounts
        ..clear()
        ..addAll(oldAccounts);
      if (oldSecret != null) {
        _secrets[accountId] = oldSecret;
        await _credentialVault.write(accountId, oldSecret);
      }
      rethrow;
    }
    _clearArtworkRequests(accountId);
    notifyListeners();
  }

  Future<Track> resolveTrack(Track track) async {
    if (track.isPlayable) {
      return track;
    }
    MusicSourceProvider? provider;
    for (final candidate in musicProviders) {
      if (candidate.id == track.sourceId) {
        provider = candidate;
        break;
      }
    }
    if (provider == null) {
      return track;
    }
    final streamUri = await provider.resolveStream(track);
    if (streamUri == null) {
      return track;
    }
    return track.copyWith(
      streamUrl: streamUri.toString(),
      streamUrlIsEphemeral: true,
    );
  }

  @override
  void dispose() {
    _secrets.clear();
    _artworkRequests.clear();
    super.dispose();
  }

  Future<void> _saveMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _accountsKey,
      jsonEncode(_accounts.map((item) => item.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Could not save self-hosted provider metadata.');
    }
  }

  void _clearArtworkRequests(String accountId) {
    _artworkRequests.removeWhere(
      (key, _) => key.startsWith('$accountId|'),
    );
    _artworkRevision += 1;
  }

  static MusicCatalogProvider _createProvider(
    SelfHostedProviderAccount account,
    String secret,
  ) {
    switch (account.kind) {
      case SelfHostedProviderKind.jellyfin:
        return JellyfinProvider(
          baseUri: account.baseUri,
          userId: account.identity,
          apiKey: secret,
          id: account.providerId,
          name: account.name,
        );
      case SelfHostedProviderKind.subsonic:
        return SubsonicProvider(
          baseUri: account.baseUri,
          username: account.identity,
          password: secret,
          id: account.providerId,
          name: account.name,
        );
    }
  }

  static Future<void> _testConnection(
    SelfHostedProviderAccount account,
    String secret,
  ) async {
    final provider = _createProvider(account, secret);
    switch (provider) {
      case JellyfinProvider jellyfin:
        await jellyfin.testConnection();
      case SubsonicProvider subsonic:
        await subsonic.testConnection();
      default:
        throw StateError('Unsupported self-hosted provider.');
    }
  }
}
