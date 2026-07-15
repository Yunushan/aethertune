import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aethertune_server/server.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('AetherTune server', () {
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
