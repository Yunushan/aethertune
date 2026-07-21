import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aethertune_server/server.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('AetherTune server', () {
    test('uses a loopback listener unless an explicit IP is configured', () {
      expect(serverListenAddress(null).address, '127.0.0.1');
      expect(serverListenAddress('  ').address, '127.0.0.1');
      expect(serverListenAddress('0.0.0.0').address, '0.0.0.0');
      expect(serverListenAddress('::1').address, '::1');
      expect(
        () => serverListenAddress('sync.example.com'),
        throwsA(isA<FormatException>()),
      );
    });

    test('health endpoint reports ok', () async {
      final handler = createServerHandler(
        clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final response = await handler(_request('GET', '/health'));
      final body = await _json(response);

      expect(response.statusCode, 200);
      expect(body['status'], 'ok');
      expect(body['service'], 'aethertune-server');
      expect(body['timestamp'], '2026-01-02T03:04:05.000Z');
    });

    test('parses a strict server request-rate limit configuration', () {
      expect(
        serverRequestRateLimiterFromEnvironment(
          const <String, String>{'AETHERTUNE_RATE_LIMIT_PER_MINUTE': '7'},
        ).maximumRequests,
        7,
      );
      expect(
        () => serverRequestRateLimiterFromEnvironment(
          const <String, String>{'AETHERTUNE_RATE_LIMIT_PER_MINUTE': '0'},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rate limits without exposing bearer tokens', () async {
      var now = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final handler = createServerHandler(
        clock: () => now,
        requestRateLimiter: ServerRequestRateLimiter(
          maximumRequests: 2,
          window: const Duration(minutes: 1),
          clock: () => now,
        ),
      );

      expect((await handler(_request('GET', '/health', token: 'private'))).statusCode, 200);
      expect((await handler(_request('GET', '/health', token: 'private'))).statusCode, 200);
      final limited = await handler(_request('GET', '/health', token: 'private'));

      expect(limited.statusCode, 429);
      expect(limited.headers['retry-after'], '60');
      expect((await _json(limited))['error'], 'rate_limited');
      now = now.add(const Duration(minutes: 1));
      expect((await handler(_request('GET', '/health', token: 'private'))).statusCode, 200);
    });

    test('bounds rate-limit buckets under distinct-token traffic', () async {
      final handler = createServerHandler(
        requestRateLimiter: ServerRequestRateLimiter(
          maximumRequests: 10,
          maximumBuckets: 1,
        ),
      );
      expect((await handler(_request('GET', '/health', token: 'one'))).statusCode, 200);
      expect((await handler(_request('GET', '/health', token: 'two'))).statusCode, 429);
    });

    test('metrics reports aggregate process state without request details',
        () async {
      var current = DateTime.utc(2026, 1, 2, 3, 4, 5);
      final handler = createServerHandler(
        clock: () => current,
        syncAuthenticator: StaticSyncAuthenticator(
          const <String, String>{'yunus': 'test-token'},
        ),
      );

      await handler(_request('GET', '/health'));
      current = current.add(const Duration(seconds: 65));
      final response = await handler(_request('GET', '/api/v1/metrics'));
      final body = await _json(response);

      expect(response.statusCode, 200);
      expect(body['service'], 'aethertune-server');
      expect(body['startedAt'], '2026-01-02T03:04:05.000Z');
      expect(body['uptimeSeconds'], 65);
      expect(body['requestsTotal'], 2);
      expect(body['librarySync'], isTrue);
      expect(
        body.keys,
        containsAll(<String>[
          'service',
          'startedAt',
          'uptimeSeconds',
          'requestsTotal',
          'librarySync',
        ]),
      );
      expect(jsonEncode(body), isNot(contains('yunus')));
      expect(jsonEncode(body), isNot(contains('test-token')));
    });

    test('metrics supports constant-time raw and digest bearer protection',
        () async {
      const token = 'private-operations-token';
      final rawHandler = createServerHandler(
        operationsAuthenticator: StaticOperationsAuthenticator(token),
      );

      final missing = await rawHandler(_request('GET', '/api/v1/metrics'));
      final rejected = await rawHandler(
        _request('GET', '/api/v1/metrics', token: 'wrong-token'),
      );
      final accepted = await rawHandler(
        _request('GET', '/api/v1/metrics', token: token),
      );

      expect(missing.statusCode, 401);
      expect(missing.headers['www-authenticate'], 'Bearer');
      expect(rejected.statusCode, 401);
      expect(await rejected.readAsString(), isNot(contains('wrong-token')));
      expect(accepted.statusCode, 200);
      expect((await _json(accepted))['requestsTotal'], 3);

      final digest = sha256.convert(utf8.encode(token)).toString();
      final digestHandler = createServerHandler(
        operationsAuthenticator:
            StaticOperationsAuthenticator('sha256:$digest'),
      );
      expect(
        (await digestHandler(
          _request('GET', '/api/v1/metrics', token: token),
        ))
            .statusCode,
        200,
      );
      expect(
        () => StaticOperationsAuthenticator('sha256:not-a-digest'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => StaticOperationsAuthenticator('   '),
        throwsA(isA<FormatException>()),
      );
    });

    test('writes safe structured request logs without disrupting requests',
        () async {
      final entries = <ServerRequestLogEntry>[];
      final handler = createServerHandler(
        clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
        requestLogger: entries.add,
      );

      final tracks = await handler(
        _request(
          'GET',
          '/api/v1/tracks?q=private-search&token=query-secret',
          token: 'header-secret',
        ),
      );
      final missing = await handler(
        _request('POST', '/private-path/embedded-secret'),
      );

      expect(tracks.statusCode, 200);
      expect(missing.statusCode, 404);
      expect(entries, hasLength(2));
      expect(entries[0].toJson(), <String, Object?>{
        'timestamp': '2026-01-02T03:04:05.000Z',
        'method': 'GET',
        'route': '/api/v1/tracks',
        'statusCode': 200,
        'durationMilliseconds': 0,
      });
      expect(entries[1].route, '/not-found');
      final logs = jsonEncode(entries.map((entry) => entry.toJson()).toList());
      expect(logs, isNot(contains('private-search')));
      expect(logs, isNot(contains('query-secret')));
      expect(logs, isNot(contains('header-secret')));
      expect(logs, isNot(contains('embedded-secret')));

      final failureTolerant = createServerHandler(
        requestLogger: (_) => throw StateError('logger failure'),
      );
      expect(
        (await failureTolerant(_request('GET', '/health'))).statusCode,
        200,
      );
    });

    test('info endpoint lists clients and sync availability', () async {
      final unavailable = await createServerHandler()(
        _request('GET', '/api/v1/info'),
      );
      final unavailableBody = await _json(unavailable);
      expect(unavailableBody['librarySync'], isFalse);

      final configured = await createServerHandler(
        syncAuthenticator: StaticSyncAuthenticator(
          const <String, String>{'yunus': 'test-token'},
        ),
      )(_request('GET', '/api/v1/info'));
      final body = await _json(configured);

      expect(configured.statusCode, 200);
      expect(body['name'], 'AetherTune');
      expect(body['librarySync'], isTrue);
      expect(
        body['supportedClients'],
        containsAll(<String>['android', 'ios', 'linux', 'macos', 'windows']),
      );
    });

    test('tracks endpoint filters catalog entries', () async {
      final response = await createServerHandler()(
        _request('GET', '/api/v1/tracks?q=radio'),
      );
      final body = await _json(response);
      final tracks = body['tracks'] as List<dynamic>;

      expect(response.statusCode, 200);
      expect(tracks, hasLength(1));
      expect((tracks.single as Map<String, dynamic>)['id'], 'open-catalogs');
    });

    test('unsupported methods and paths return JSON errors', () async {
      final handler = createServerHandler();
      final methodResponse = await handler(_request('POST', '/health'));
      final methodBody = await _json(methodResponse);
      final missingResponse = await handler(_request('GET', '/missing'));
      final missingBody = await _json(missingResponse);

      expect(methodResponse.statusCode, 405);
      expect(methodBody['error'], 'method_not_allowed');
      expect(methodBody['method'], 'POST');
      expect(missingResponse.statusCode, 404);
      expect(missingBody['error'], 'not_found');
      expect(missingBody['path'], '/missing');
    });
  });

  group('authenticated library sync', () {
    const token = 'library-sync-secret';
    late StaticSyncAuthenticator authenticator;
    late MemoryLibrarySyncSnapshotStore store;

    setUp(() {
      authenticator = StaticSyncAuthenticator(
        const <String, String>{'yunus': token},
      );
      store = MemoryLibrarySyncSnapshotStore();
    });

    test('stays unavailable until server users are configured', () async {
      final response = await createServerHandler()(
        _request('GET', '/api/v1/sync/library'),
      );

      expect(response.statusCode, 503);
      expect((await _json(response))['error'], 'sync_not_configured');
    });

    test('rejects missing and invalid bearer tokens without echoing them',
        () async {
      final handler = createServerHandler(
        syncAuthenticator: authenticator,
        syncStore: store,
      );
      final missing = await handler(
        _request('GET', '/api/v1/sync/library'),
      );
      const rejected = 'wrong-private-token';
      final invalid = await handler(
        _request(
          'GET',
          '/api/v1/sync/library',
          token: rejected,
        ),
      );
      final invalidText = await invalid.readAsString();

      expect(missing.statusCode, 401);
      expect(missing.headers['www-authenticate'], 'Bearer');
      expect(invalid.statusCode, 401);
      expect(invalidText, contains('unauthorized'));
      expect(invalidText, isNot(contains(rejected)));
    });

    test('uploads and downloads a versioned checksum-verified snapshot',
        () async {
      final handler = createServerHandler(
        clock: () => DateTime.utc(2026, 7, 10, 12, 30),
        syncAuthenticator: authenticator,
        syncStore: store,
      );
      final empty = await handler(
        _request('GET', '/api/v1/sync/library', token: token),
      );
      final emptyBody = await _json(empty);
      expect(empty.statusCode, 200);
      expect(emptyBody['revision'], 0);
      expect(emptyBody['snapshot'], isNull);

      final snapshot = _syncSnapshot(title: 'First device library');
      final uploaded = await handler(
        _request(
          'PUT',
          '/api/v1/sync/library',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'android-phone',
            'snapshot': snapshot,
          },
        ),
      );
      final uploadBody = await _json(uploaded);

      expect(uploaded.statusCode, 200);
      expect(uploadBody['revision'], 1);
      expect(uploadBody['updatedAt'], '2026-07-10T12:30:00.000Z');
      expect(uploadBody['updatedByDevice'], 'android-phone');
      expect(uploadBody['checksum'], hasLength(64));

      final metadata = await handler(
        _request('GET', '/api/v1/sync/library/metadata', token: token),
      );
      final metadataBody = await _json(metadata);
      expect(metadata.statusCode, 200);
      expect(metadataBody['revision'], 1);
      expect(metadataBody['checksum'], uploadBody['checksum']);
      expect(metadataBody, isNot(contains('snapshot')));

      final downloaded = await handler(
        _request('GET', '/api/v1/sync/library', token: token),
      );
      final downloadBody = await _json(downloaded);
      expect(downloaded.statusCode, 200);
      expect(downloadBody['revision'], 1);
      expect(downloadBody['checksum'], uploadBody['checksum']);
      expect(downloadBody['snapshot'], snapshot);
      expect(jsonEncode(downloadBody), isNot(contains(token)));
    });

    test('detects stale revisions without overwriting the current snapshot',
        () async {
      final handler = createServerHandler(
        clock: () => DateTime.utc(2026, 7, 10, 13),
        syncAuthenticator: authenticator,
        syncStore: store,
      );
      await handler(
        _request(
          'PUT',
          '/api/v1/sync/library',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'phone',
            'snapshot': _syncSnapshot(title: 'Phone copy'),
          },
        ),
      );

      final conflict = await handler(
        _request(
          'PUT',
          '/api/v1/sync/library',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'desktop',
            'snapshot': _syncSnapshot(title: 'Stale desktop copy'),
          },
        ),
      );
      final conflictBody = await _json(conflict);

      expect(conflict.statusCode, 409);
      expect(conflictBody['error'], 'sync_conflict');
      expect(conflictBody['currentRevision'], 1);
      expect(conflictBody['updatedByDevice'], 'phone');

      final current = await handler(
        _request('GET', '/api/v1/sync/library', token: token),
      );
      final currentBody = await _json(current);
      final currentSnapshot = currentBody['snapshot'] as Map<String, dynamic>;
      expect(currentSnapshot['name'], 'Phone copy');

      final resolved = await handler(
        _request(
          'PUT',
          '/api/v1/sync/library',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 1,
            'deviceId': 'desktop',
            'snapshot': _syncSnapshot(title: 'Chosen desktop copy'),
          },
        ),
      );
      expect(resolved.statusCode, 200);
      expect((await _json(resolved))['revision'], 2);
    });

    test('deletes a snapshot as a revisioned tombstone', () async {
      final handler = createServerHandler(
        clock: () => DateTime.utc(2026, 7, 10, 14),
        syncAuthenticator: authenticator,
        syncStore: store,
      );
      final uploaded = await handler(
        _request(
          'PUT',
          '/api/v1/sync/library',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'phone',
            'snapshot': _syncSnapshot(),
          },
        ),
      );
      expect(uploaded.statusCode, 200);

      final deleted = await handler(
        _request(
          'DELETE',
          '/api/v1/sync/library',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 1,
            'deviceId': 'desktop',
          },
        ),
      );
      final deletedBody = await _json(deleted);
      expect(deleted.statusCode, 200);
      expect(deletedBody['revision'], 2);
      expect(deletedBody['checksum'], isNull);
      expect(deletedBody['updatedByDevice'], 'desktop');

      final fetched = await handler(
        _request('GET', '/api/v1/sync/library', token: token),
      );
      final fetchedBody = await _json(fetched);
      expect(fetched.statusCode, 200);
      expect(fetchedBody['revision'], 2);
      expect(fetchedBody['snapshot'], isNull);
      expect(fetchedBody['checksum'], isNull);

      final staleWrite = await handler(
        _request(
          'PUT',
          '/api/v1/sync/library',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 1,
            'deviceId': 'phone',
            'snapshot': _syncSnapshot(title: 'Stale copy'),
          },
        ),
      );
      final staleBody = await _json(staleWrite);
      expect(staleWrite.statusCode, 409);
      expect(staleBody['currentRevision'], 2);
      expect(staleBody['checksum'], isNull);
    });

    test('rejects local paths, device cache jobs, and oversized requests',
        () async {
      final handler = createServerHandler(
        syncAuthenticator: authenticator,
        syncStore: store,
      );
      final localPath = await handler(
        _request(
          'PUT',
          '/api/v1/sync/library',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'phone',
            'snapshot': _syncSnapshot(localPath: '/private/music/song.mp3'),
          },
        ),
      );
      expect(localPath.statusCode, 400);
      expect(
        (await _json(localPath))['message'],
        contains('local file paths'),
      );

      final cacheJobs = _syncSnapshot();
      cacheJobs['offlineCacheQueue'] = <Object?>[
        <String, Object?>{'id': 'private-cache-job'},
      ];
      final offlineQueue = await handler(
        _request(
          'PUT',
          '/api/v1/sync/library',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'phone',
            'snapshot': cacheJobs,
          },
        ),
      );
      expect(offlineQueue.statusCode, 400);
      expect((await _json(offlineQueue))['message'], contains('cache jobs'));

      final oversized = await handler(
        Request(
          'PUT',
          Uri.parse('http://localhost/api/v1/sync/library'),
          headers: const <String, String>{
            'authorization': 'Bearer $token',
          },
          body: Stream<List<int>>.value(
            Uint8List(maxSyncSnapshotBytes + 1),
          ),
        ),
      );
      expect(oversized.statusCode, 413);
      expect((await _json(oversized))['error'], 'payload_too_large');
    });
  });

  group('authenticated listen-together sessions', () {
    const token = 'listen-together-secret';

    test('shares a portable revision-protected playback session', () async {
      final handler = createServerHandler(
        clock: () => DateTime.utc(2026, 7, 12, 10),
        syncAuthenticator: StaticSyncAuthenticator(
          const <String, String>{'friends': token},
        ),
        listenTogetherStore: MemoryLibrarySyncSnapshotStore(),
      );
      final empty = await handler(
        _request('GET', '/api/v1/listen-together/session', token: token),
      );
      final emptyBody = await _json(empty);
      expect(empty.statusCode, 200);
      expect(emptyBody['revision'], 0);
      expect(emptyBody['session'], isNull);

      final created = await handler(
        _request(
          'PUT',
          '/api/v1/listen-together/session',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'host-phone',
            'session': <String, Object?>{
              'version': 1,
              'trackIds': <String>['track-1', 'track-2'],
              'currentTrackId': 'track-1',
              'positionMilliseconds': 12345,
              'playing': true,
            },
          },
        ),
      );
      final createdBody = await _json(created);
      expect(created.statusCode, 200);
      expect(createdBody['revision'], 1);
      expect(createdBody['checksum'], hasLength(64));

      final joined = await handler(
        _request('GET', '/api/v1/listen-together/session', token: token),
      );
      final joinedBody = await _json(joined);
      expect(joinedBody['revision'], 1);
      expect((joinedBody['session'] as Map<String, dynamic>)['playing'], isTrue);

      final stale = await handler(
        _request(
          'PUT',
          '/api/v1/listen-together/session',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'guest-desktop',
            'session': <String, Object?>{
              'version': 1,
              'trackIds': <String>['track-1'],
              'currentTrackId': 'track-1',
              'positionMilliseconds': 0,
              'playing': false,
            },
          },
        ),
      );
      expect(stale.statusCode, 409);
      expect((await _json(stale))['error'], 'listen_together_conflict');
    });

    test('accepts a repeated v2 shared queue with its exact current index',
        () async {
      final handler = createServerHandler(
        syncAuthenticator: StaticSyncAuthenticator(
          const <String, String>{'friends': token},
        ),
        listenTogetherStore: MemoryLibrarySyncSnapshotStore(),
      );
      final response = await handler(
        _request(
          'PUT',
          '/api/v1/listen-together/session',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'host-phone',
            'session': <String, Object?>{
              'version': 2,
              'trackIds': <String>['track-1', 'track-2', 'track-1'],
              'currentTrackId': 'track-1',
              'currentIndex': 2,
              'positionMilliseconds': 12345,
              'playing': true,
            },
          },
        ),
      );

      expect(response.statusCode, 200);
      final fetched = await handler(
        _request('GET', '/api/v1/listen-together/session', token: token),
      );
      final body = await _json(fetched);
      expect(fetched.statusCode, 200);
      expect((body['session'] as Map<String, dynamic>)['trackIds'], <String>[
        'track-1',
        'track-2',
        'track-1',
      ]);
      expect((body['session'] as Map<String, dynamic>)['currentIndex'], 2);
    });

    test('rejects non-portable listen-together payloads', () async {
      final handler = createServerHandler(
        syncAuthenticator: StaticSyncAuthenticator(
          const <String, String>{'friends': token},
        ),
      );
      final rejected = await handler(
        _request(
          'PUT',
          '/api/v1/listen-together/session',
          token: token,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'host-phone',
            'session': <String, Object?>{
              'version': 1,
              'trackIds': <String>['track-1'],
              'currentTrackId': 'track-1',
              'positionMilliseconds': 0,
              'playing': false,
              'streamUrl': 'https://private.example.test/token',
            },
          },
        ),
      );
      expect(rejected.statusCode, 400);
      expect((await _json(rejected))['error'], 'invalid_listen_together_session');
    });

    test('lets a separately authenticated guest read a host invite', () async {
      const hostToken = 'host-secret';
      const guestToken = 'guest-secret';
      final handler = createServerHandler(
        syncAuthenticator: StaticSyncAuthenticator(
          const <String, String>{
            'host-account': hostToken,
            'guest-account': guestToken,
          },
        ),
        listenTogetherStore: MemoryLibrarySyncSnapshotStore(),
        listenTogetherInviteStore: MemoryListenTogetherInviteStore(),
      );
      final created = await handler(
        _request(
          'PUT',
          '/api/v1/listen-together/session',
          token: hostToken,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'host-phone',
            'session': <String, Object?>{
              'version': 1,
              'trackIds': <String>['track-1'],
              'currentTrackId': 'track-1',
              'positionMilliseconds': 5000,
              'playing': true,
            },
          },
        ),
      );
      expect(created.statusCode, 200);

      final issued = await handler(
        _request(
          'POST',
          '/api/v1/listen-together/session/invite',
          token: hostToken,
        ),
      );
      final inviteCode = (await _json(issued))['inviteCode'] as String;
      expect(issued.statusCode, 201);
      expect(inviteCode, matches(RegExp(r'^[A-Za-z0-9_-]{24}$')));

      final joined = await handler(
        _request(
          'GET',
          '/api/v1/listen-together/invites/$inviteCode',
          token: guestToken,
        ),
      );
      final joinedBody = await _json(joined);
      expect(joined.statusCode, 200);
      expect((joinedBody['session'] as Map<String, dynamic>)['currentTrackId'], 'track-1');
      expect(joinedBody.containsKey('host-account'), isFalse);

      final ended = await handler(
        _request(
          'DELETE',
          '/api/v1/listen-together/session',
          token: hostToken,
          jsonBody: <String, Object?>{
            'baseRevision': 1,
            'deviceId': 'host-phone',
          },
        ),
      );
      expect(ended.statusCode, 200);
      final restarted = await handler(
        _request(
          'PUT',
          '/api/v1/listen-together/session',
          token: hostToken,
          jsonBody: <String, Object?>{
            'baseRevision': 2,
            'deviceId': 'host-phone',
            'session': <String, Object?>{
              'version': 1,
              'trackIds': <String>['track-1'],
              'currentTrackId': 'track-1',
              'positionMilliseconds': 0,
              'playing': false,
            },
          },
        ),
      );
      expect(restarted.statusCode, 200);
      final expired = await handler(
        _request(
          'GET',
          '/api/v1/listen-together/invites/$inviteCode',
          token: guestToken,
        ),
      );
      expect(expired.statusCode, 404);
    });
  });

  test('file listen-together invites survive restart without storing raw codes',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'aethertune-server-invite-test-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final firstStore = FileListenTogetherInviteStore(root);
    final code = await firstStore.issue('host-account', 7);
    final restartedStore = FileListenTogetherInviteStore(root);

    final restored = await restartedStore.lookup(code);
    expect(restored?.ownerId, 'host-account');
    expect(restored?.sessionRevision, 7);
    expect(await restartedStore.lookup('not-an-invite'), isNull);
    final files = await root
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    expect(files, hasLength(1));
    expect(files.single.path, isNot(contains(code)));
  });

  test('file shared-playlist invites are consumed once without raw codes',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'aethertune-server-shared-invite-test-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final firstStore = FileSharedPlaylistInviteStore(root);
    final code = await firstStore.issue(
      playlistId: 'AAAAAAAAAAAAAAAAAAAAAAAA',
      role: SharedPlaylistRole.editor,
      expiresAt: DateTime.utc(2026, 7, 24),
    );
    final restartedStore = FileSharedPlaylistInviteStore(root);

    final consumed = await restartedStore.consume(code);

    expect(consumed?.playlistId, 'AAAAAAAAAAAAAAAAAAAAAAAA');
    expect(consumed?.role, SharedPlaylistRole.editor);
    expect(await restartedStore.lookup(code), isNull);
    final files = await root
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    expect(files, isEmpty);
  });

  test('file shared-playlist invite rotation keeps other playlists intact',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'aethertune-server-shared-rotate-test-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final store = FileSharedPlaylistInviteStore(root);
    final expiresAt = DateTime.utc(2026, 7, 24);
    final first = await store.issue(
      playlistId: 'AAAAAAAAAAAAAAAAAAAAAAAA',
      role: SharedPlaylistRole.viewer,
      expiresAt: expiresAt,
    );
    final second = await store.issue(
      playlistId: 'AAAAAAAAAAAAAAAAAAAAAAAA',
      role: SharedPlaylistRole.editor,
      expiresAt: expiresAt,
    );
    final other = await store.issue(
      playlistId: 'BBBBBBBBBBBBBBBBBBBBBBBB',
      role: SharedPlaylistRole.viewer,
      expiresAt: expiresAt,
    );

    expect(
      await store.invalidateForPlaylist('AAAAAAAAAAAAAAAAAAAAAAAA'),
      2,
    );
    expect(await store.lookup(first), isNull);
    expect(await store.lookup(second), isNull);
    expect((await store.lookup(other))?.playlistId, 'BBBBBBBBBBBBBBBBBBBBBBBB');
  });

  test('file shared-playlist history survives restart and retains 25 revisions',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'aethertune-server-shared-history-test-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final store = FileSharedPlaylistStore(root);
    const playlistId = 'AAAAAAAAAAAAAAAAAAAAAAAA';
    for (var revision = 0;
        revision <= maxSharedPlaylistHistoryEntries;
        revision += 1) {
      final result = await store.write(
        playlistId: playlistId,
        ownerId: 'owner-account',
        baseRevision: revision,
        deviceId: 'desktop',
        document: <String, Object?>{
          'version': 1,
          'name': 'Revision ${revision + 1}',
          'trackIds': <String>['track-$revision'],
        },
        collaborators: const <String, SharedPlaylistRole>{},
        publicShareSecretHash: null,
        updatedAt: DateTime.utc(2026, 7, 17, 12, revision),
      );
      expect(result.isConflict, isFalse);
    }

    final restarted = FileSharedPlaylistStore(root);
    final history = await restarted.readHistory(playlistId);

    expect(history, hasLength(maxSharedPlaylistHistoryEntries));
    expect(history.first.revision, maxSharedPlaylistHistoryEntries + 1);
    expect(history.last.revision, 2);
  });

  group('shared playlists', () {
    const ownerToken = 'shared-owner-token';
    const viewerToken = 'shared-viewer-token';
    const editorToken = 'shared-editor-token';

    Handler handler({DateTime Function()? clock}) => createServerHandler(
      clock: clock,
      syncAuthenticator: StaticSyncAuthenticator(
        const <String, String>{
          'owner-account': ownerToken,
          'viewer-account': viewerToken,
          'editor-account': editorToken,
        },
      ),
      sharedPlaylistStore: MemorySharedPlaylistStore(),
      sharedPlaylistInviteStore: MemorySharedPlaylistInviteStore(),
    );

    test('issues, rotates, and revokes anonymous smart-playlist links',
        () async {
      final server = handler();
      final created = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists',
          token: ownerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'owner-phone',
            'playlist': <String, Object?>{
              'version': 2,
              'kind': 'smart',
              'name': 'Rated favorites',
              'rule': <String, Object?>{
                'favoritesOnly': true,
                'limit': 25,
              },
            },
          },
        ),
      );
      expect(created.statusCode, 201);
      final playlistId = (await _json(created))['id'] as String;

      final issued = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists/$playlistId/public-link',
          token: ownerToken,
          jsonBody: const <String, Object?>{
            'baseRevision': 1,
            'deviceId': 'owner-phone',
          },
        ),
      );
      expect(issued.statusCode, 200);
      final firstSecret = (await _json(issued))['secret'] as String;
      expect(firstSecret, matches(RegExp(r'^[A-Za-z0-9_-]{24}$')));

      final anonymousRead = await server(
        _request(
          'GET',
          '/api/v1/public-smart-playlists/$playlistId/$firstSecret',
        ),
      );
      expect(anonymousRead.statusCode, 200);
      final anonymousBody = await _json(anonymousRead);
      expect((anonymousBody['playlist'] as Map)['name'], 'Rated favorites');
      expect(anonymousBody.containsKey('updatedByDevice'), isFalse);
      expect(anonymousBody.containsKey('ownerId'), isFalse);

      final rotated = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists/$playlistId/public-link',
          token: ownerToken,
          jsonBody: const <String, Object?>{
            'baseRevision': 2,
            'deviceId': 'owner-phone',
          },
        ),
      );
      expect(rotated.statusCode, 200);
      final secondSecret = (await _json(rotated))['secret'] as String;
      expect(secondSecret, isNot(firstSecret));
      final retiredRead = await server(
        _request(
          'GET',
          '/api/v1/public-smart-playlists/$playlistId/$firstSecret',
        ),
      );
      expect(retiredRead.statusCode, 404);

      final revoked = await server(
        _request(
          'DELETE',
          '/api/v1/shared-playlists/$playlistId/public-link',
          token: ownerToken,
          jsonBody: const <String, Object?>{
            'baseRevision': 3,
            'deviceId': 'owner-phone',
          },
        ),
      );
      expect(revoked.statusCode, 200);
      final revokedRead = await server(
        _request(
          'GET',
          '/api/v1/public-smart-playlists/$playlistId/$secondSecret',
        ),
      );
      expect(revokedRead.statusCode, 404);

      final manual = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists',
          token: ownerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'owner-phone',
            'playlist': <String, Object?>{
              'version': 1,
              'name': 'Private IDs',
              'trackIds': <String>['local-track'],
            },
          },
        ),
      );
      final manualId = (await _json(manual))['id'] as String;
      final rejectedManualLink = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists/$manualId/public-link',
          token: ownerToken,
          jsonBody: const <String, Object?>{
            'baseRevision': 1,
            'deviceId': 'owner-phone',
          },
        ),
      );
      expect(rejectedManualLink.statusCode, 400);
    });

    test('enforces authenticated viewer/editor invitations and revisions',
        () async {
      final server = handler();
      final created = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists',
          token: ownerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'owner-phone',
            'playlist': <String, Object?>{
              'version': 1,
              'name': 'Road trip',
              'trackIds': <String>['track-1', 'track-2'],
            },
          },
        ),
      );
      expect(created.statusCode, 201);
      final createdBody = await _json(created);
      final playlistId = createdBody['id'] as String;
      expect(playlistId, matches(RegExp(r'^[A-Za-z0-9_-]{24}$')));
      expect(createdBody['role'], 'owner');

      final viewerInvite = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists/$playlistId/invites',
          token: ownerToken,
          jsonBody: const <String, Object?>{'role': 'viewer'},
        ),
      );
      expect(viewerInvite.statusCode, 201);
      final viewerCode = (await _json(viewerInvite))['inviteCode'] as String;

      final viewerJoin = await server(
        _request(
          'POST',
          '/api/v1/shared-playlist-invites/$viewerCode',
          token: viewerToken,
        ),
      );
      expect(viewerJoin.statusCode, 200);
      expect((await _json(viewerJoin))['role'], 'viewer');

      final reusedViewerInvite = await server(
        _request(
          'POST',
          '/api/v1/shared-playlist-invites/$viewerCode',
          token: viewerToken,
        ),
      );
      expect(reusedViewerInvite.statusCode, 404);

      final viewerWrite = await server(
        _request(
          'PUT',
          '/api/v1/shared-playlists/$playlistId',
          token: viewerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 2,
            'deviceId': 'viewer-desktop',
            'playlist': <String, Object?>{
              'version': 1,
              'name': 'Changed',
              'trackIds': <String>['track-1'],
            },
          },
        ),
      );
      expect(viewerWrite.statusCode, 403);

      final viewerRevoke = await server(
        _request(
          'DELETE',
          '/api/v1/shared-playlists/$playlistId/collaborators/viewer-account',
          token: viewerToken,
          jsonBody: const <String, Object?>{
            'baseRevision': 2,
            'deviceId': 'viewer-desktop',
          },
        ),
      );
      expect(viewerRevoke.statusCode, 403);

      final editorInvite = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists/$playlistId/invites',
          token: ownerToken,
          jsonBody: const <String, Object?>{'role': 'editor'},
        ),
      );
      final editorCode = (await _json(editorInvite))['inviteCode'] as String;
      final editorJoin = await server(
        _request(
          'POST',
          '/api/v1/shared-playlist-invites/$editorCode',
          token: editorToken,
        ),
      );
      expect(editorJoin.statusCode, 200);
      expect((await _json(editorJoin))['role'], 'editor');

      final editorWrite = await server(
        _request(
          'PUT',
          '/api/v1/shared-playlists/$playlistId',
          token: editorToken,
          jsonBody: <String, Object?>{
            'baseRevision': 3,
            'deviceId': 'editor-desktop',
            'playlist': <String, Object?>{
              'version': 1,
              'name': 'Road trip updated',
              'trackIds': <String>['track-2', 'track-1', 'track-2'],
            },
          },
        ),
      );
      expect(editorWrite.statusCode, 200);
      expect((await _json(editorWrite))['revision'], 4);

      final staleOwnerWrite = await server(
        _request(
          'PUT',
          '/api/v1/shared-playlists/$playlistId',
          token: ownerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 3,
            'deviceId': 'owner-phone',
            'playlist': <String, Object?>{
              'version': 1,
              'name': 'Stale',
              'trackIds': <String>['track-1'],
            },
          },
        ),
      );
      expect(staleOwnerWrite.statusCode, 409);
      expect((await _json(staleOwnerWrite))['error'], 'shared_playlist_conflict');

      final ownerRead = await server(
        _request(
          'GET',
          '/api/v1/shared-playlists/$playlistId',
          token: ownerToken,
        ),
      );
      final ownerBody = await _json(ownerRead);
      expect(ownerRead.statusCode, 200);
      expect((ownerBody['playlist'] as Map)['name'], 'Road trip updated');
      expect((ownerBody['collaborators'] as Map)['viewer-account'], 'viewer');
      expect((ownerBody['collaborators'] as Map)['editor-account'], 'editor');

      final revokedEditor = await server(
        _request(
          'DELETE',
          '/api/v1/shared-playlists/$playlistId/collaborators/editor-account',
          token: ownerToken,
          jsonBody: const <String, Object?>{
            'baseRevision': 4,
            'deviceId': 'owner-phone',
          },
        ),
      );
      expect(revokedEditor.statusCode, 200);
      final revokedBody = await _json(revokedEditor);
      expect(revokedBody['revision'], 5);
      final remainingCollaborators = revokedBody['collaborators'] as Map;
      expect(remainingCollaborators['viewer-account'], 'viewer');
      expect(remainingCollaborators.containsKey('editor-account'), isFalse);

      final editorReadAfterRevocation = await server(
        _request(
          'GET',
          '/api/v1/shared-playlists/$playlistId',
          token: editorToken,
        ),
      );
      expect(editorReadAfterRevocation.statusCode, 404);

      final viewerHistory = await server(
        _request(
          'GET',
          '/api/v1/shared-playlists/$playlistId/revisions',
          token: viewerToken,
        ),
      );
      expect(viewerHistory.statusCode, 200);
      final revisions = (await _json(viewerHistory))['revisions'] as List;
      expect(
        revisions.map((value) => (value as Map)['revision']).toList(),
        <int>[5, 4, 3, 2, 1],
      );
      expect((revisions[1] as Map)['playlist'], isA<Map>());
    });

    test('expires unused invitations after the configured lifetime', () async {
      var now = DateTime.utc(2026, 7, 17, 12);
      final server = handler(clock: () => now);
      final created = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists',
          token: ownerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'owner-phone',
            'playlist': <String, Object?>{
              'version': 1,
              'name': 'Expiring invite',
              'trackIds': <String>['track-1'],
            },
          },
        ),
      );
      final playlistId = (await _json(created))['id'] as String;
      final issued = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists/$playlistId/invites',
          token: ownerToken,
          jsonBody: const <String, Object?>{'role': 'viewer'},
        ),
      );
      expect(issued.statusCode, 201);
      final issuedBody = await _json(issued);
      final inviteCode = issuedBody['inviteCode'] as String;
      expect(
        DateTime.parse(issuedBody['expiresAt'] as String).toUtc(),
        now.add(sharedPlaylistInviteLifetime),
      );

      now = now.add(sharedPlaylistInviteLifetime).add(const Duration(seconds: 1));
      final expired = await server(
        _request(
          'POST',
          '/api/v1/shared-playlist-invites/$inviteCode',
          token: viewerToken,
        ),
      );
      expect(expired.statusCode, 404);
    });

    test('owners can rotate every unused invitation code', () async {
      final server = handler();
      final created = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists',
          token: ownerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'owner-phone',
            'playlist': <String, Object?>{
              'version': 1,
              'name': 'Rotating invite',
              'trackIds': <String>['track-1'],
            },
          },
        ),
      );
      final playlistId = (await _json(created))['id'] as String;
      final viewerInvite = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists/$playlistId/invites',
          token: ownerToken,
          jsonBody: const <String, Object?>{'role': 'viewer'},
        ),
      );
      final editorInvite = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists/$playlistId/invites',
          token: ownerToken,
          jsonBody: const <String, Object?>{'role': 'editor'},
        ),
      );
      final viewerCode = (await _json(viewerInvite))['inviteCode'] as String;
      final editorCode = (await _json(editorInvite))['inviteCode'] as String;

      final rotated = await server(
        _request(
          'DELETE',
          '/api/v1/shared-playlists/$playlistId/invites',
          token: ownerToken,
        ),
      );
      expect(rotated.statusCode, 200);
      expect((await _json(rotated))['invalidated'], 2);

      final rejectedViewer = await server(
        _request(
          'POST',
          '/api/v1/shared-playlist-invites/$viewerCode',
          token: viewerToken,
        ),
      );
      final rejectedEditor = await server(
        _request(
          'POST',
          '/api/v1/shared-playlist-invites/$editorCode',
          token: editorToken,
        ),
      );
      expect(rejectedViewer.statusCode, 404);
      expect(rejectedEditor.statusCode, 404);

      final replacement = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists/$playlistId/invites',
          token: ownerToken,
          jsonBody: const <String, Object?>{'role': 'viewer'},
        ),
      );
      final replacementCode = (await _json(replacement))['inviteCode'] as String;
      final acceptedReplacement = await server(
        _request(
          'POST',
          '/api/v1/shared-playlist-invites/$replacementCode',
          token: viewerToken,
        ),
      );
      expect(acceptedReplacement.statusCode, 200);
    });

    test('rejects stream URLs and unauthenticated invitation joins', () async {
      final server = handler();
      final rejected = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists',
          token: ownerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'owner-phone',
            'playlist': <String, Object?>{
              'version': 1,
              'name': 'Unsafe',
              'trackIds': <String>['track-1'],
              'streamUrl': 'https://private.example.test/audio',
            },
          },
        ),
      );
      expect(rejected.statusCode, 400);
      expect((await _json(rejected))['error'], 'invalid_shared_playlist');

      final unauthenticated = await server(
        _request('POST', '/api/v1/shared-playlist-invites/not-a-real-code'),
      );
      expect(unauthenticated.statusCode, 401);
    });

    test('stores bounded smart-playlist rules without library data', () async {
      final server = handler();
      final smartDocument = <String, Object?>{
        'version': 2,
        'kind': 'smart',
        'name': 'Mira discoveries',
        'rule': <String, Object?>{
          'query': '',
          'sourceId': '',
          'artist': 'Mira',
          'album': '',
          'genre': '',
          'minimumDurationSeconds': 0,
          'maximumDurationSeconds': 0,
          'favoritesOnly': false,
          'minimumPlayCount': 0,
          'minimumDaysSinceLastPlayed': 0,
          'matchMode': 'all',
          'ruleGroups': <Object?>[
            <String, Object?>{
              'matchMode': 'any',
              'rules': <Object?>[
                <String, Object?>{'field': 'genre', 'value': 'Jazz'},
              ],
              'groups': <Object?>[],
            },
          ],
          'sortMode': 'title',
          'limit': 25,
        },
      };
      final created = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists',
          token: ownerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'owner-phone',
            'playlist': smartDocument,
          },
        ),
      );
      expect(created.statusCode, 201);
      expect((await _json(created))['playlist'], smartDocument);

      final rejected = await server(
        _request(
          'POST',
          '/api/v1/shared-playlists',
          token: ownerToken,
          jsonBody: <String, Object?>{
            'baseRevision': 0,
            'deviceId': 'owner-phone',
            'playlist': <String, Object?>{
              ...smartDocument,
              'libraryTracks': <Object?>['private-track-id'],
            },
          },
        ),
      );
      expect(rejected.statusCode, 400);
      expect((await _json(rejected))['error'], 'invalid_shared_playlist');
    });
  });

  test('file sync store survives restart and retains only the latest revision',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'aethertune-server-sync-test-',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final firstStore = FileLibrarySyncSnapshotStore(root);
    final first = await firstStore.write(
      userId: 'private-user-name',
      baseRevision: 0,
      deviceId: 'phone',
      snapshot: _syncSnapshot(title: 'Revision one'),
      checksum: _checksum(_syncSnapshot(title: 'Revision one')),
      updatedAt: DateTime.utc(2026, 7, 10, 14),
    );
    expect(first.isConflict, isFalse);

    final restartedStore = FileLibrarySyncSnapshotStore(root);
    final restored = await restartedStore.read('private-user-name');
    expect(restored?.revision, 1);
    expect(restored?.snapshot?['name'], 'Revision one');

    final conflict = await restartedStore.write(
      userId: 'private-user-name',
      baseRevision: 0,
      deviceId: 'desktop',
      snapshot: _syncSnapshot(title: 'Stale'),
      checksum: _checksum(_syncSnapshot(title: 'Stale')),
      updatedAt: DateTime.utc(2026, 7, 10, 15),
    );
    expect(conflict.isConflict, isTrue);
    expect(conflict.snapshot?.revision, 1);

    final secondSnapshot = _syncSnapshot(title: 'Revision two');
    final second = await restartedStore.write(
      userId: 'private-user-name',
      baseRevision: 1,
      deviceId: 'desktop',
      snapshot: secondSnapshot,
      checksum: _checksum(secondSnapshot),
      updatedAt: DateTime.utc(2026, 7, 10, 15),
    );
    expect(second.snapshot?.revision, 2);

    final deleted = await restartedStore.delete(
      userId: 'private-user-name',
      baseRevision: 2,
      deviceId: 'desktop',
      updatedAt: DateTime.utc(2026, 7, 10, 16),
    );
    expect(deleted.isConflict, isFalse);
    expect(deleted.snapshot?.revision, 3);
    expect(deleted.snapshot?.snapshot, isNull);

    final afterDeletionRestart = FileLibrarySyncSnapshotStore(root);
    final tombstone = await afterDeletionRestart.read('private-user-name');
    expect(tombstone?.revision, 3);
    expect(tombstone?.snapshot, isNull);

    final staleAfterDeletion = await afterDeletionRestart.write(
      userId: 'private-user-name',
      baseRevision: 2,
      deviceId: 'phone',
      snapshot: _syncSnapshot(title: 'Stale after deletion'),
      checksum: _checksum(_syncSnapshot(title: 'Stale after deletion')),
      updatedAt: DateTime.utc(2026, 7, 10, 17),
    );
    expect(staleAfterDeletion.isConflict, isTrue);
    expect(staleAfterDeletion.snapshot?.revision, 3);

    final files = await root
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    expect(files, hasLength(1));
    expect(files.single.path, endsWith('snapshot-3.json'));
    expect(files.single.path, isNot(contains('private-user-name')));
  });

  test('authenticator parses JSON users and rejects malformed configuration',
      () {
    final hashedToken = sha256.convert(utf8.encode('token-three')).toString();
    final authenticator = StaticSyncAuthenticator.fromJson(
      '{"yunus":"token-one","desktop":"token-two","server":"sha256:$hashedToken"}',
    );
    expect(authenticator.isConfigured, isTrue);
    expect(authenticator.authenticate('token-one'), 'yunus');
    expect(authenticator.authenticate('token-two'), 'desktop');
    expect(authenticator.authenticate('token-three'), 'server');
    expect(authenticator.authenticate('wrong-token'), isNull);
    expect(StaticSyncAuthenticator.fromJson(null).isConfigured, isFalse);
    expect(
      () => StaticSyncAuthenticator.fromJson('["invalid"]'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => StaticSyncAuthenticator.fromJson(
        '{"yunus":"sha256:not-a-token-digest"}',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

Request _request(
  String method,
  String path, {
  String? token,
  Map<String, Object?>? jsonBody,
}) {
  return Request(
    method,
    Uri.parse('http://localhost$path'),
    headers: <String, String>{
      if (token != null) 'authorization': 'Bearer $token',
      if (jsonBody != null) 'content-type': 'application/json',
    },
    body: jsonBody == null ? null : jsonEncode(jsonBody),
  );
}

Map<String, Object?> _syncSnapshot({
  String title = 'Synced library',
  String? localPath,
}) {
  return <String, Object?>{
    'syncVersion': 1,
    'version': 1,
    'name': title,
    'tracks': <Object?>[
      <String, Object?>{
        'id': 'track-1',
        'title': 'Track 1',
        'localPath': localPath,
      },
    ],
    'offlineCacheQueue': <Object?>[],
  };
}

String _checksum(Map<String, Object?> snapshot) {
  return sha256.convert(utf8.encode(jsonEncode(snapshot))).toString();
}

Future<Map<String, dynamic>> _json(Response response) async {
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}
