import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/provider_error.dart';
import 'package:aethertune/src/domain/library_sync_account.dart';
import 'package:aethertune/src/domain/library_sync_profile.dart';
import 'package:aethertune/src/domain/listen_together_session.dart';

void main() {
  test('validates server URLs and builds a path-safe sync endpoint', () {
    final account = createLibrarySyncAccount(
      baseUrl: 'HTTPS://SYNC.EXAMPLE.TEST/aethertune/',
      deviceId: '  Windows desktop  ',
      allowInsecureHttp: false,
    );

    expect(account.baseUri, Uri.parse('https://sync.example.test/aethertune'));
    expect(account.deviceId, 'Windows desktop');
    expect(
      account.libraryEndpointUri,
      Uri.parse(
        'https://sync.example.test/aethertune/api/v1/sync/library',
      ),
    );
    expect(
      account.profileEndpointUri,
      Uri.parse(
        'https://sync.example.test/aethertune/api/v1/auth/profile',
      ),
    );
    expect(
      () => createLibrarySyncAccount(
        baseUrl: 'http://192.168.1.10:8080',
        deviceId: 'Phone',
        allowInsecureHttp: false,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => createLibrarySyncAccount(
        baseUrl: 'https://user:secret@sync.example.test?token=secret',
        deviceId: 'Phone',
        allowInsecureHttp: false,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('fetch sends bearer auth and verifies the server checksum', () async {
    const token = 'private-sync-token';
    final snapshot = <String, Object?>{
      'syncVersion': 1,
      'version': 1,
      'tracks': <Object?>[],
      'offlineCacheQueue': <Object?>[],
    };
    final checksum = sha256
        .convert(utf8.encode(jsonEncode(snapshot)))
        .toString();
    String? method;
    Uri? uri;
    Map<String, String>? capturedRequestHeaders;
    final client = LibrarySyncClient(
      account: _account(),
      token: token,
      httpExecutor: (
        capturedMethod,
        capturedUri, {
        required headers,
        body,
      }) async {
        method = capturedMethod;
        uri = capturedUri;
        capturedRequestHeaders = headers;
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'revision': 4,
            'updatedAt': '2026-07-10T12:30:00.000Z',
            'updatedByDevice': 'Android phone',
            'checksum': checksum,
            'snapshot': snapshot,
          }),
        );
      },
    );

    final result = await client.fetch();

    expect(method, 'GET');
    expect(uri, _account().libraryEndpointUri);
    expect(capturedRequestHeaders?['authorization'], 'Bearer $token');
    expect(uri.toString(), isNot(contains(token)));
    expect(result.revision, 4);
    expect(result.snapshot, snapshot);
    expect(result.updatedByDevice, 'Android phone');
  });

  test('fetches sync metadata without requesting a snapshot document', () async {
    Uri? uri;
    final client = LibrarySyncClient(
      account: _account(),
      token: 'private-sync-token',
      httpExecutor: (method, capturedUri, {required headers, body}) async {
        expect(method, 'GET');
        uri = capturedUri;
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'revision': 4,
            'updatedAt': '2026-07-10T12:30:00.000Z',
            'updatedByDevice': 'Android phone',
            'checksum': 'a' * 64,
          }),
        );
      },
    );

    final result = (await client.fetchMetadata())!;

    expect(uri, _account().libraryMetadataEndpointUri);
    expect(result.revision, 4);
    expect(result.snapshot, isNull);
    expect(result.checksum, 'a' * 64);
  });

  test('falls back when an older server lacks sync metadata', () async {
    final client = LibrarySyncClient(
      account: _account(),
      token: 'private-sync-token',
      httpExecutor: (method, uri, {required headers, body}) async {
        expect(method, 'GET');
        expect(uri, _account().libraryMetadataEndpointUri);
        return const LibrarySyncHttpResponse(statusCode: 404, body: '');
      },
    );

    expect(await client.fetchMetadata(), isNull);
  });

  test('publishes and fetches portable listen-together sessions', () async {
    final session = ListenTogetherSession(
      trackIds: const <String>['track-1', 'track-2'],
      currentTrackId: 'track-1',
      position: const Duration(seconds: 12),
      playing: true,
    );
    var requests = 0;
    final client = LibrarySyncClient(
      account: _account(),
      token: 'private-sync-token',
      httpExecutor: (method, uri, {required headers, body}) async {
        expect(uri, _account().listenTogetherEndpointUri);
        requests += 1;
        if (method == 'PUT') {
          final request = jsonDecode(body!) as Map<String, dynamic>;
          expect(request['baseRevision'], 0);
          expect(request['deviceId'], 'Test device');
          expect(request['session'], session.toJson());
          return LibrarySyncHttpResponse(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'revision': 1,
              'updatedAt': '2026-07-12T10:00:00.000Z',
              'updatedByDevice': 'Test device',
              'checksum': 'a' * 64,
            }),
          );
        }
        expect(method, 'GET');
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'revision': 1,
            'updatedAt': '2026-07-12T10:00:00.000Z',
            'updatedByDevice': 'Test device',
            'checksum': 'a' * 64,
            'session': session.toJson(),
          }),
        );
      },
    );

    final published = await client.publishListenTogetherSession(
      baseRevision: 0,
      session: session,
    );
    final joined = await client.fetchListenTogetherSession();

    expect(published.revision, 1);
    expect(joined.session?.trackIds, session.trackIds);
    expect(joined.session?.position, session.position);
    expect(requests, 2);
  });

  test('raises typed listen-together conflicts', () async {
    final client = LibrarySyncClient(
      account: _account(),
      token: 'private-sync-token',
      httpExecutor: (method, uri, {required headers, body}) async {
        return LibrarySyncHttpResponse(
          statusCode: 409,
          body: jsonEncode(<String, Object?>{
            'error': 'listen_together_conflict',
            'currentRevision': 4,
            'updatedByDevice': 'Host desktop',
          }),
        );
      },
    );

    await expectLater(
      client.publishListenTogetherSession(
        baseRevision: 0,
        session: ListenTogetherSession(
          trackIds: const <String>['track-1'],
          currentTrackId: 'track-1',
          position: Duration.zero,
          playing: false,
        ),
      ),
      throwsA(
        isA<ListenTogetherConflictException>()
            .having((error) => error.currentRevision, 'revision', 4)
            .having((error) => error.updatedByDevice, 'device', 'Host desktop'),
      ),
    );
  });

  test('rejects a corrupted snapshot and redacts transport failures', () async {
    const token = 'never-display-this-token';
    final corrupted = LibrarySyncClient(
      account: _account(),
      token: token,
      httpExecutor: (method, uri, {required headers, body}) async {
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'revision': 1,
            'updatedAt': '2026-07-10T12:30:00.000Z',
            'updatedByDevice': 'Phone',
            'checksum': List<String>.filled(64, '0').join(),
            'snapshot': <String, Object?>{
              'syncVersion': 1,
              'version': 1,
              'tracks': <Object?>[],
            },
          }),
        );
      },
    );
    await expectLater(
      corrupted.fetch(),
      throwsA(isA<ProviderRequestException>()),
    );

    final failed = LibrarySyncClient(
      account: _account(),
      token: token,
      httpExecutor: (method, uri, {required headers, body}) async {
        throw StateError('Connection failed with $token.');
      },
    );
    await expectLater(
      failed.fetch(),
      throwsA(
        predicate<Object>((error) {
          final message = error.toString();
          return message.contains('[redacted]') && !message.contains(token);
        }),
      ),
    );
  });

  test('push sends revision and raises typed optimistic conflicts', () async {
    Map<String, Object?>? requestBody;
    final client = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        expect(method, 'PUT');
        expect(headers['content-type'], 'application/json');
        requestBody = jsonDecode(body!) as Map<String, dynamic>;
        return LibrarySyncHttpResponse(
          statusCode: 409,
          body: jsonEncode(<String, Object?>{
            'error': 'sync_conflict',
            'currentRevision': 7,
            'updatedAt': '2026-07-10T14:00:00.000Z',
            'updatedByDevice': 'Linux desktop',
            'checksum': 'abc',
          }),
        );
      },
    );
    final snapshot = <String, Object?>{
      'syncVersion': 1,
      'version': 1,
      'tracks': <Object?>[],
    };

    await expectLater(
      client.push(baseRevision: 3, snapshot: snapshot),
      throwsA(
        isA<LibrarySyncConflictException>()
            .having((error) => error.currentRevision, 'revision', 7)
            .having(
              (error) => error.updatedByDevice,
              'device',
              'Linux desktop',
            ),
      ),
    );
    expect(requestBody?['baseRevision'], 3);
    expect(requestBody?['deviceId'], 'Test device');
    expect(requestBody?['snapshot'], snapshot);
  });

  test('fetches validated managed identity without exposing its token',
      () async {
    const token = 'managed-private-token';
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    final client = LibrarySyncClient(
      account: _account(),
      token: token,
      httpExecutor: (method, uri, {required headers, body}) async {
        requestedUri = uri;
        requestedHeaders = headers;
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'account': <String, Object?>{
              'id': 'primary',
              'displayName': 'Primary listener',
              'managed': true,
              'editable': true,
            },
            'device': <String, Object?>{
              'id': '0123456789abcdef01234567',
              'deviceName': 'Windows desktop',
              'createdAt': '2026-07-15T12:00:00.000Z',
            },
          }),
        );
      },
    );

    final profile = await client.fetchProfile();

    expect(requestedUri, _account().profileEndpointUri);
    expect(requestedHeaders?['authorization'], 'Bearer $token');
    expect(requestedUri.toString(), isNot(contains(token)));
    expect(profile?.id, 'primary');
    expect(profile?.effectiveDisplayName, 'Primary listener');
    expect(profile?.managed, isTrue);
    expect(profile?.editable, isTrue);
    expect(profile?.device?.name, 'Windows desktop');
    expect(profile?.device?.createdAt, DateTime.utc(2026, 7, 15, 12));
  });

  test('updates managed profile over authenticated PATCH', () async {
    const token = 'managed-private-token';
    String? requestedMethod;
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    Map<String, Object?>? requestedBody;
    final client = LibrarySyncClient(
      account: _account(),
      token: token,
      httpExecutor: (method, uri, {required headers, body}) async {
        requestedMethod = method;
        requestedUri = uri;
        requestedHeaders = headers;
        requestedBody = jsonDecode(body!) as Map<String, Object?>;
        return const LibrarySyncHttpResponse(
          statusCode: 200,
          body: '{'
              '"account":{'
              '"id":"primary",'
              '"displayName":"Shared listeners",'
              '"managed":true,'
              '"editable":true'
              '},'
              '"device":{'
              '"id":"0123456789abcdef01234567",'
              '"deviceName":"Pocket player",'
              '"createdAt":"2026-07-15T12:00:00.000Z"'
              '}'
              '}',
        );
      },
    );

    final updated = await client.updateProfile(
      displayName: '  Shared listeners  ',
      deviceName: '  Pocket player  ',
    );

    expect(requestedMethod, 'PATCH');
    expect(requestedUri, _account().profileEndpointUri);
    expect(requestedHeaders?['authorization'], 'Bearer $token');
    expect(requestedHeaders?['content-type'], 'application/json');
    expect(requestedBody, <String, Object?>{
      'displayName': 'Shared listeners',
      'deviceName': 'Pocket player',
    });
    expect(jsonEncode(requestedBody), isNot(contains(token)));
    expect(updated.effectiveDisplayName, 'Shared listeners');
    expect(updated.editable, isTrue);
    expect(updated.device?.name, 'Pocket player');
    await expectLater(
      client.updateProfile(
        displayName: ' ',
        deviceName: 'Pocket player',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('tolerates old servers and rejects malformed managed identity',
      () async {
    final oldServer = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        return const LibrarySyncHttpResponse(
          statusCode: 404,
          body: '{"error":"not_found"}',
        );
      },
    );
    expect(await oldServer.fetchProfile(), isNull);

    final staticServer = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        return const LibrarySyncHttpResponse(
          statusCode: 200,
          body: '{'
              '"account":{'
              '"id":"static-account",'
              '"displayName":null,'
              '"managed":false'
              '},'
              '"device":null'
              '}',
        );
      },
    );
    final staticProfile = await staticServer.fetchProfile();
    expect(staticProfile?.id, 'static-account');
    expect(staticProfile?.effectiveDisplayName, 'static-account');
    expect(staticProfile?.managed, isFalse);
    expect(staticProfile?.editable, isFalse);
    expect(staticProfile?.device, isNull);

    final legacyManagedProfile = LibrarySyncProfile.fromServerJson(
      <String, Object?>{
        'account': <String, Object?>{
          'id': 'legacy-managed',
          'displayName': 'Legacy listener',
          'managed': true,
        },
        'device': <String, Object?>{
          'id': '0123456789abcdef01234567',
          'deviceName': 'Legacy device',
          'createdAt': '2026-07-15T12:00:00.000Z',
        },
      },
    );
    expect(legacyManagedProfile.editable, isFalse);
    expect(
      () => LibrarySyncProfile.fromServerJson(<String, Object?>{
        'account': <String, Object?>{
          'id': 'static-account',
          'managed': false,
          'editable': true,
        },
        'device': null,
      }),
      throwsA(isA<FormatException>()),
    );

    final malformed = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        return const LibrarySyncHttpResponse(
          statusCode: 200,
          body: '{'
              '"account":{"id":"primary","managed":true},'
              '"device":null'
              '}',
        );
      },
    );
    await expectLater(
      malformed.fetchProfile(),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => LibrarySyncProfile.fromServerJson(<String, Object?>{
        'account': <String, Object?>{
          'id': 'primary',
          'managed': true,
        },
        'device': <String, Object?>{
          'id': '0123456789abcdef01234567',
          'deviceName': 'Desktop',
          'createdAt': 42,
        },
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('deletes a remote snapshot with the current revision', () async {
    String? method;
    Map<String, Object?>? requestBody;
    final client = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (capturedMethod, uri, {required headers, body}) async {
        method = capturedMethod;
        requestBody = jsonDecode(body!) as Map<String, Object?>;
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'revision': 5,
            'updatedAt': '2026-07-10T15:00:00.000Z',
            'updatedByDevice': 'Test device',
            'checksum': null,
          }),
        );
      },
    );

    final result = await client.delete(baseRevision: 4);

    expect(method, 'DELETE');
    expect(requestBody, <String, Object?>{
      'baseRevision': 4,
      'deviceId': 'Test device',
    });
    expect(result.revision, 5);
    expect(result.hasSnapshot, isFalse);
    expect(result.checksum, isNull);
  });

  test('accepts a revisioned remote deletion during fetch', () async {
    final client = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'revision': 6,
            'updatedAt': '2026-07-10T16:00:00.000Z',
            'updatedByDevice': 'Desktop',
            'checksum': null,
            'snapshot': null,
          }),
        );
      },
    );

    final result = await client.fetch();

    expect(result.revision, 6);
    expect(result.hasSnapshot, isFalse);
    expect(result.updatedByDevice, 'Desktop');
  });
}

LibrarySyncAccount _account() {
  return createLibrarySyncAccount(
    baseUrl: 'https://sync.example.test/base',
    deviceId: 'Test device',
    allowInsecureHttp: false,
  );
}
