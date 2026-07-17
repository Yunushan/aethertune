import 'package:aethertune/src/data/listenbrainz_client.dart';
import 'package:aethertune/src/data/listenbrainz_scrobbling_store.dart';
import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configures only a validated token in the credential vault', () async {
    final vault = _MemoryVault();
    final client = _FakeListenBrainzClient(validUserName: 'yunus');
    final store = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
    );

    await store.configure(' token ');

    expect(store.isConfigured, isTrue);
    expect(store.userName, 'yunus');
    expect(vault.values['listenbrainz-user-token'], 'token');
    expect(client.validateCalls, 1);
  });

  test('submits once only after the ListenBrainz completion threshold', () async {
    final client = _FakeListenBrainzClient();
    final store = ListenBrainzScrobblingStore(
      credentialVault: _MemoryVault(),
      clientFactory: (_) => client,
    );
    await store.configure('token');
    final track = Track(
      id: 'track-1',
      title: 'Signal',
      artist: 'Aether',
      duration: const Duration(minutes: 10),
    );
    final startedAt = DateTime.utc(2026, 7, 17, 12);

    await store.submitIfEligible(
      track: track,
      startedAt: startedAt,
      position: const Duration(minutes: 3, seconds: 59),
    );
    await store.submitIfEligible(
      track: track,
      startedAt: startedAt,
      position: const Duration(minutes: 4),
    );
    await store.submitIfEligible(
      track: track,
      startedAt: startedAt,
      position: const Duration(minutes: 5),
    );

    expect(client.submitted, hasLength(1));
    expect(client.submitted.single.track.id, 'track-1');
    expect(client.submitted.single.startedAt, startedAt);
  });

  test('allows a later position update to retry a failed submission', () async {
    final client = _FakeListenBrainzClient(failNextSubmission: true);
    final store = ListenBrainzScrobblingStore(
      credentialVault: _MemoryVault(),
      clientFactory: (_) => client,
    );
    await store.configure('token');
    final track = Track(
      id: 'track-1',
      title: 'Signal',
      artist: 'Aether',
      duration: const Duration(minutes: 2),
    );
    final startedAt = DateTime.utc(2026, 7, 17, 12);

    await store.submitIfEligible(
      track: track,
      startedAt: startedAt,
      position: const Duration(minutes: 1),
    );
    expect(store.lastError, isNotNull);
    await store.submitIfEligible(
      track: track,
      startedAt: startedAt,
      position: const Duration(minutes: 1, seconds: 10),
    );

    expect(client.submitted, hasLength(1));
    expect(store.lastError, isNull);
  });

  test('uses the shorter of half the track and four minutes', () {
    expect(
      ListenBrainzScrobblingStore.completionThreshold(
        const Duration(minutes: 3),
      ),
      const Duration(minutes: 1, seconds: 30),
    );
    expect(
      ListenBrainzScrobblingStore.completionThreshold(
        const Duration(minutes: 12),
      ),
      const Duration(minutes: 4),
    );
  });
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

final class _SubmittedListen {
  const _SubmittedListen({required this.track, required this.startedAt});

  final Track track;
  final DateTime startedAt;
}

final class _FakeListenBrainzClient extends ListenBrainzClient {
  _FakeListenBrainzClient({this.validUserName, this.failNextSubmission = false})
    : super(token: 'test-token');

  final String? validUserName;
  bool failNextSubmission;
  int validateCalls = 0;
  final List<_SubmittedListen> submitted = <_SubmittedListen>[];

  @override
  Future<String?> validateToken() async {
    validateCalls += 1;
    return validUserName;
  }

  @override
  Future<void> submitListen({
    required Track track,
    required DateTime startedAt,
  }) async {
    if (failNextSubmission) {
      failNextSubmission = false;
      throw StateError('network failed');
    }
    submitted.add(_SubmittedListen(track: track, startedAt: startedAt));
  }
}
