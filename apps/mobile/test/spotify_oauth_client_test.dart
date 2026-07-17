import 'package:aethertune/src/data/spotify_oauth_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds the RFC PKCE S256 challenge', () {
    expect(
      spotifyPkceChallenge(
        'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
      ),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('creates an authorization URL with state, PKCE, and loopback callback', () {
    final request = SpotifyAuthorizationRequest.create(
      clientId: 'client-id',
      redirectUri: Uri.parse('http://127.0.0.1:45678/spotify-callback'),
    );

    expect(request.codeVerifier.length, inInclusiveRange(43, 128));
    expect(request.uri.host, 'accounts.spotify.com');
    expect(request.uri.queryParameters['response_type'], 'code');
    expect(request.uri.queryParameters['client_id'], 'client-id');
    expect(
      request.uri.queryParameters['redirect_uri'],
      'http://127.0.0.1:45678/spotify-callback',
    );
    expect(request.uri.queryParameters['state'], request.state);
    expect(request.uri.queryParameters['code_challenge'], request.codeChallenge);
  });

  test('deduplicates and requests explicit Spotify OAuth scopes', () {
    final request = SpotifyAuthorizationRequest.create(
      clientId: 'client-id',
      redirectUri: Uri.parse('http://127.0.0.1:45678/spotify-callback'),
      scopes: const <String>[
        'user-library-read',
        ' user-library-read ',
        '',
      ],
    );

    expect(request.scopes, const <String>['user-library-read']);
    expect(request.uri.queryParameters['scope'], 'user-library-read');
  });

  test('exchanges a code without a client secret', () async {
    String? requestBody;
    Map<String, String>? capturedHeaders;
    final client = SpotifyOAuthClient(
      clock: () => DateTime.utc(2026, 7, 17, 12),
      request: (uri, {
        required method,
        required headers,
        String? body,
      }) async {
        expect(uri, SpotifyOAuthClient.tokenUri);
        expect(method, 'POST');
        capturedHeaders = headers;
        requestBody = body;
        return const SpotifyHttpResponse(
          statusCode: 200,
          body: '{"access_token":"access","refresh_token":"refresh","expires_in":3600}',
        );
      },
    );
    final authorization = SpotifyAuthorizationRequest.create(
      clientId: 'client-id',
      redirectUri: Uri.parse('http://127.0.0.1:45678/spotify-callback'),
    );

    final token = await client.exchangeAuthorizationCode(
      authorization: authorization,
      code: 'returned-code',
    );

    final values = Uri.splitQueryString(requestBody!);
    expect(
      capturedHeaders!['content-type'],
      'application/x-www-form-urlencoded',
    );
    expect(values['grant_type'], 'authorization_code');
    expect(values['client_id'], 'client-id');
    expect(values['code'], 'returned-code');
    expect(values['code_verifier'], authorization.codeVerifier);
    expect(values.containsKey('client_secret'), isFalse);
    expect(token.accessToken, 'access');
    expect(token.refreshToken, 'refresh');
    expect(token.expiresAt, DateTime.utc(2026, 7, 17, 13));
  });

  test('retains the old refresh token when Spotify omits a replacement', () async {
    final client = SpotifyOAuthClient(
      clock: () => DateTime.utc(2026, 7, 17, 12),
      request: (uri, {required method, required headers, body}) async =>
          const SpotifyHttpResponse(
            statusCode: 200,
            body: '{"access_token":"next-access","expires_in":1800}',
          ),
    );

    final token = await client.refresh(
      clientId: 'client-id',
      current: SpotifyOAuthToken(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresAt: DateTime.utc(2026, 7, 17, 12),
      ),
    );

    expect(token.accessToken, 'next-access');
    expect(token.refreshToken, 'old-refresh');
  });
}
