import 'package:aethertune/src/data/youtube_oauth_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds the RFC PKCE S256 challenge', () {
    expect(
      youtubePkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('creates a desktop authorization URL with offline PKCE consent', () {
    final request = YouTubeAuthorizationRequest.create(
      clientId: 'client-id.apps.googleusercontent.com',
      redirectUri: Uri.parse('http://127.0.0.1:45678/youtube-callback'),
      scopes: const <String>[
        'https://www.googleapis.com/auth/youtube.readonly',
        ' https://www.googleapis.com/auth/youtube.readonly ',
      ],
    );

    expect(request.codeVerifier.length, inInclusiveRange(43, 128));
    expect(request.uri.host, 'accounts.google.com');
    expect(request.uri.queryParameters['response_type'], 'code');
    expect(request.uri.queryParameters['access_type'], 'offline');
    expect(request.uri.queryParameters['prompt'], 'consent');
    expect(request.uri.queryParameters['state'], request.state);
    expect(request.uri.queryParameters['code_challenge'], request.codeChallenge);
    expect(
      request.uri.queryParameters['scope'],
      'https://www.googleapis.com/auth/youtube.readonly',
    );
  });

  test('rejects an empty scope list and non-loopback callbacks', () {
    expect(
      () => YouTubeAuthorizationRequest.create(
        clientId: 'client-id',
        redirectUri: Uri.parse('http://127.0.0.1:45678/youtube-callback'),
        scopes: const <String>[],
      ),
      throwsFormatException,
    );
    expect(
      () => YouTubeAuthorizationRequest.create(
        clientId: 'client-id',
        redirectUri: Uri.parse('https://example.test/callback'),
        scopes: const <String>['scope'],
      ),
      throwsFormatException,
    );
  });

  test('exchanges a code without embedding a client secret', () async {
    String? requestBody;
    final client = YouTubeOAuthClient(
      clock: () => DateTime.utc(2026, 7, 24, 12),
      request: (uri, {required method, required headers, body}) async {
        expect(uri, YouTubeOAuthClient.tokenUri);
        expect(method, 'POST');
        expect(headers['content-type'], 'application/x-www-form-urlencoded');
        requestBody = body;
        return const YouTubeOAuthHttpResponse(
          statusCode: 200,
          body:
              '{"access_token":"access","refresh_token":"refresh","expires_in":3600}',
        );
      },
    );
    final authorization = YouTubeAuthorizationRequest.create(
      clientId: 'client-id.apps.googleusercontent.com',
      redirectUri: Uri.parse('http://127.0.0.1:45678/youtube-callback'),
      scopes: const <String>['https://www.googleapis.com/auth/youtube.readonly'],
    );

    final token = await client.exchangeAuthorizationCode(
      authorization: authorization,
      code: 'returned-code',
    );

    final values = Uri.splitQueryString(requestBody!);
    expect(values['grant_type'], 'authorization_code');
    expect(values['client_id'], 'client-id.apps.googleusercontent.com');
    expect(values['code_verifier'], authorization.codeVerifier);
    expect(values.containsKey('client_secret'), isFalse);
    expect(token.expiresAt, DateTime.utc(2026, 7, 24, 13));
  });

  test('retains the old refresh token when Google omits a replacement',
      () async {
    final client = YouTubeOAuthClient(
      clock: () => DateTime.utc(2026, 7, 24, 12),
      request: (uri, {required method, required headers, body}) async =>
          const YouTubeOAuthHttpResponse(
            statusCode: 200,
            body: '{"access_token":"next-access","expires_in":1800}',
          ),
    );

    final token = await client.refresh(
      clientId: 'client-id.apps.googleusercontent.com',
      current: YouTubeOAuthToken(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: DateTime.utc(2026, 7, 24, 12),
      ),
    );

    expect(token.accessToken, 'next-access');
    expect(token.refreshToken, 'old-refresh');
  });
}
