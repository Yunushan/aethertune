import 'package:aethertune/src/data/youtube_oauth_client.dart';
import 'package:aethertune/src/data/youtube_oauth_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final authorization = YouTubeAuthorizationRequest.create(
    clientId: 'client-id.apps.googleusercontent.com',
    redirectUri: Uri.parse('http://127.0.0.1:45678/youtube-callback'),
    scopes: const <String>['https://www.googleapis.com/auth/youtube.readonly'],
  );

  test('accepts an authorization callback with the matching state', () {
    final callback = parseYouTubeAuthorizationCallback(
      Uri.parse(
        'http://127.0.0.1:45678/youtube-callback?'
        'code=returned-code&state=${authorization.state}',
      ),
      authorization,
    );

    expect(callback.code, 'returned-code');
  });

  test('rejects an authorization callback with a different state', () {
    expect(
      () => parseYouTubeAuthorizationCallback(
        Uri.parse(
          'http://127.0.0.1:45678/youtube-callback?'
          'code=returned-code&state=wrong-state',
        ),
        authorization,
      ),
      throwsFormatException,
    );
  });

  test('surfaces a declined authorization callback', () {
    expect(
      () => parseYouTubeAuthorizationCallback(
        Uri.parse(
          'http://127.0.0.1:45678/youtube-callback?'
          'error=access_denied&state=${authorization.state}',
        ),
        authorization,
      ),
      throwsFormatException,
    );
  });
}
