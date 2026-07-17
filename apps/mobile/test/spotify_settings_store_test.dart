import 'dart:convert';

import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/data/spotify_oauth_client.dart';
import 'package:aethertune/src/data/spotify_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores an authorized Spotify session only in the credential vault', () async {
    final vault = _MemoryVault();
    final store = SpotifySettingsStore(
      credentialVault: vault,
      authorizationRunner: (_) async => _token('access', 'refresh'),
    );

    await store.connect(' client-id ');

    expect(store.isConfigured, isTrue);
    expect(store.clientId, 'client-id');
    final saved = jsonDecode(vault.values['spotify-oauth-session']!) as Map;
    expect(saved['clientId'], 'client-id');
    expect(saved['accessToken'], 'access');
    expect(store.musicProviders.single.id, 'spotify-metadata');
  });

  test('refreshes an expired token and atomically persists the replacement', () async {
    final vault = _MemoryVault()
      ..values['spotify-oauth-session'] = jsonEncode(
        SpotifyOAuthSession(
          clientId: 'client-id',
          token: SpotifyOAuthToken(
            accessToken: 'old-access',
            refreshToken: 'old-refresh',
            expiresAt: DateTime.utc(2026, 7, 17, 11),
          ),
        ).toJson(),
      );
    var refreshCalls = 0;
    final store = SpotifySettingsStore(
      credentialVault: vault,
      oauthClient: SpotifyOAuthClient(
        clock: () => DateTime.utc(2026, 7, 17, 12),
        request: (uri, {
          required method,
          required headers,
          String? body,
        }) async {
          refreshCalls += 1;
          expect(uri, SpotifyOAuthClient.tokenUri);
          expect(method, 'POST');
          expect(Uri.splitQueryString(body!)['grant_type'], 'refresh_token');
          return const SpotifyHttpResponse(
            statusCode: 200,
            body: '{"access_token":"next-access","expires_in":86400}',
          );
        },
      ),
      clock: () => DateTime.utc(2026, 7, 17, 12),
    );
    await store.load();

    expect(await store.readAccessToken(), 'next-access');
    expect(refreshCalls, 1);
    final saved = jsonDecode(vault.values['spotify-oauth-session']!) as Map;
    expect(saved['accessToken'], 'next-access');
    expect(saved['refreshToken'], 'old-refresh');
  });

  test('disconnect removes the secure session and provider', () async {
    final vault = _MemoryVault();
    final store = SpotifySettingsStore(
      credentialVault: vault,
      authorizationRunner: (_) async => _token('access', 'refresh'),
    );
    await store.connect('client-id');

    await store.remove();

    expect(store.isConfigured, isFalse);
    expect(vault.values, isEmpty);
    expect(store.musicProviders, isEmpty);
  });
}

SpotifyOAuthToken _token(String accessToken, String refreshToken) {
  return SpotifyOAuthToken(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: DateTime.utc(2026, 7, 18),
  );
}

final class _MemoryVault implements ProviderCredentialVault {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String accountId) async {
    values.remove(accountId);
  }

  @override
  Future<String?> read(String accountId) async => values[accountId];

  @override
  Future<void> write(String accountId, String secret) async {
    values[accountId] = secret;
  }
}
