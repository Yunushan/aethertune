import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

final class YouTubeOAuthHttpResponse {
  const YouTubeOAuthHttpResponse({required this.statusCode, this.body = ''});

  final int statusCode;
  final String body;
}

typedef YouTubeOAuthHttpRequest = Future<YouTubeOAuthHttpResponse> Function(
  Uri uri, {
  required String method,
  required Map<String, String> headers,
  String? body,
});

final class YouTubeOAuthToken {
  const YouTubeOAuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool expiresWithin(Duration duration, DateTime now) =>
      !expiresAt.isAfter(now.add(duration));

  Map<String, Object?> toJson() => <String, Object?>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  static YouTubeOAuthToken? tryFromJson(Map<String, Object?> json) {
    final accessToken = _nonEmpty(json['accessToken']);
    final refreshToken = _nonEmpty(json['refreshToken']);
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (accessToken == null || refreshToken == null || expiresAt == null) {
      return null;
    }
    return YouTubeOAuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt.toUtc(),
    );
  }
}

/// A PKCE request for a user-owned Google OAuth desktop client.
final class YouTubeAuthorizationRequest {
  YouTubeAuthorizationRequest({
    required this.clientId,
    required this.redirectUri,
    required this.state,
    required this.codeVerifier,
    required this.scopes,
  }) : codeChallenge = youtubePkceChallenge(codeVerifier);

  final String clientId;
  final Uri redirectUri;
  final String state;
  final String codeVerifier;
  final String codeChallenge;
  final List<String> scopes;

  Uri get uri => Uri.https(
    'accounts.google.com',
    '/o/oauth2/v2/auth',
    <String, String>{
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri.toString(),
      'scope': scopes.join(' '),
      'code_challenge_method': 'S256',
      'code_challenge': codeChallenge,
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
    },
  );

  static YouTubeAuthorizationRequest create({
    required String clientId,
    required Uri redirectUri,
    required Iterable<String> scopes,
    Random? random,
  }) {
    final normalizedClientId = clientId.trim();
    if (normalizedClientId.isEmpty) {
      throw const FormatException('Enter a Google OAuth desktop client ID.');
    }
    if (redirectUri.scheme != 'http' || redirectUri.host != '127.0.0.1') {
      throw const FormatException(
        'YouTube desktop OAuth requires a 127.0.0.1 callback URL.',
      );
    }
    final normalizedScopes = _normalizeScopes(scopes);
    if (normalizedScopes.isEmpty) {
      throw const FormatException('At least one YouTube OAuth scope is required.');
    }
    final source = random ?? Random.secure();
    return YouTubeAuthorizationRequest(
      clientId: normalizedClientId,
      redirectUri: redirectUri,
      state: _randomUrlSafeString(source, 32),
      codeVerifier: _randomUrlSafeString(source, 64),
      scopes: normalizedScopes,
    );
  }
}

String youtubePkceChallenge(String verifier) {
  final normalized = verifier.trim();
  if (normalized.length < 43 || normalized.length > 128) {
    throw const FormatException('YouTube PKCE verifier has an invalid length.');
  }
  return base64UrlEncode(sha256.convert(utf8.encode(normalized)).bytes)
      .replaceAll('=', '');
}

final class YouTubeOAuthClient {
  YouTubeOAuthClient({
    YouTubeOAuthHttpRequest? request,
    DateTime Function()? clock,
  }) : _request = request ?? _sendRequest,
       _clock = clock ?? DateTime.now;

  static final Uri tokenUri = Uri.parse('https://oauth2.googleapis.com/token');

  final YouTubeOAuthHttpRequest _request;
  final DateTime Function() _clock;

  Future<YouTubeOAuthToken> exchangeAuthorizationCode({
    required YouTubeAuthorizationRequest authorization,
    required String code,
  }) {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) {
      throw const FormatException('Google did not return an authorization code.');
    }
    return _requestToken(<String, String>{
      'client_id': authorization.clientId,
      'grant_type': 'authorization_code',
      'code': normalizedCode,
      'redirect_uri': authorization.redirectUri.toString(),
      'code_verifier': authorization.codeVerifier,
    });
  }

  Future<YouTubeOAuthToken> refresh({
    required String clientId,
    required YouTubeOAuthToken current,
  }) async {
    final refreshed = await _requestToken(<String, String>{
      'client_id': clientId.trim(),
      'grant_type': 'refresh_token',
      'refresh_token': current.refreshToken,
    });
    return YouTubeOAuthToken(
      accessToken: refreshed.accessToken,
      refreshToken: refreshed.refreshToken.isEmpty
          ? current.refreshToken
          : refreshed.refreshToken,
      expiresAt: refreshed.expiresAt,
    );
  }

  Future<YouTubeOAuthToken> _requestToken(Map<String, String> values) async {
    final response = await _request(
      tokenUri,
      method: 'POST',
      headers: const <String, String>{
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
      },
      body: Uri(queryParameters: values).query,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google rejected the YouTube authorization request.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Google returned an invalid token response.');
    }
    final json = Map<String, Object?>.from(decoded);
    final accessToken = _nonEmpty(json['access_token']);
    final refreshToken = _nonEmpty(json['refresh_token']) ?? '';
    final expiresIn = _positiveInt(json['expires_in']);
    if (accessToken == null || expiresIn == null) {
      throw const FormatException('Google token response was incomplete.');
    }
    return YouTubeOAuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: _clock().toUtc().add(Duration(seconds: expiresIn)),
    );
  }

  static Future<YouTubeOAuthHttpResponse> _sendRequest(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    String? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      headers.forEach((name, value) => request.headers.set(name, value));
      if (body != null) {
        request.write(body);
      }
      final response = await request.close();
      return YouTubeOAuthHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decodeStream(response),
      );
    } finally {
      client.close(force: true);
    }
  }
}

List<String> _normalizeScopes(Iterable<String> scopes) {
  final unique = <String>{};
  for (final scope in scopes) {
    final normalized = scope.trim();
    if (normalized.isNotEmpty) {
      unique.add(normalized);
    }
  }
  return List<String>.unmodifiable(unique);
}

String _randomUrlSafeString(Random random, int byteCount) {
  final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String? _nonEmpty(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

int? _positiveInt(Object? value) {
  final parsed = switch (value) {
    num number => number.toInt(),
    _ => int.tryParse(value?.toString() ?? ''),
  };
  return parsed == null || parsed <= 0 ? null : parsed;
}
