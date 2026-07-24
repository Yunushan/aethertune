import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'youtube_oauth_client.dart';

typedef YouTubeAuthorizationLauncher = Future<bool> Function(Uri uri);

/// Desktop-only loopback OAuth flow for a user-owned Google OAuth client.
final class YouTubeOAuthFlow {
  YouTubeOAuthFlow({
    required YouTubeOAuthClient oauthClient,
    YouTubeAuthorizationLauncher? authorizationLauncher,
    this.callbackTimeout = const Duration(minutes: 3),
  }) : _oauthClient = oauthClient,
       _authorizationLauncher = authorizationLauncher ?? _launchAuthorization;

  final YouTubeOAuthClient _oauthClient;
  final YouTubeAuthorizationLauncher _authorizationLauncher;
  final Duration callbackTimeout;

  Future<YouTubeOAuthToken> authorize(
    String clientId, {
    required Iterable<String> scopes,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final authorization = YouTubeAuthorizationRequest.create(
        clientId: clientId,
        redirectUri: Uri(
          scheme: 'http',
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          path: '/youtube-callback',
        ),
        scopes: scopes,
      );
      final launched = await _authorizationLauncher(authorization.uri);
      if (!launched) {
        throw StateError('Could not open the Google authorization page.');
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

  Future<YouTubeAuthorizationCallback> _waitForCallback(
    HttpServer server,
    YouTubeAuthorizationRequest authorization,
  ) async {
    await for (final request in server.timeout(callbackTimeout)) {
      if (request.uri.path != authorization.redirectUri.path) {
        await _respond(request, HttpStatus.notFound, 'Not found.');
        continue;
      }
      try {
        final callback = parseYouTubeAuthorizationCallback(
          request.uri,
          authorization,
        );
        await _respond(
          request,
          HttpStatus.ok,
          'YouTube authorization completed. You can return to AetherTune.',
        );
        return callback;
      } on FormatException catch (error) {
        await _respond(request, HttpStatus.badRequest, error.message);
        rethrow;
      }
    }
    throw StateError('YouTube authorization did not return a callback.');
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

final class YouTubeAuthorizationCallback {
  const YouTubeAuthorizationCallback({required this.code});

  final String code;
}

YouTubeAuthorizationCallback parseYouTubeAuthorizationCallback(
  Uri callback,
  YouTubeAuthorizationRequest authorization,
) {
  final state = callback.queryParameters['state']?.trim();
  if (state == null || state != authorization.state) {
    throw const FormatException('YouTube authorization state did not match.');
  }
  final error = callback.queryParameters['error']?.trim();
  if (error != null && error.isNotEmpty) {
    throw FormatException('YouTube authorization was declined: $error.');
  }
  final code = callback.queryParameters['code']?.trim();
  if (code == null || code.isEmpty) {
    throw const FormatException('Google did not return an authorization code.');
  }
  return YouTubeAuthorizationCallback(code: code);
}
