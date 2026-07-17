import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/music_catalog_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/self_hosted_provider_account.dart';
import '../domain/track.dart';
import 'jellyfin_provider.dart';
import 'provider_artwork_file_cache.dart';
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

final class SelfHostedProviderAccountExport {
  const SelfHostedProviderAccountExport({
    required this.json,
    required this.exportedAccountCount,
    required this.skippedInsecureAccountCount,
  });

  final String json;
  final int exportedAccountCount;
  final int skippedInsecureAccountCount;
}

final class SelfHostedProviderAccountImportResult {
  const SelfHostedProviderAccountImportResult({
    required this.importedAccountCount,
    required this.skippedExistingAccountCount,
    required this.skippedInsecureAccountCount,
  });

  final int importedAccountCount;
  final int skippedExistingAccountCount;
  final int skippedInsecureAccountCount;
}

final class SelfHostedProviderStore extends ChangeNotifier {
  SelfHostedProviderStore({
    ProviderCredentialVault? credentialVault,
    SelfHostedConnectionTester? connectionTester,
    SelfHostedProviderFactory? providerFactory,
    ProviderArtworkFileCache? artworkFileCache,
  })  : _credentialVault =
            credentialVault ?? SecureProviderCredentialVault(),
        _connectionTester = connectionTester ?? _testConnection,
        _providerFactory = providerFactory ?? _createProvider,
        _artworkFileCache = artworkFileCache ?? ProviderArtworkFileCache();

  static const _accountsKey = 'aethertune.self_hosted_accounts.v1';
  static const accountMigrationDocumentFormat =
      'aethertune.self_hosted_accounts';
  static const accountMigrationDocumentVersion = 1;
  static const _maximumMigrationBytes = 64 * 1024;
  static const _maximumMigrationAccounts = 32;

  final ProviderCredentialVault _credentialVault;
  final SelfHostedConnectionTester _connectionTester;
  final SelfHostedProviderFactory _providerFactory;
  final ProviderArtworkFileCache _artworkFileCache;
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

  SelfHostedProviderAccountExport exportAccountConfiguration() {
    final exportable = _accounts
        .where((account) => account.usesSecureTransport)
        .toList(growable: false);
    return SelfHostedProviderAccountExport(
      json: jsonEncode(<String, Object?>{
        'format': accountMigrationDocumentFormat,
        'version': accountMigrationDocumentVersion,
        'accounts': exportable.map((account) => account.toJson()).toList(),
      }),
      exportedAccountCount: exportable.length,
      skippedInsecureAccountCount: _accounts.length - exportable.length,
    );
  }

  Future<SelfHostedProviderAccountImportResult>
      importAccountConfiguration(String document) async {
    if (utf8.encode(document).length > _maximumMigrationBytes) {
      throw const FormatException(
        'Self-hosted account configuration is too large.',
      );
    }

    final decoded = jsonDecode(document);
    if (decoded is! Map) {
      throw const FormatException('Self-hosted account configuration is invalid.');
    }
    final root = Map<String, Object?>.from(decoded);
    if (root['format'] != accountMigrationDocumentFormat ||
        root['version'] != accountMigrationDocumentVersion) {
      throw const FormatException(
        'This is not a supported self-hosted account configuration.',
      );
    }
    final rawAccounts = root['accounts'];
    if (rawAccounts is! List || rawAccounts.length > _maximumMigrationAccounts) {
      throw const FormatException(
        'Self-hosted account configuration has an invalid account list.',
      );
    }

    final importedCandidates = <SelfHostedProviderAccount>[];
    final documentIds = <String>{};
    var skippedInsecureAccountCount = 0;
    for (final rawAccount in rawAccounts) {
      if (rawAccount is! Map) {
        throw const FormatException(
          'Self-hosted account configuration contains an invalid account.',
        );
      }
      final account = SelfHostedProviderAccount.fromJson(
        Map<String, Object?>.from(rawAccount),
      );
      if (!documentIds.add(account.id)) {
        throw const FormatException(
          'Self-hosted account configuration contains duplicate accounts.',
        );
      }
      if (!account.usesSecureTransport) {
        skippedInsecureAccountCount += 1;
        continue;
      }
      importedCandidates.add(account);
    }

    final existingIds = _accounts.map((account) => account.id).toSet();
    final accountsToImport = importedCandidates
        .where((account) => !existingIds.contains(account.id))
        .toList(growable: false);
    final result = SelfHostedProviderAccountImportResult(
      importedAccountCount: accountsToImport.length,
      skippedExistingAccountCount:
          importedCandidates.length - accountsToImport.length,
      skippedInsecureAccountCount: skippedInsecureAccountCount,
    );
    if (accountsToImport.isEmpty) {
      return result;
    }

    final oldAccounts = List<SelfHostedProviderAccount>.from(_accounts);
    try {
      _accounts
        ..addAll(accountsToImport)
        ..sort((left, right) => left.name.compareTo(right.name));
      await _saveMetadata();
    } on Object {
      _accounts
        ..clear()
        ..addAll(oldAccounts);
      rethrow;
    }
    notifyListeners();
    return result;
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
    final normalizedWidth = maxWidth.clamp(32, 2048);
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

  Future<void> rotateCredential(String accountId, String newSecret) async {
    SelfHostedProviderAccount? account;
    for (final candidate in _accounts) {
      if (candidate.id == accountId) {
        account = candidate;
        break;
      }
    }
    if (account == null) {
      throw StateError('Self-hosted account does not exist.');
    }
    final oldSecret = _secrets[accountId] ?? '';
    if (oldSecret.isEmpty) {
      throw StateError('The existing secure credential is unavailable.');
    }
    if (newSecret.isEmpty) {
      throw FormatException('${account.kind.secretLabel} is required.');
    }
    if (newSecret == oldSecret) {
      throw FormatException(
        'New ${account.kind.secretLabel.toLowerCase()} must differ from the current credential.',
      );
    }

    try {
      await _connectionTester(account, newSecret);
    } on Object catch (error) {
      throw ProviderRequestException(
        safeProviderErrorMessage(
          error,
          providerName: account.name,
          secrets: <String>[oldSecret, newSecret],
        ),
      );
    }

    try {
      await _credentialVault.write(accountId, newSecret);
    } on Object catch (error) {
      try {
        await _credentialVault.write(accountId, oldSecret);
      } on Object {
        throw StateError(
          '${account.name} credential rotation failed and the previous credential could not be restored.',
        );
      }
      throw ProviderRequestException(
        safeProviderErrorMessage(
          error,
          providerName: account.name,
          secrets: <String>[oldSecret, newSecret],
        ),
      );
    }

    _secrets[accountId] = newSecret;
    _clearArtworkRequests(accountId);
    try {
      await _artworkFileCache.removeProvider(account.providerId);
    } on Object {
      // Rotation succeeded; private cache cleanup is best effort.
    }
    notifyListeners();
  }

  Future<void> remove(String accountId) async {
    final oldAccounts = List<SelfHostedProviderAccount>.from(_accounts);
    final oldSecret = _secrets[accountId];
    SelfHostedProviderAccount? removedAccount;
    for (final account in _accounts) {
      if (account.id == accountId) {
        removedAccount = account;
        break;
      }
    }
    if (removedAccount == null) {
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
    try {
      await _artworkFileCache.removeProvider(removedAccount.providerId);
    } on Object {
      // Account and credential deletion must not fail on best-effort cache cleanup.
    }
    notifyListeners();
  }

  Future<Track> resolveTrack(Track track) async {
    final provider = _providerForSourceId(track.sourceId);
    if (provider == null) {
      return track;
    }
    final results = await Future.wait<Uri?>(<Future<Uri?>>[
      track.isPlayable
          ? Future<Uri?>.value(null)
          : provider.resolveStream(track),
      track.artworkUri != null || track.providerArtworkId == null
          ? Future<Uri?>.value(null)
          : _materializeTrackArtwork(track),
    ]);
    final streamUri = results[0];
    final artworkUri = results[1];
    if (streamUri == null && artworkUri == null) {
      return track;
    }
    return track.copyWith(
      streamUrl: streamUri?.toString(),
      streamUrlIsEphemeral:
          streamUri == null ? track.streamUrlIsEphemeral : true,
      artworkUri: artworkUri,
      artworkUriIsEphemeral:
          artworkUri == null ? track.artworkUriIsEphemeral : true,
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

  MusicCatalogProvider? _providerForSourceId(String sourceId) {
    for (final account in _accounts) {
      final secret = _secrets[account.id];
      if (account.providerId == sourceId &&
          secret != null &&
          secret.isNotEmpty) {
        return _providerFactory(account, secret);
      }
    }
    return null;
  }

  Future<Uri?> _materializeTrackArtwork(Track track) async {
    try {
      final artworkId = track.providerArtworkId;
      if (artworkId == null || artworkId.trim().isEmpty) {
        return null;
      }
      final bytes = await loadArtwork(
        sourceId: track.sourceId,
        artworkId: artworkId,
        version: track.providerArtworkVersion,
        maxWidth: 512,
      );
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      return _artworkFileCache.materialize(
        sourceId: track.sourceId,
        artworkId: artworkId,
        version: track.providerArtworkVersion,
        bytes: bytes,
      );
    } on Object {
      return null;
    }
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
