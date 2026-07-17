import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

final class SpotifyHttpResponse {
  const SpotifyHttpResponse({required this.statusCode, this.body = ''});

  final int statusCode;
  final String body;
}

typedef SpotifyHttpRequest = Future<SpotifyHttpResponse> Function(
  Uri uri, {
  required String method,
  required Map<String, String> headers,
  String? body,
});

final class SpotifyOAuthToken {
  const SpotifyOAuthToken({
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

  static SpotifyOAuthToken? tryFromJson(Map<String, Object?> json) {
    final accessToken = _nonEmpty(json['accessToken']);
    final refreshToken = _nonEmpty(json['refreshToken']);
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (accessToken == null || refreshToken == null || expiresAt == null) {
      return null;
    }
    return SpotifyOAuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt.toUtc(),
    );
  }
}

final class SpotifyAuthorizationRequest {
  SpotifyAuthorizationRequest({
    required this.clientId,
    required this.redirectUri,
    required this.state,
    required this.codeVerifier,
  }) : codeChallenge = spotifyPkceChallenge(codeVerifier);

  final String clientId;
  final Uri redirectUri;
  final String state;
  final String codeVerifier;
  final String codeChallenge;

  Uri get uri => Uri.https('accounts.spotify.com', '/authorize', <String, String>{
    'client_id': clientId,
    'response_type': 'code',
    'redirect_uri': redirectUri.toString(),
    'state': state,
    'code_challenge_method': 'S256',
    'code_challenge': codeChallenge,
  });

  static SpotifyAuthorizationRequest create({
    required String clientId,
    required Uri redirectUri,
    Random? random,
  }) {
    final normalizedClientId = clientId.trim();
    if (normalizedClientId.isEmpty) {
      throw const FormatException('Enter a Spotify developer client ID.');
    }
    if (redirectUri.scheme != 'http' || redirectUri.host != '127.0.0.1') {
      throw const FormatException('Spotify requires a 127.0.0.1 callback URL.');
    }
    final source = random ?? Random.secure();
    return SpotifyAuthorizationRequest(
      clientId: normalizedClientId,
      redirectUri: redirectUri,
      state: _randomUrlSafeString(source, 32),
      codeVerifier: _randomUrlSafeString(source, 64),
    );
  }
}

String spotifyPkceChallenge(String verifier) {
  final normalized = verifier.trim();
  if (normalized.length < 43 || normalized.length > 128) {
    throw const FormatException('Spotify PKCE verifier has an invalid length.');
  }
  return base64UrlEncode(sha256.convert(utf8.encode(normalized)).bytes)
      .replaceAll('=', '');
}

final class SpotifyOAuthClient {
  SpotifyOAuthClient({
    SpotifyHttpRequest? request,
    DateTime Function()? clock,
  }) : _request = request ?? _sendRequest,
       _clock = clock ?? DateTime.now;

  static final Uri tokenUri =
      Uri.parse('https://accounts.spotify.com/api/token');

  final SpotifyHttpRequest _request;
  final DateTime Function() _clock;

  Future<SpotifyOAuthToken> exchangeAuthorizationCode({
    required SpotifyAuthorizationRequest authorization,
    required String code,
  }) {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) {
      throw const FormatException('Spotify did not return an authorization code.');
    }
    return _requestToken(<String, String>{
      'client_id': authorization.clientId,
      'grant_type': 'authorization_code',
      'code': normalizedCode,
      'redirect_uri': authorization.redirectUri.toString(),
      'code_verifier': authorization.codeVerifier,
    });
  }

  Future<SpotifyOAuthToken> refresh({
    required String clientId,
    required SpotifyOAuthToken current,
  }) async {
    final refreshed = await _requestToken(<String, String>{
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': current.refreshToken,
    });
    return SpotifyOAuthToken(
      accessToken: refreshed.accessToken,
      refreshToken: refreshed.refreshToken.isEmpty
          ? current.refreshToken
          : refreshed.refreshToken,
      expiresAt: refreshed.expiresAt,
    );
  }

  Future<SpotifyOAuthToken> _requestToken(Map<String, String> values) async {
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
      throw StateError('Spotify rejected the authorization request.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Spotify returned an invalid token response.');
    }
    final json = Map<String, Object?>.from(decoded);
    final accessToken = _nonEmpty(json['access_token']);
    final refreshToken = _nonEmpty(json['refresh_token']) ?? '';
    final expiresIn = _positiveInt(json['expires_in']);
    if (accessToken == null || expiresIn == null) {
      throw const FormatException('Spotify token response was incomplete.');
    }
    return SpotifyOAuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: _clock().toUtc().add(Duration(seconds: expiresIn)),
    );
  }

  static Future<SpotifyHttpResponse> _sendRequest(
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
      return SpotifyHttpResponse(
        statusCode: response.statusCode,
        body: await utf8.decodeStream(response),
      );
    } finally {
      client.close(force: true);
    }
  }
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
