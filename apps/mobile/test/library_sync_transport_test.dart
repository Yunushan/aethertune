import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/library_sync_credential_vault.dart';
import 'package:aethertune/src/data/library_sync_store.dart';
import 'package:aethertune/src/data/provider_error.dart';
import 'package:aethertune/src/domain/library_sync_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final stage in ['headers', 'body', 'total']) {
    test('bounds $stage waits and disconnects the owned socket', () async {
      Timer? drip;
      var chunks = 0;
      final server = await _RawSyncServer.open((connection) {
        if (stage == 'headers') return;
        connection.socket.write(
          'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
          '1\r\n{\r\n',
        );
        if (stage == 'total') {
          drip = Timer.periodic(const Duration(milliseconds: 40), (_) {
            chunks++;
            connection.socket.write('1\r\n \r\n');
          });
        }
      });
      addTearDown(() => drip?.cancel());
      final operation = executeLibrarySyncHttpRequest(
        'GET',
        server.uri,
        headers: const {},
        requestTimeout: Duration(milliseconds: stage == 'headers' ? 250 : 5000),
        idleTimeout: Duration(milliseconds: stage == 'body' ? 250 : 5000),
        transferTimeout: Duration(milliseconds: stage == 'total' ? 600 : 5000),
      );
      await expectLater(_observed(operation), throwsA(isA<TimeoutException>()));
      expect(server.connections, hasLength(1));
      await server.connections.single.disconnected.future.timeout(
        const Duration(seconds: 2),
      );
      if (stage == 'total') expect(chunks, greaterThan(2));
    });
  }

  test('total deadline also bounds a stalled TLS handshake', () async {
    final server = await _RawSyncServer.open((_) {});
    await expectLater(
      _observed(
        executeLibrarySyncHttpRequest(
          'GET',
          server.uri.replace(scheme: 'https'),
          headers: const {},
          requestTimeout: const Duration(seconds: 5),
          transferTimeout: const Duration(milliseconds: 300),
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(server.connections, hasLength(1));
    await server.connections.single.disconnected.future.timeout(
      const Duration(seconds: 2),
    );
  });

  test('rejects nonpositive deadline configuration', () async {
    for (final value in [Duration.zero, const Duration(milliseconds: -1)]) {
      for (final stage in ['request', 'idle', 'total']) {
        await expectLater(
          executeLibrarySyncHttpRequest(
            'GET',
            Uri.parse('http://127.0.0.1:1/'),
            headers: const {},
            requestTimeout: stage == 'request'
                ? value
                : const Duration(seconds: 1),
            idleTimeout: stage == 'idle' ? value : const Duration(seconds: 1),
            transferTimeout: stage == 'total'
                ? value
                : const Duration(seconds: 1),
          ),
          throwsArgumentError,
        );
      }
    }
  });

  test('returns a complete UTF-8 response and closes its socket', () async {
    final server = await _RawSyncServer.open((connection) {
      connection.reply(jsonEncode({'name': 'M\u00fczik'}));
    });
    final result = await executeLibrarySyncHttpRequest(
      'GET',
      server.uri,
      headers: const {'accept': 'application/json'},
    );
    expect(result.statusCode, 200);
    expect(jsonDecode(result.body), {'name': 'M\u00fczik'});
    await server.connections.single.disconnected.future.timeout(
      const Duration(seconds: 2),
    );
  });

  test('does not forward credentials through redirects', () async {
    final destination = await _RawSyncServer.open(
      (connection) => connection.reply('{}'),
    );
    final origin = await _RawSyncServer.open((connection) {
      connection.reply(
        '',
        status: 302,
        extraHeaders: 'Location: ${destination.uri}\r\n',
      );
    });
    final result = await executeLibrarySyncHttpRequest(
      'GET',
      origin.uri,
      headers: const {'authorization': 'Bearer synthetic-token'},
    );
    expect(result.statusCode, 302);
    expect(destination.connections, isEmpty);
  });

  test('still rejects oversized response bodies and disconnects', () async {
    final server = await _RawSyncServer.open((connection) {
      connection.socket.write(
        'HTTP/1.1 200 OK\r\nContent-Length: ${maxLibrarySyncResponseBytes + 1}\r\n\r\n',
      );
      connection.socket.add(
        List<int>.filled(maxLibrarySyncResponseBytes + 1, 32),
      );
    });
    await expectLater(
      executeLibrarySyncHttpRequest('GET', server.uri, headers: const {}),
      throwsA(isA<FormatException>()),
    );
    await server.connections.single.disconnected.future.timeout(
      const Duration(seconds: 2),
    );
  });

  test('still rejects invalid UTF-8 and disconnects', () async {
    final server = await _RawSyncServer.open((connection) {
      connection.socket.write('HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\n');
      connection.socket.add([255]);
    });
    await expectLater(
      executeLibrarySyncHttpRequest('GET', server.uri, headers: const {}),
      throwsA(isA<FormatException>()),
    );
    await server.connections.single.disconnected.future.timeout(
      const Duration(seconds: 2),
    );
  });

  test(
    'preserves UTF-8 uploads, headers and non-success HTTP statuses',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final handled = Completer<void>();
      final payload = jsonEncode({'name': 'M\u00fczik'});
      final listener = server.listen((request) async {
        try {
          expect(request.method, 'PUT');
          expect(request.uri.path, '/api/v1/sync/library');
          expect(
            request.headers.value('authorization'),
            'Bearer synthetic-token',
          );
          expect(request.headers.contentType?.charset, 'utf-8');
          expect(await utf8.decoder.bind(request).join(), payload);
          request.response
            ..statusCode = 409
            ..write(payload);
          await request.response.close();
          handled.complete();
        } on Object catch (error, stack) {
          handled.completeError(error, stack);
        }
      });
      addTearDown(() async {
        await server.close(force: true);
        await listener.cancel();
      });
      final response = await executeLibrarySyncHttpRequest(
        'PUT',
        Uri.parse('http://127.0.0.1:${server.port}/api/v1/sync/library'),
        headers: const {
          'authorization': 'Bearer synthetic-token',
          'content-type': 'application/json; charset=utf-8',
        },
        body: payload,
      );
      await handled.future;
      expect(response.statusCode, 409);
      expect(response.body, payload);
    },
  );

  test(
    'bounds decompressed response size, not just compressed wire size',
    () async {
      final wire = gzip.encode(
        List<int>.filled(maxLibrarySyncResponseBytes + 1, 32),
      );
      expect(wire.length, lessThan(maxLibrarySyncResponseBytes));
      final server = await _RawSyncServer.open((connection) {
        connection.socket.write(
          'HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n'
          'Content-Length: ${wire.length}\r\n\r\n',
        );
        connection.socket.add(wire);
      });
      await expectLater(
        executeLibrarySyncHttpRequest('GET', server.uri, headers: const {}),
        throwsA(isA<FormatException>()),
      );
      await server.connections.single.disconnected.future.timeout(
        const Duration(seconds: 2),
      );
    },
  );

  test(
    'cancelling one request leaves another client and its response intact',
    () async {
      final stalled = await _RawSyncServer.open((_) {});
      final accepted = Completer<_Connection>();
      final healthy = await _RawSyncServer.open(accepted.complete);
      final failed = expectLater(
        executeLibrarySyncHttpRequest(
          'GET',
          stalled.uri,
          headers: const {},
          requestTimeout: const Duration(milliseconds: 250),
        ),
        throwsA(isA<TimeoutException>()),
      );
      final succeeding = executeLibrarySyncHttpRequest(
        'GET',
        healthy.uri,
        headers: const {},
      );
      final peer = await accepted.future;
      await failed;
      expect(peer.disconnected.isCompleted, isFalse);
      peer.reply('{"revision":7}');
      expect((await succeeding).body, '{"revision":7}');
      await stalled.connections.single.disconnected.future.timeout(
        const Duration(seconds: 2),
      );
    },
  );

  test(
    'early native request failures are bounded and do not expose credentials',
    () async {
      final server = await _RawSyncServer.open(
        (connection) => connection.reply('{}'),
      );
      await expectLater(
        _observed(
          executeLibrarySyncHttpRequest(
            'BAD METHOD',
            server.uri.replace(query: 'token=synthetic-secret'),
            headers: const {'authorization': 'Bearer synthetic-secret'},
          ),
        ),
        throwsA(
          predicate<Object>(
            (error) =>
                error is HttpException &&
                !error.toString().contains('synthetic-secret'),
          ),
        ),
      );
      final response = await executeLibrarySyncHttpRequest(
        'GET',
        server.uri,
        headers: const {},
      );
      expect(response.statusCode, 200);
    },
  );

  test(
    'sync settings recover from a real timeout and retry without stale writes',
    () async {
      SharedPreferences.setMockInitialValues({});
      var responding = false;
      final server = await _RawSyncServer.open((connection) {
        if (!responding) return;
        if (connection.request.startsWith('GET /api/v1/auth/profile ')) {
          connection.reply('{}', status: 404);
        } else {
          connection.reply(
            jsonEncode({'revision': 0, 'snapshot': null, 'checksum': null}),
          );
        }
      });
      final vault = _MemoryVault();
      final store = LibrarySyncStore(
        credentialVault: vault,
        clientFactory: (account, token) => LibrarySyncClient(
          account: account,
          token: token,
          httpExecutor: (method, uri, {required headers, body}) =>
              executeLibrarySyncHttpRequest(
                method,
                uri,
                headers: headers,
                body: body,
                requestTimeout: const Duration(milliseconds: 250),
              ),
        ),
      );
      final library = LibraryStore();
      addTearDown(store.dispose);
      addTearDown(library.dispose);
      await library.load();
      await store.load();
      final account = LibrarySyncAccount(
        baseUri: server.uri,
        deviceId: 'Synthetic device',
        allowInsecureHttp: true,
      );
      final operation = store.testAndSave(library, account, 'synthetic-token');
      expect(store.busy, isTrue);
      await expectLater(
        store.testAndSave(library, account, 'synthetic-token'),
        throwsStateError,
      );
      await expectLater(
        _observed(operation),
        throwsA(isA<ProviderRequestException>()),
      );
      expect(store.busy, isFalse);
      expect(store.lastError, contains('TimeoutException'));
      expect(store.lastError, isNot(contains('synthetic-token')));
      expect(store.isConfigured, isFalse);
      expect(vault.token, isNull);
      final old = server.connections.single;
      await old.disconnected.future.timeout(const Duration(seconds: 2));

      responding = true;
      await store.testAndSave(library, account, 'synthetic-token');
      expect(store.busy, isFalse);
      expect(store.lastError, isNull);
      expect(store.isConfigured, isTrue);
      expect(vault.token, 'synthetic-token');
      expect(server.connections, hasLength(3));
      expect(store.lastKnownRevision, 0);
    },
  );
}

Future<T> _observed<T>(Future<T> operation) => operation.timeout(
  const Duration(seconds: 2),
  onTimeout: () =>
      throw TestFailure('Transport did not enforce its configured deadline.'),
);

// A raw peer lets tests observe remote disconnects even before HTTP headers.
// It also models a TLS peer that accepts TCP but never finishes the handshake.
class _RawSyncServer {
  _RawSyncServer(this.server);
  final ServerSocket server;
  final List<_Connection> connections = [];
  late final StreamSubscription<Socket> subscription;
  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}');

  static Future<_RawSyncServer> open(void Function(_Connection) handle) async {
    final result = _RawSyncServer(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    result.subscription = result.server.listen((socket) {
      final connection = _Connection(socket);
      result.connections.add(connection);
      connection.subscription = socket.listen(
        (bytes) {
          if (connection.handled) return;
          connection.request += latin1.decode(bytes);
          if (connection.request.contains('\r\n\r\n')) {
            connection.handled = true;
            handle(connection);
          }
        },
        onError: (Object _) {
          connection.markDisconnected();
        },
        onDone: connection.markDisconnected,
      );
    });
    addTearDown(() async {
      for (final connection in result.connections) {
        connection.socket.destroy();
        await connection.subscription.cancel();
      }
      await result.server.close();
      await result.subscription.cancel();
    });
    return result;
  }
}

class _Connection {
  _Connection(this.socket) {
    // Early native size rejection can reset this fixture's pending writes.
    // Observe the sink future as well as the socket's input subscription.
    unawaited(
      socket.done.then<void>((_) {}, onError: (Object _) => markDisconnected()),
    );
  }
  final Socket socket;
  final disconnected = Completer<void>();
  late final StreamSubscription<List<int>> subscription;
  var request = '';
  var handled = false;

  void markDisconnected() {
    if (!disconnected.isCompleted) disconnected.complete();
  }

  void reply(String body, {int status = 200, String extraHeaders = ''}) {
    final bytes = utf8.encode(body);
    socket.write(
      'HTTP/1.1 $status Response\r\nContent-Type: application/json\r\n'
      'Content-Length: ${bytes.length}\r\n$extraHeaders\r\n',
    );
    socket.add(bytes);
  }
}

class _MemoryVault implements LibrarySyncCredentialVault {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async => token = value;
  @override
  Future<void> delete() async => token = null;
}
