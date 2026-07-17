import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'spotify_oauth_client.dart';

typedef SpotifyAuthorizationLauncher = Future<bool> Function(Uri uri);

final class SpotifyOAuthFlow {
  SpotifyOAuthFlow({
    required SpotifyOAuthClient oauthClient,
    SpotifyAuthorizationLauncher? authorizationLauncher,
    this.callbackTimeout = const Duration(minutes: 3),
  }) : _oauthClient = oauthClient,
       _authorizationLauncher = authorizationLauncher ?? _launchAuthorization;

  final SpotifyOAuthClient _oauthClient;
  final SpotifyAuthorizationLauncher _authorizationLauncher;
  final Duration callbackTimeout;

  Future<SpotifyOAuthToken> authorize(String clientId) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final authorization = SpotifyAuthorizationRequest.create(
        clientId: clientId,
        redirectUri: Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          path: '/spotify-callback',
        ),
      );
      final launched = await _authorizationLauncher(authorization.uri);
      if (!launched) {
        throw StateError('Could not open the Spotify authorization page.');
      }
      final callback = await _waitForCallback(server, authorization);
      return _oauthClient.exchangeAuthorizationCode(
        authorization: authorization,
        code: callback.code,
      );
    } finally {
      await server.close(force: true);
    }
  }

  Future<SpotifyAuthorizationCallback> _waitForCallback(
    HttpServer server,
    SpotifyAuthorizationRequest authorization,
  ) async {
    await for (final request in server.timeout(callbackTimeout)) {
      if (request.uri.path != authorization.redirectUri.path) {
        await _respond(request, HttpStatus.notFound, 'Not found.');
        continue;
      }
      try {
        final callback = parseSpotifyAuthorizationCallback(
          request.uri,
          authorization,
        );
        await _respond(
          request,
          HttpStatus.ok,
          'Spotify authorization completed. You can return to AetherTune.',
        );
        return callback;
      } on FormatException catch (error) {
        await _respond(request, HttpStatus.badRequest, error.message);
        rethrow;
      }
    }
    throw StateError('Spotify authorization did not return a callback.');
  }

  static Future<void> _respond(
    HttpRequest request,
    int statusCode,
    String message,
  ) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.text;
    request.response.write(message);
    await request.response.close();
  }

  static Future<bool> _launchAuthorization(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

final class SpotifyAuthorizationCallback {
  const SpotifyAuthorizationCallback({required this.code});

  final String code;
}

SpotifyAuthorizationCallback parseSpotifyAuthorizationCallback(
  Uri callback,
  SpotifyAuthorizationRequest authorization,
) {
  final state = callback.queryParameters['state']?.trim();
  if (state == null || state != authorization.state) {
    throw const FormatException('Spotify authorization state did not match.');
  }
  final error = callback.queryParameters['error']?.trim();
  if (error != null && error.isNotEmpty) {
    throw FormatException('Spotify authorization was declined: $error.');
  }
  final code = callback.queryParameters['code']?.trim();
  if (code == null || code.isEmpty) {
    throw const FormatException('Spotify did not return an authorization code.');
  }
  return SpotifyAuthorizationCallback(code: code);
}
