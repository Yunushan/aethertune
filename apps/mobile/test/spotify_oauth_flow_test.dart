import 'package:aethertune/src/data/spotify_oauth_client.dart';
import 'package:aethertune/src/data/spotify_oauth_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final authorization = SpotifyAuthorizationRequest.create(
    clientId: 'client-id',
    redirectUri: Uri.parse('http://127.0.0.1:45678/spotify-callback'),
  );

  test('accepts an authorization callback with the matching state', () {
    final callback = parseSpotifyAuthorizationCallback(
      Uri.parse(
        'http://127.0.0.1:45678/spotify-callback?'
        'code=returned-code&state=${authorization.state}',
      ),
      authorization,
    );

    expect(callback.code, 'returned-code');
  });

  test('rejects an authorization callback with a different state', () {
    expect(
      () => parseSpotifyAuthorizationCallback(
        Uri.parse(
          'http://127.0.0.1:45678/spotify-callback?'
          'code=returned-code&state=wrong-state',
        ),
        authorization,
      ),
      throwsFormatException,
    );
  });

  test('surfaces a declined authorization callback', () {
    expect(
      () => parseSpotifyAuthorizationCallback(
        Uri.parse(
          'http://127.0.0.1:45678/spotify-callback?'
          'error=access_denied&state=${authorization.state}',
        ),
        authorization,
      ),
      throwsFormatException,
    );
  });
}
