import 'dart:convert';
import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  for (final persisted in [false, true]) {
    final storage = persisted ? 'persisted' : 'memory';
    for (final policy in <String, Map<String, String>>{
      'default': {},
      'one day': {'AETHERTUNE_MANAGED_TOKEN_TTL_DAYS': '1'},
    }.entries) {
      test('$storage recovered tokens honor ${policy.key} expiry', () async {
        var now = DateTime.utc(2026, 9, 6);
        final directory = await _testDirectory(persisted);
        final lifetime = managedTokenLifetimeFromEnvironment(policy.value)!;
        var registry = await _registry(directory, () => now, lifetime);
        final original = await registry.issueToken(
          accountId: 'primary',
          deviceName: 'Original',
        );
        final recovery = await registry.issueRecoveryCode(accountId: 'primary');
        now = now.add(const Duration(minutes: 30));
        final recovered = (await registry.redeemRecoveryCode(
          code: recovery.code,
          deviceName: 'Recovered',
        ))!;
        final deadline = now.add(lifetime);
        expect(registry.authenticate(original.token), isNull);
        expect(registry.authenticate(recovered.token), 'primary');
        if (persisted) {
          // A later configuration change must not reinterpret a saved deadline.
          registry = await _registry(
            directory,
            () => now,
            const Duration(days: 2),
          );
        }
        now = deadline.subtract(const Duration(microseconds: 1));
        expect(registry.authenticate(recovered.token), 'primary');
        now = deadline;
        expect(registry.authenticate(recovered.token), isNull);
        expect(
          recovered.device.toJson()['expiresAt'],
          deadline.toIso8601String(),
        );
        expect(
          registry.account('primary')!.toJson()['tokens'],
          contains(containsPair('expiresAt', deadline.toIso8601String())),
        );
      });
    }

    test('$storage recovery preserves explicit no-expiry policy', () async {
      var now = DateTime.utc(2026, 9, 6);
      final directory = await _testDirectory(persisted);
      final lifetime = managedTokenLifetimeFromEnvironment({
        'AETHERTUNE_MANAGED_TOKEN_TTL_DAYS': '0',
      });
      var registry = await _registry(directory, () => now, lifetime);
      await registry.issueToken(accountId: 'primary', deviceName: 'Original');
      final recovery = await registry.issueRecoveryCode(accountId: 'primary');
      final recovered = (await registry.redeemRecoveryCode(
        code: recovery.code,
        deviceName: 'Recovered',
      ))!;
      if (persisted) registry = await _registry(directory, () => now, lifetime);
      now = now.add(const Duration(days: 4000));
      expect(registry.authenticate(recovered.token), 'primary');
      expect(recovered.device.toJson(), isNot(contains('expiresAt')));
    });

    test('$storage device rename preserves the original deadline', () async {
      var now = DateTime.utc(2026, 9, 6);
      final directory = await _testDirectory(persisted);
      const lifetime = Duration(hours: 1);
      var registry = await _registry(directory, () => now, lifetime);
      final issued = await registry.issueToken(
        accountId: 'primary',
        deviceName: 'Phone',
      );
      final deadline = now.add(lifetime);
      now = now.add(const Duration(minutes: 30));
      final updated = (await registry.updateProfile(
        accountId: 'primary',
        tokenId: issued.device.id,
        deviceName: 'Renamed phone',
      ))!;
      expect(updated.device.id, issued.device.id);
      expect(updated.device.deviceName, 'Renamed phone');
      if (persisted) registry = await _registry(directory, () => now, lifetime);
      now = deadline.subtract(const Duration(microseconds: 1));
      expect(registry.authenticate(issued.token), 'primary');
      now = deadline;
      expect(registry.authenticate(issued.token), isNull);
      expect(updated.device.toJson()['expiresAt'], deadline.toIso8601String());
    });

    test(
      '$storage profile and activity updates do not extend expiry',
      () async {
        var now = DateTime.utc(2026, 9, 6);
        final directory = await _testDirectory(persisted);
        const lifetime = Duration(days: 2);
        var registry = await _registry(directory, () => now, lifetime);
        final issued = await registry.issueToken(
          accountId: 'primary',
          deviceName: 'Phone',
        );
        final deadline = now.add(lifetime);
        now = now.add(const Duration(days: 1));
        await registry.updateProfile(
          accountId: 'primary',
          tokenId: issued.device.id,
          displayName: 'Updated profile',
        );
        await registry.recordAuthenticatedUse(
          accountId: 'primary',
          tokenId: issued.device.id,
        );
        if (persisted) {
          registry = await _registry(directory, () => now, lifetime);
        }
        now = deadline.subtract(const Duration(microseconds: 1));
        expect(registry.authenticate(issued.token), 'primary');
        now = deadline;
        expect(registry.authenticate(issued.token), isNull);
      },
    );

    test(
      '$storage rename keeps intentionally non-expiring tokens valid',
      () async {
        var now = DateTime.utc(2026, 9, 6);
        final directory = await _testDirectory(persisted);
        var registry = await _registry(directory, () => now, null);
        final issued = await registry.issueToken(
          accountId: 'primary',
          deviceName: 'Phone',
        );
        final updated = (await registry.updateProfile(
          accountId: 'primary',
          tokenId: issued.device.id,
          deviceName: 'Renamed phone',
        ))!;
        if (persisted) registry = await _registry(directory, () => now, null);
        now = now.add(const Duration(days: 4000));
        expect(registry.authenticate(issued.token), 'primary');
        expect(updated.device.toJson(), isNot(contains('expiresAt')));
      },
    );
  }

  test(
    'rotation assigns expiry to a legacy token and survives restart',
    () async {
      var now = DateTime.utc(2026, 9, 6);
      final directory = await _testDirectory(true);
      var registry = await _registry(directory, () => now, null);
      final legacy = await registry.issueToken(
        accountId: 'primary',
        deviceName: 'Phone',
      );
      registry = await _registry(
        directory,
        () => now,
        const Duration(hours: 1),
      );
      final replacement = await registry.issueToken(
        accountId: 'primary',
        deviceName: 'Phone',
        replaceTokenId: legacy.device.id,
      );
      final deadline = now.add(const Duration(hours: 1));
      registry = await _registry(
        directory,
        () => now,
        const Duration(days: 365),
      );
      expect(registry.authenticate(legacy.token), isNull);
      expect(registry.authenticate(replacement.token), 'primary');
      now = deadline;
      expect(registry.authenticate(replacement.token), isNull);
      expect(
        replacement.device.toJson()['expiresAt'],
        deadline.toIso8601String(),
      );
    },
  );

  for (final recover in [false, true]) {
    test(
      'HTTP denies expired ${recover ? 'recovered' : 'renamed'} tokens after restart',
      () async {
        var now = DateTime.utc(2026, 9, 6);
        final directory = await _testDirectory(true);
        const lifetime = Duration(hours: 1);
        var registry = await _registry(directory, () => now, lifetime);
        Handler handler() => createServerHandler(
          clock: () => now,
          syncAuthenticator: registry,
          managedSyncAccounts: registry,
          operationsAuthenticator: StaticOperationsAuthenticator(
            'expiry-test-operations',
          ),
          syncStore: MemoryLibrarySyncSnapshotStore(),
        );
        var server = handler();
        final issued = await _json(
          await server(
            _request(
              'POST',
              '/api/v1/admin/sync-tokens',
              token: 'expiry-test-operations',
              body: {'accountId': 'primary', 'deviceName': 'Phone'},
            ),
          ),
          201,
        );
        var token = issued['token'] as String;
        if (recover) {
          final recovery = await _json(
            await server(
              _request(
                'POST',
                '/api/v1/admin/sync-recovery-codes',
                token: 'expiry-test-operations',
                body: {'accountId': 'primary'},
              ),
            ),
            201,
          );
          final redeemed = await _json(
            await server(
              _request(
                'POST',
                '/api/v1/sync/recovery',
                body: {
                  'recoveryCode': recovery['recoveryCode'],
                  'deviceName': 'Recovered',
                },
              ),
            ),
            201,
          );
          token = redeemed['token'] as String;
        }
        final deadline = now.add(lifetime);
        now = now.add(const Duration(minutes: 30));
        await _json(
          await server(
            _request(
              'PATCH',
              '/api/v1/auth/profile',
              token: token,
              body: {'deviceName': 'Renamed'},
            ),
          ),
          200,
        );
        registry = await _registry(directory, () => now, lifetime);
        server = handler();
        now = deadline.subtract(const Duration(microseconds: 1));
        await _json(
          await server(_request('GET', '/api/v1/auth/profile', token: token)),
          200,
        );
        now = deadline;
        final denied = await _json(
          await server(_request('GET', '/api/v1/auth/profile', token: token)),
          401,
        );
        expect(denied['error'], 'unauthorized');
        await _json(
          await server(_request('GET', '/api/v1/sync/library', token: token)),
          401,
        );
        await _json(
          await server(
            _request(
              'PATCH',
              '/api/v1/auth/profile',
              token: token,
              body: {'deviceName': 'Cannot revive'},
            ),
          ),
          401,
        );
        final accounts = await _json(
          await server(
            _request(
              'GET',
              '/api/v1/admin/sync-accounts',
              token: 'expiry-test-operations',
            ),
          ),
          200,
        );
        final account = (accounts['accounts'] as List).single as Map;
        final device = (account['tokens'] as List).single as Map;
        expect(device['expiresAt'], deadline.toIso8601String());
        expect(jsonEncode(accounts), isNot(contains(token)));
        expect(jsonEncode(accounts), isNot(contains('sha256')));
      },
    );
  }
}

Future<Directory?> _testDirectory(bool persisted) async {
  if (!persisted) return null;
  final parent = await Directory.systemTemp.resolveSymbolicLinks();
  final directory = await Directory(
    parent,
  ).createTemp('aethertune-token-expiry-');
  addTearDown(() async {
    final canonical = await directory.resolveSymbolicLinks();
    expect(p.equals(canonical, directory.path), isTrue);
    expect(p.isWithin(parent, canonical), isTrue);
    await directory.delete(recursive: true);
  });
  return directory;
}

Future<ManagedSyncAccountRegistry> _registry(
  Directory? directory,
  DateTime Function() clock,
  Duration? lifetime,
) async => directory == null
    ? ManagedSyncAccountRegistry.memory(clock: clock, tokenLifetime: lifetime)
    : ManagedSyncAccountRegistry.open(
        directory,
        clock: clock,
        tokenLifetime: lifetime,
      );

Request _request(
  String method,
  String path, {
  String? token,
  Map<String, Object?>? body,
}) => Request(
  method,
  Uri.parse('http://localhost$path'),
  headers: {
    if (token != null) 'authorization': 'Bearer $token',
    if (body != null) 'content-type': 'application/json',
  },
  body: body == null ? null : jsonEncode(body),
);

Future<Map<String, dynamic>> _json(Response response, int status) async {
  final body = await response.readAsString();
  expect(response.statusCode, status, reason: body);
  return jsonDecode(body) as Map<String, dynamic>;
}
