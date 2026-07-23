import 'package:aethertune/src/data/listenbrainz_client.dart';
import 'package:aethertune/src/data/listenbrainz_scrobbling_store.dart';
import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

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

  test('persists a failed listen with only submission metadata and retries it',
      () async {
    final vault = _MemoryVault();
    final failedClient = _FakeListenBrainzClient(failNextSubmission: true);
    final startedAt = DateTime.utc(2026, 7, 17, 12);
    final failed = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => failedClient,
      clock: () => DateTime.utc(2026, 7, 18),
    );
    await failed.configure('token');
    await failed.submitIfEligible(
      track: Track(
        id: 'private-track-id',
        title: 'Signal',
        artist: 'Aether',
        album: 'Vault',
        duration: const Duration(minutes: 2),
        localPath: '/private/music/signal.mp3',
        streamUrl: 'https://secret.example.test/stream',
      ),
      startedAt: startedAt,
      position: const Duration(minutes: 1),
    );
    expect(failed.pendingListenCount, 1);

    final retryClient = _FakeListenBrainzClient();
    final restored = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => retryClient,
      clock: () => DateTime.utc(2026, 7, 18),
    );
    await restored.load();
    expect(restored.pendingListenCount, 1);

    expect(await restored.retryPendingListens(), 1);
    expect(restored.pendingListenCount, 0);
    expect(retryClient.submitted.single.track.title, 'Signal');
    expect(retryClient.submitted.single.track.artist, 'Aether');
    expect(retryClient.submitted.single.track.album, 'Vault');
    expect(retryClient.submitted.single.track.localPath, isNull);
    expect(retryClient.submitted.single.track.streamUrl, isNull);
  });

  test('keeps background retry opt-in separate and clears it on disconnect',
      () async {
    final vault = _MemoryVault();
    final store = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => _FakeListenBrainzClient(),
    );

    await store.load();
    expect(store.backgroundRetryEnabled, isFalse);
    await expectLater(
      store.setBackgroundRetryEnabled(true),
      throwsA(isA<StateError>()),
    );

    await store.configure('token');
    await store.setBackgroundRetryEnabled(true);
    expect(store.backgroundRetryEnabled, isTrue);

    final restored = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => _FakeListenBrainzClient(),
    );
    await restored.load();
    expect(restored.backgroundRetryEnabled, isTrue);

    await restored.remove();
    expect(restored.backgroundRetryEnabled, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'aethertune.listenbrainz.background-retry.v1',
      ),
      isNull,
    );
  });

  test('background retry policy needs opt-in and every privacy gate', () {
    bool eligible({
      bool isConfigured = true,
      bool backgroundRetryEnabled = true,
      bool hasPendingListens = true,
      bool offlineModeEnabled = false,
      bool pauseListeningHistory = false,
    }) {
      return shouldRetryListenBrainzInBackground(
        isConfigured: isConfigured,
        backgroundRetryEnabled: backgroundRetryEnabled,
        hasPendingListens: hasPendingListens,
        offlineModeEnabled: offlineModeEnabled,
        pauseListeningHistory: pauseListeningHistory,
      );
    }

    expect(eligible(), isTrue);
    expect(eligible(isConfigured: false), isFalse);
    expect(eligible(backgroundRetryEnabled: false), isFalse);
    expect(eligible(hasPendingListens: false), isFalse);
    expect(eligible(offlineModeEnabled: true), isFalse);
    expect(eligible(pauseListeningHistory: true), isFalse);
  });

  test('loading an opted-in queue does not submit it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.listenbrainz.background-retry.v1': true,
      'aethertune.listenbrainz.pending.v1': '''
{"version":1,"listens":[
  {"title":"Signal","artist":"Aether","durationMs":120000,"startedAt":"2026-07-17T12:00:00.000Z"}
]}
''',
    });
    final client = _FakeListenBrainzClient();
    final store = ListenBrainzScrobblingStore(
      credentialVault: _MemoryVault()
        ..values['listenbrainz-user-token'] = 'token',
      clientFactory: (_) => client,
      clock: () => DateTime.utc(2026, 7, 18),
    );

    await store.load();

    expect(store.backgroundRetryEnabled, isTrue);
    expect(store.pendingListenCount, 1);
    expect(client.submitted, isEmpty);
  });

  test('drops expired pending listens during load', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.listenbrainz.pending.v1': '''
{"version":1,"listens":[
  {"title":"Old","artist":"Aether","durationMs":1000,"startedAt":"2026-06-01T00:00:00.000Z"},
  {"title":"Fresh","artist":"Aether","durationMs":1000,"startedAt":"2026-07-17T00:00:00.000Z"}
]}
''',
    });
    final store = ListenBrainzScrobblingStore(
      credentialVault: _MemoryVault(),
      clientFactory: (_) => _FakeListenBrainzClient(),
      clock: () => DateTime.utc(2026, 7, 18),
    );

    await store.load();

    expect(store.pendingListenCount, 1);
  });

  test('reads history through the configured account without exposing its token',
      () async {
    final client = _FakeListenBrainzClient(
      validUserName: 'yunus',
      historyEntries: <ListenBrainzHistoryEntry>[
        ListenBrainzHistoryEntry(
          title: 'Satellite',
          artist: 'Aether',
          listenedAt: DateTime.utc(2026, 7, 18, 12),
        ),
      ],
    );
    final store = ListenBrainzScrobblingStore(
      credentialVault: _MemoryVault(),
      clientFactory: (_) => client,
    );
    await store.configure('token');

    final history = await store.fetchListenHistory();

    expect(history.single.title, 'Satellite');
    expect(client.requestedUserName, 'yunus');
    expect(client.requestedHistoryCount, 100);
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
  _FakeListenBrainzClient({
    this.validUserName,
    this.failNextSubmission = false,
    this.historyEntries = const <ListenBrainzHistoryEntry>[],
  })
    : super(token: 'test-token');

  final String? validUserName;
  bool failNextSubmission;
  int validateCalls = 0;
  final List<ListenBrainzHistoryEntry> historyEntries;
  final List<_SubmittedListen> submitted = <_SubmittedListen>[];
  String? requestedUserName;
  int? requestedHistoryCount;

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

  @override
  Future<List<ListenBrainzHistoryEntry>> fetchListenHistory({
    required String userName,
    int count = 100,
    DateTime? before,
  }) async {
    requestedUserName = userName;
    requestedHistoryCount = count;
    return historyEntries;
  }
}
