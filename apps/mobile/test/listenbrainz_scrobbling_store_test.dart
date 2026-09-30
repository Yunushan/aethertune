import 'dart:async';

import 'package:aethertune/src/data/listenbrainz_client.dart';
import 'package:aethertune/src/data/listenbrainz_scrobbling_store.dart';
import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _pendingKey = 'aethertune.listenbrainz.pending.v1';
const _backgroundRetryKey = 'aethertune.listenbrainz.background-retry.v1';

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
    await expectLater(store.configure('different-token'), throwsStateError);
    expect(vault.values['listenbrainz-user-token'], 'token');
  });

  test('disconnect follows an in-flight same-account validation', () async {
    final vault = _MemoryVault();
    final validating = Completer<void>();
    final releaseValidation = Completer<void>();
    final client = _FakeListenBrainzClient(validUserName: 'yunus');
    final store = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
    );
    addTearDown(store.dispose);
    await store.configure('token');
    client.beforeValidate = () async {
      validating.complete();
      await releaseValidation.future;
    };

    final configuring = store.configure('token');
    await validating.future;
    final disconnecting = store.remove();
    releaseValidation.complete();
    await configuring;
    await disconnecting;

    expect(store.isConfigured, isFalse);
    expect(store.userName, isNull);
    expect(vault.values['listenbrainz-user-token'], isNull);
  });

  test(
    'same-token revalidation preserves in-flight submission dedup',
    () async {
      final submitting = Completer<void>();
      final releaseSubmission = Completer<void>();
      var pauseNextSubmission = true;
      final client = _FakeListenBrainzClient(validUserName: 'yunus')
        ..beforeSubmit = (_) async {
          if (!pauseNextSubmission) return;
          pauseNextSubmission = false;
          submitting.complete();
          await releaseSubmission.future;
        };
      final store = ListenBrainzScrobblingStore(
        credentialVault: _MemoryVault(),
        clientFactory: (_) => client,
      );
      addTearDown(store.dispose);
      await store.configure('token');
      final track = Track(
        id: 'same-token-revalidation',
        title: 'Signal',
        artist: 'Aether',
        duration: const Duration(minutes: 2),
      );
      final startedAt = DateTime.utc(2026, 9, 23, 12);

      final first = store.submitIfEligible(
        track: track,
        startedAt: startedAt,
        position: const Duration(minutes: 2),
      );
      await submitting.future;
      await store.configure('token');
      releaseSubmission.complete();
      await first;
      await store.submitIfEligible(
        track: track,
        startedAt: startedAt,
        position: const Duration(minutes: 2),
      );

      expect(client.submitted, hasLength(1));
      expect(store.pendingListenCount, 0);
    },
  );

  test(
    'a delayed startup vault read cannot overwrite later credentials',
    () async {
      final vault = _MemoryVault()
        ..values['listenbrainz-user-token'] = 'old-token';
      final reading = Completer<void>();
      final releaseRead = Completer<void>();
      vault.readOverride = (_) async {
        reading.complete();
        await releaseRead.future;
        return 'old-token';
      };
      final store = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => _FakeListenBrainzClient(validUserName: 'yunus'),
      );
      addTearDown(store.dispose);

      final loading = store.load();
      await reading.future;
      final disconnecting = store.remove();
      final configuring = store.configure('new-token');
      releaseRead.complete();
      await loading;
      await disconnecting;
      await configuring;

      expect(store.loaded, isTrue);
      expect(store.isConfigured, isTrue);
      expect(vault.values['listenbrainz-user-token'], 'new-token');
      expect(store.userName, 'yunus');
    },
  );

  test(
    'submits once only after the ListenBrainz completion threshold',
    () async {
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
    },
  );

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

  test(
    'persists a failed listen with only submission metadata and retries it',
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
    },
  );

  test(
    'rejected queue write cannot publish a phantom pending listen',
    () async {
      final backend = _RejectingPreferences();
      SharedPreferencesStorePlatform.instance = backend;
      final vault = _MemoryVault();
      final client = _FakeListenBrainzClient(failNextSubmission: true);
      final store = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => client,
        clock: () => DateTime.utc(2026, 9, 23),
      );
      await store.configure('token');
      final track = Track(
        id: 'private-track-id',
        title: 'Signal',
        artist: 'Aether',
        duration: const Duration(minutes: 2),
      );
      final startedAt = DateTime.utc(2026, 9, 22, 12);

      backend.rejectWrites = true;
      await store.submitIfEligible(
        track: track,
        startedAt: startedAt,
        position: const Duration(minutes: 1),
      );
      expect(store.pendingListenCount, 0);
      expect(store.lastError, contains('could not be saved'));
      expect(
        (await SharedPreferences.getInstance()).getString(_pendingKey),
        isNull,
      );

      final reopened = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => client,
        clock: () => DateTime.utc(2026, 9, 23),
      );
      await reopened.load();
      expect(reopened.pendingListenCount, 0);

      backend.rejectWrites = false;
      client.failNextSubmission = true;
      await store.submitIfEligible(
        track: track,
        startedAt: startedAt,
        position: const Duration(minutes: 1),
      );
      expect(store.pendingListenCount, 1);
      final restored = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => client,
        clock: () => DateTime.utc(2026, 9, 23),
      );
      await restored.load();
      expect(restored.pendingListenCount, 1);
    },
  );

  test('rejected retry save retains the durable queue', () async {
    final backend = _RejectingPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final vault = _MemoryVault();
    final client = _FakeListenBrainzClient(failNextSubmission: true);
    final store = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
      clock: () => DateTime.utc(2026, 9, 23),
    );
    await store.configure('token');
    await store.submitIfEligible(
      track: Track(
        id: 'track-1',
        title: 'Signal',
        artist: 'Aether',
        duration: const Duration(minutes: 2),
      ),
      startedAt: DateTime.utc(2026, 9, 22, 12),
      position: const Duration(minutes: 1),
    );
    expect(store.pendingListenCount, 1);

    backend.rejectWrites = true;
    expect(await store.retryPendingListens(), 1);
    expect(client.submitted, hasLength(1));
    expect(store.pendingListenCount, 1);
    expect(store.lastError, contains('could not be saved'));
    final reopened = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
      clock: () => DateTime.utc(2026, 9, 23),
    );
    await reopened.load();
    expect(reopened.pendingListenCount, 1);

    backend.rejectWrites = false;
    expect(await store.retryPendingListens(), 0);
    expect(client.submitted, hasLength(1));
    expect(store.pendingListenCount, 0);
    final restored = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
      clock: () => DateTime.utc(2026, 9, 23),
    );
    await restored.load();
    expect(restored.pendingListenCount, 0);
  });

  test(
    'rejected retry opt-in changes leave durable consent unchanged',
    () async {
      final backend = _RejectingPreferences();
      SharedPreferencesStorePlatform.instance = backend;
      final vault = _MemoryVault();
      final store = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => _FakeListenBrainzClient(),
      );
      await store.configure('token');

      backend.rejectWrites = true;
      await expectLater(
        store.setBackgroundRetryEnabled(true),
        throwsStateError,
      );
      expect(store.backgroundRetryEnabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(_backgroundRetryKey),
        isNull,
      );

      backend.rejectWrites = false;
      await store.setBackgroundRetryEnabled(true);
      backend.rejectWrites = true;
      await expectLater(
        store.setBackgroundRetryEnabled(false),
        throwsStateError,
      );
      expect(store.backgroundRetryEnabled, isTrue);
      final reopened = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => _FakeListenBrainzClient(),
      );
      await reopened.load();
      expect(reopened.backgroundRetryEnabled, isTrue);
    },
  );

  test('rejected disconnect cleanup blocks orphaned queue reuse', () async {
    final backend = _RejectingPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final vault = _MemoryVault();
    final client = _FakeListenBrainzClient(failNextSubmission: true);
    final store = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
      clock: () => DateTime.utc(2026, 9, 23),
    );
    await store.configure('old-token');
    await store.submitIfEligible(
      track: Track(
        id: 'private-track-id',
        title: 'Signal',
        artist: 'Aether',
        duration: const Duration(minutes: 2),
      ),
      startedAt: DateTime.utc(2026, 9, 22, 12),
      position: const Duration(minutes: 1),
    );
    await store.setBackgroundRetryEnabled(true);

    backend.rejectRemovals = true;
    await expectLater(store.remove(), throwsStateError);
    expect(store.isConfigured, isFalse);
    expect(store.pendingListenCount, 1);
    expect(store.backgroundRetryEnabled, isFalse);
    expect(store.lastError, contains('could not be removed'));
    expect(vault.values, isEmpty);
    final reopened = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
      clock: () => DateTime.utc(2026, 9, 23),
    );
    await reopened.load();
    expect(reopened.isConfigured, isFalse);
    expect(reopened.pendingListenCount, 1);
    expect(reopened.backgroundRetryEnabled, isFalse);
    await expectLater(reopened.configure('new-token'), throwsStateError);
    expect(reopened.isConfigured, isFalse);

    backend.rejectRemovals = false;
    await reopened.configure('new-token');
    expect(reopened.isConfigured, isTrue);
    expect(reopened.pendingListenCount, 0);
    expect(reopened.backgroundRetryEnabled, isFalse);
    final restored = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
      clock: () => DateTime.utc(2026, 9, 23),
    );
    await restored.load();
    expect(restored.pendingListenCount, 0);
    expect(restored.backgroundRetryEnabled, isFalse);
    expect(client.submitted, isEmpty);
  });

  test(
    'in-flight submission cannot recreate a queue after disconnect',
    () async {
      final backend = _RejectingPreferences();
      SharedPreferencesStorePlatform.instance = backend;
      final vault = _MemoryVault();
      final client = _FakeListenBrainzClient();
      final started = Completer<void>();
      final release = Completer<void>();
      client.beforeSubmit = (_) {
        started.complete();
        return release.future;
      };
      final store = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => client,
        clock: () => DateTime.utc(2026, 9, 23),
      );
      await store.configure('token');

      final submission = store.submitIfEligible(
        track: Track(
          id: 'track-1',
          title: 'Signal',
          artist: 'Aether',
          duration: const Duration(minutes: 2),
        ),
        startedAt: DateTime.utc(2026, 9, 22, 12),
        position: const Duration(minutes: 1),
      );
      await started.future;
      await store.remove();
      release.complete();
      await submission;

      expect(store.isConfigured, isFalse);
      expect(store.pendingListenCount, 0);
      expect(
        (await SharedPreferences.getInstance()).getString(_pendingKey),
        isNull,
      );
      final reopened = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => client,
        clock: () => DateTime.utc(2026, 9, 23),
      );
      await reopened.load();
      expect(reopened.pendingListenCount, 0);
      expect(reopened.isConfigured, isFalse);
    },
  );

  test('overlapping failed listens both reach durable storage', () async {
    final backend = _RejectingPreferences();
    SharedPreferencesStorePlatform.instance = backend;
    final vault = _MemoryVault();
    final client = _FakeListenBrainzClient()..failAllSubmissions = true;
    final store = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
      clock: () => DateTime.utc(2026, 9, 23),
    );
    await store.configure('token');
    backend.pauseNextWrite();

    Future<void> submit(String id) => store.submitIfEligible(
      track: Track(
        id: id,
        title: id,
        artist: 'Aether',
        duration: const Duration(minutes: 2),
      ),
      startedAt: DateTime.utc(2026, 9, 22, 12),
      position: const Duration(minutes: 1),
    );

    final first = submit('First');
    await backend.writeStarted;
    final second = submit('Second');
    await Future<void>.delayed(Duration.zero);
    backend.resumeWrite();
    await Future.wait(<Future<void>>[first, second]);
    expect(store.pendingListenCount, 2);
    final reopened = ListenBrainzScrobblingStore(
      credentialVault: vault,
      clientFactory: (_) => client,
      clock: () => DateTime.utc(2026, 9, 23),
    );
    await reopened.load();
    expect(reopened.pendingListenCount, 2);
  });

  test(
    'submitting stays true until every overlapping listen finishes',
    () async {
      final client = _FakeListenBrainzClient()..failAllSubmissions = true;
      final secondStarted = Completer<void>();
      final releaseSecond = Completer<void>();
      client.beforeSubmit = (track) {
        if (track.id == 'Second') {
          secondStarted.complete();
          return releaseSecond.future;
        }
        return Future<void>.value();
      };
      final store = ListenBrainzScrobblingStore(
        credentialVault: _MemoryVault(),
        clientFactory: (_) => client,
        clock: () => DateTime.utc(2026, 9, 23),
      );
      await store.configure('token');

      Future<void> submit(String id) => store.submitIfEligible(
        track: Track(
          id: id,
          title: id,
          artist: 'Aether',
          duration: const Duration(minutes: 2),
        ),
        startedAt: DateTime.utc(2026, 9, 22, 12),
        position: const Duration(minutes: 1),
      );

      final second = submit('Second');
      await secondStarted.future;
      await submit('First');
      expect(store.submitting, isTrue);
      expect(await store.retryPendingListens(), 0);
      releaseSecond.complete();
      await second;
      expect(store.submitting, isFalse);
      expect(store.pendingListenCount, 2);
    },
  );

  test(
    'keeps background retry opt-in separate and clears it on disconnect',
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
    },
  );

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

  test(
    'reads history through the configured account without exposing its token',
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
    },
  );

  test(
    'stopping retries persists the in-flight success but does not submit the next listen',
    () async {
      final vault = _MemoryVault();
      final client = _FakeListenBrainzClient();
      final store = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => client,
      );
      addTearDown(store.dispose);
      await store.configure('token');
      for (var index = 0; index < 2; index++) {
        client.failNextSubmission = true;
        await store.submitIfEligible(
          track: Track(
            id: 'stop-$index',
            title: 'Stop $index',
            artist: 'Fixture',
            duration: const Duration(minutes: 2),
          ),
          startedAt: DateTime.now().subtract(Duration(minutes: index + 3)),
          position: const Duration(minutes: 1),
        );
      }
      expect(store.pendingListenCount, 2);
      var running = true;
      client.onSubmit = () {
        running = false;
      };
      expect(await store.retryPendingListens(shouldContinue: () => running), 1);
      expect(client.submitted, hasLength(1));
      final reopened = ListenBrainzScrobblingStore(
        credentialVault: vault,
        clientFactory: (_) => client,
      );
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.pendingListenCount, 1);
      expect(
        await reopened.retryPendingListens(shouldContinue: () => false),
        0,
      );
      expect(client.submitted, hasLength(1));
    },
  );

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
  Future<String?> Function(String)? readOverride;

  @override
  Future<void> delete(String accountId) async {
    values.remove(accountId);
  }

  @override
  Future<String?> read(String accountId) async {
    final override = readOverride;
    if (override != null) return override(accountId);
    return values[accountId];
  }

  @override
  Future<void> write(String accountId, String secret) async {
    values[accountId] = secret;
  }
}

final class _RejectingPreferences extends InMemorySharedPreferencesStore {
  _RejectingPreferences() : super.empty();

  bool rejectWrites = false;
  bool rejectRemovals = false;
  Completer<void>? _pausedWrite;
  Completer<void>? _writeStarted;

  Future<void> get writeStarted => _writeStarted!.future;

  void pauseNextWrite() {
    _pausedWrite = Completer<void>();
    _writeStarted = Completer<void>();
  }

  void resumeWrite() => _pausedWrite?.complete();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (rejectWrites) return false;
    final pause = _pausedWrite;
    if (pause != null) {
      _writeStarted?.complete();
      await pause.future;
      _pausedWrite = null;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (rejectRemovals) return false;
    return super.remove(key);
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
  }) : super(token: 'test-token');

  final String? validUserName;
  bool failNextSubmission;
  bool failAllSubmissions = false;
  int validateCalls = 0;
  final List<ListenBrainzHistoryEntry> historyEntries;
  final List<_SubmittedListen> submitted = <_SubmittedListen>[];
  String? requestedUserName;
  int? requestedHistoryCount;
  void Function()? onSubmit;
  Future<void> Function()? beforeValidate;
  Future<void> Function(Track)? beforeSubmit;

  @override
  Future<String?> validateToken() async {
    validateCalls += 1;
    final before = beforeValidate;
    if (before != null) await before();
    return validUserName;
  }

  @override
  Future<void> submitListen({
    required Track track,
    required DateTime startedAt,
  }) async {
    final before = beforeSubmit;
    if (before != null) await before(track);
    if (failAllSubmissions || failNextSubmission) {
      failNextSubmission = false;
      throw StateError('network failed');
    }
    submitted.add(_SubmittedListen(track: track, startedAt: startedAt));
    onSubmit?.call();
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
