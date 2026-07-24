import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'provider_credential_vault.dart';
import 'youtube_account_provider.dart';
import 'youtube_oauth_client.dart';
import 'youtube_oauth_flow.dart';

typedef YouTubeAuthorizationRunner = Future<YouTubeOAuthToken> Function(
  String clientId,
);
typedef YouTubeAccountProviderFactory = YouTubeAccountProvider Function(
  YouTubeAccessTokenReader accessTokenReader,
);

final class YouTubeOAuthSession {
  const YouTubeOAuthSession({required this.clientId, required this.token});

  final String clientId;
  final YouTubeOAuthToken token;

  Map<String, Object?> toJson() => <String, Object?>{
    'clientId': clientId,
    ...token.toJson(),
  };

  static YouTubeOAuthSession? tryFromJson(Map<String, Object?> json) {
    final clientId = json['clientId']?.toString().trim() ?? '';
    final token = YouTubeOAuthToken.tryFromJson(json);
    if (clientId.isEmpty || token == null || token.refreshToken.isEmpty) {
      return null;
    }
    return YouTubeOAuthSession(clientId: clientId, token: token);
  }
}

/// Persists a desktop-only, read-only YouTube OAuth session in the vault.
final class YouTubeAccountSettingsStore extends ChangeNotifier {
  YouTubeAccountSettingsStore({
    ProviderCredentialVault? credentialVault,
    YouTubeOAuthClient? oauthClient,
    YouTubeAuthorizationRunner? authorizationRunner,
    YouTubeAccountProviderFactory? providerFactory,
    DateTime Function()? clock,
    TargetPlatform? platform,
  }) : _credentialVault = credentialVault ?? SecureProviderCredentialVault(),
       _oauthClient = oauthClient ?? YouTubeOAuthClient(),
       _authorizationRunner = authorizationRunner,
       _providerFactory = providerFactory ??
           ((accessTokenReader) =>
               YouTubeAccountProvider(accessTokenReader: accessTokenReader)),
       _clock = clock ?? DateTime.now,
       _platform = platform ?? defaultTargetPlatform;

  static const _credentialId = 'youtube-oauth-session';
  static const _refreshSkew = Duration(minutes: 1);

  final ProviderCredentialVault _credentialVault;
  final YouTubeOAuthClient _oauthClient;
  final YouTubeAuthorizationRunner? _authorizationRunner;
  final YouTubeAccountProviderFactory _providerFactory;
  final DateTime Function() _clock;
  final TargetPlatform _platform;

  YouTubeOAuthSession? _session;
  YouTubeAccountProvider? _provider;
  bool _loaded = false;
  bool _connecting = false;
  String? _loadError;
  Future<String>? _refreshingToken;

  bool get loaded => _loaded;
  bool get isConfigured => _session != null;
  bool get connecting => _connecting;
  String? get loadError => _loadError;
  String? get clientId => _session?.clientId;
  bool get desktopOAuthSupported => switch (_platform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };

  YouTubeAccountProvider? get accountProvider {
    if (!desktopOAuthSupported || _session == null) {
      return null;
    }
    return _provider ??= _providerFactory(readAccessToken);
  }

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
      _loadError = 'YouTube credential storage is unavailable.';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> connect(String clientId) async {
    if (!desktopOAuthSupported) {
      throw StateError(
        'YouTube account sign-in is available on desktop only.',
      );
    }
    final normalizedClientId = clientId.trim();
    if (normalizedClientId.isEmpty) {
      throw const FormatException('Enter a Google OAuth desktop client ID.');
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
        throw const FormatException('Google did not return a refresh token.');
      }
      final session = YouTubeOAuthSession(
        clientId: normalizedClientId,
        token: token,
      );
      await _credentialVault.write(_credentialId, jsonEncode(session.toJson()));
      _session = session;
      _provider = null;
      _loadError = null;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  Future<void> remove() async {
    await _credentialVault.delete(_credentialId);
    _session = null;
    _provider = null;
    _loadError = null;
    notifyListeners();
  }

  Future<String> readAccessToken() {
    final session = _session;
    if (session == null) {
      throw StateError('YouTube is not connected.');
    }
    if (!session.token.expiresWithin(_refreshSkew, _clock().toUtc())) {
      return Future<String>.value(session.token.accessToken);
    }
    return _refreshingToken ??= _refreshAccessToken(session);
  }

  Future<YouTubeOAuthToken> _authorize(String clientId) {
    return YouTubeOAuthFlow(
      oauthClient: _oauthClient,
    ).authorize(clientId, scopes: authorizationScopes);
  }

  static const Set<String> authorizationScopes = <String>{
    'https://www.googleapis.com/auth/youtube.readonly',
  };

  Future<String> _refreshAccessToken(YouTubeOAuthSession session) async {
    try {
      final refreshed = await _oauthClient.refresh(
        clientId: session.clientId,
        current: session.token,
      );
      final nextSession = YouTubeOAuthSession(
        clientId: session.clientId,
        token: refreshed,
      );
      await _credentialVault.write(
        _credentialId,
        jsonEncode(nextSession.toJson()),
      );
      _session = nextSession;
      _provider = null;
      _loadError = null;
      notifyListeners();
      return refreshed.accessToken;
    } finally {
      _refreshingToken = null;
    }
  }

  static YouTubeOAuthSession? _decodeSession(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      return null;
    }
    return YouTubeOAuthSession.tryFromJson(
      Map<String, Object?>.from(decoded),
    );
  }
}
