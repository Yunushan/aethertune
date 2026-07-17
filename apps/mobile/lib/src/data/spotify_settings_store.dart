import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/music_source_provider.dart';
import 'provider_credential_vault.dart';
import 'spotify_metadata_provider.dart';
import 'spotify_oauth_client.dart';
import 'spotify_oauth_flow.dart';

typedef SpotifyAuthorizationRunner = Future<SpotifyOAuthToken> Function(
  String clientId,
);

final class SpotifyOAuthSession {
  const SpotifyOAuthSession({required this.clientId, required this.token});

  final String clientId;
  final SpotifyOAuthToken token;

  Map<String, Object?> toJson() => <String, Object?>{
    'clientId': clientId,
    ...token.toJson(),
  };

  static SpotifyOAuthSession? tryFromJson(Map<String, Object?> json) {
    final clientId = json['clientId']?.toString().trim() ?? '';
    final token = SpotifyOAuthToken.tryFromJson(json);
    if (clientId.isEmpty || token == null) {
      return null;
    }
    return SpotifyOAuthSession(clientId: clientId, token: token);
  }
}

/// Persists a Spotify PKCE session solely in the platform credential vault.
final class SpotifySettingsStore extends ChangeNotifier {
  SpotifySettingsStore({
    ProviderCredentialVault? credentialVault,
    SpotifyOAuthClient? oauthClient,
    SpotifyAuthorizationRunner? authorizationRunner,
    DateTime Function()? clock,
  }) : _credentialVault = credentialVault ?? SecureProviderCredentialVault(),
       _oauthClient = oauthClient ?? SpotifyOAuthClient(),
       _clock = clock ?? DateTime.now,
       _authorizationRunner = authorizationRunner;

  static const _credentialId = 'spotify-oauth-session';
  static const _refreshSkew = Duration(minutes: 1);

  final ProviderCredentialVault _credentialVault;
  final SpotifyOAuthClient _oauthClient;
  final SpotifyAuthorizationRunner? _authorizationRunner;
  final DateTime Function() _clock;

  SpotifyOAuthSession? _session;
  bool _loaded = false;
  bool _connecting = false;
  String? _loadError;
  Future<String>? _refreshingToken;

  bool get loaded => _loaded;
  bool get isConfigured => _session != null;
  bool get connecting => _connecting;
  String? get loadError => _loadError;
  String? get clientId => _session?.clientId;

  List<MusicSourceProvider> get musicProviders => _session == null
      ? const <MusicSourceProvider>[]
      : <MusicSourceProvider>[
          SpotifyMetadataProvider(accessTokenReader: readAccessToken),
        ];

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final encoded = await _credentialVault.read(_credentialId);
      _session = _decodeSession(encoded);
      _loadError = null;
    } on Object {
      _session = null;
      _loadError = 'Spotify credential storage is unavailable.';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> connect(String clientId) async {
    final normalizedClientId = clientId.trim();
    if (normalizedClientId.isEmpty) {
      throw const FormatException('Enter a Spotify developer client ID.');
    }
    if (_connecting) {
      return;
    }
    _connecting = true;
    notifyListeners();
    try {
      final token = await (_authorizationRunner ?? _authorize)(
        normalizedClientId,
      );
      if (token.refreshToken.trim().isEmpty) {
        throw const FormatException('Spotify did not return a refresh token.');
      }
      final session = SpotifyOAuthSession(
        clientId: normalizedClientId,
        token: token,
      );
      await _credentialVault.write(_credentialId, jsonEncode(session.toJson()));
      _session = session;
      _loadError = null;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> remove() async {
    await _credentialVault.delete(_credentialId);
    _session = null;
    _loadError = null;
    notifyListeners();
  }

  Future<String> readAccessToken() {
    final session = _session;
    if (session == null) {
      throw StateError('Spotify is not connected.');
    }
    if (!session.token.expiresWithin(_refreshSkew, _clock().toUtc())) {
      return Future<String>.value(session.token.accessToken);
    }
    return _refreshingToken ??= _refreshAccessToken(session);
  }

  Future<SpotifyOAuthToken> _authorize(String clientId) {
    return SpotifyOAuthFlow(
      oauthClient: _oauthClient,
    ).authorize(clientId, scopes: _requiredScopes);
  }

  static const Set<String> _requiredScopes = <String>{'user-library-read'};

  Future<String> _refreshAccessToken(SpotifyOAuthSession session) async {
    try {
      final refreshed = await _oauthClient.refresh(
        clientId: session.clientId,
        current: session.token,
      );
      final nextSession = SpotifyOAuthSession(
        clientId: session.clientId,
        token: refreshed,
      );
      await _credentialVault.write(
        _credentialId,
        jsonEncode(nextSession.toJson()),
      );
      _session = nextSession;
      _loadError = null;
      notifyListeners();
      return refreshed.accessToken;
    } finally {
      _refreshingToken = null;
    }
  }

  static SpotifyOAuthSession? _decodeSession(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      return null;
    }
    return SpotifyOAuthSession.tryFromJson(Map<String, Object?>.from(decoded));
  }
}
