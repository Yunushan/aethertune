import 'dart:convert';

import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/data/youtube_account_settings_store.dart';
import 'package:aethertune/src/data/youtube_oauth_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores a desktop YouTube session only in the credential vault', () async {
    final vault = _MemoryVault();
    final store = YouTubeAccountSettingsStore(
      credentialVault: vault,
      platform: TargetPlatform.windows,
      authorizationRunner: (_) async => _token('access', 'refresh'),
    );

    await store.connect(' desktop-client ');

    expect(store.isConfigured, isTrue);
    expect(store.clientId, 'desktop-client');
    expect(store.accountProvider, isNotNull);
    final saved = jsonDecode(vault.values['youtube-oauth-session']!) as Map;
    expect(saved['clientId'], 'desktop-client');
    expect(saved['accessToken'], 'access');
  });

  test('refreshes an expired account token and persists the replacement', () async {
    final vault = _MemoryVault()
      ..values['youtube-oauth-session'] = jsonEncode(
        YouTubeOAuthSession(
          clientId: 'desktop-client',
          token: YouTubeOAuthToken(
            accessToken: 'old-access',
            refreshToken: 'old-refresh',
            expiresAt: DateTime.utc(2026, 7, 17, 11),
          ),
        ).toJson(),
      );
    final store = YouTubeAccountSettingsStore(
      credentialVault: vault,
      platform: TargetPlatform.linux,
      clock: () => DateTime.utc(2026, 7, 17, 12),
      oauthClient: YouTubeOAuthClient(
        clock: () => DateTime.utc(2026, 7, 17, 12),
        request: (uri, {required method, required headers, String? body}) async {
          expect(uri, YouTubeOAuthClient.tokenUri);
          expect(method, 'POST');
          expect(Uri.splitQueryString(body!)['grant_type'], 'refresh_token');
          return const YouTubeOAuthHttpResponse(
            statusCode: 200,
            body: '{"access_token":"next-access","expires_in":86400}',
          );
        },
      ),
    );
    await store.load();

    expect(await store.readAccessToken(), 'next-access');
    final saved = jsonDecode(vault.values['youtube-oauth-session']!) as Map;
    expect(saved['accessToken'], 'next-access');
    expect(saved['refreshToken'], 'old-refresh');
  });

  test('does not expose desktop OAuth account access on mobile', () async {
    final store = YouTubeAccountSettingsStore(
      credentialVault: _MemoryVault(),
      platform: TargetPlatform.android,
    );

    await expectLater(store.connect('desktop-client'), throwsStateError);

    expect(store.desktopOAuthSupported, isFalse);
    expect(store.accountProvider, isNull);
  });

  test('disconnect removes the secure YouTube session', () async {
    final vault = _MemoryVault();
    final store = YouTubeAccountSettingsStore(
      credentialVault: vault,
      platform: TargetPlatform.macOS,
      authorizationRunner: (_) async => _token('access', 'refresh'),
    );
    await store.connect('desktop-client');

    await store.remove();

    expect(store.isConfigured, isFalse);
    expect(vault.values, isEmpty);
    expect(store.accountProvider, isNull);
  });
}

YouTubeOAuthToken _token(String accessToken, String refreshToken) {
  return YouTubeOAuthToken(
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
