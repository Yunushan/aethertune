import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/provider_error.dart';
import 'package:aethertune/src/domain/library_sync_account.dart';

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
