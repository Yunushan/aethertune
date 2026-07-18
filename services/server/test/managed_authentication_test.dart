import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('static configuration supports several device tokens per account', () {
    final desktopDigest = sha256.convert(utf8.encode('desktop-token'));
    final authenticator = StaticSyncAuthenticator.fromJson(
      '{'
      '"primary":{'
      '"phone":"phone-token",'
      '"desktop":"sha256:$desktopDigest"'
      '},'
      '"family":["tablet-token","car-token"]'
      '}',
    );

    expect(authenticator.authenticate('phone-token'), 'primary');
    expect(authenticator.authenticate('desktop-token'), 'primary');
    expect(authenticator.authenticate('tablet-token'), 'family');
    expect(authenticator.authenticate('car-token'), 'family');
    expect(authenticator.authenticate('unknown-token'), isNull);
    expect(
      () => StaticSyncAuthenticator.fromJson('{"primary":[42]}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => StaticSyncAuthenticator.fromJson(
        '{"primary":"shared-token","other":"shared-token"}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('default managed tokens carry 256 bits of secure random material',
      () async {
    final registry = ManagedSyncAccountRegistry.memory();
    final issued = await registry.issueToken(
      accountId: 'primary',
      deviceName: 'Phone',
    );
    final encoded = issued.token.substring('at_'.length);
    final padded = encoded.padRight((encoded.length + 3) ~/ 4 * 4, '=');

    expect(issued.token, startsWith('at_'));
    expect(base64Url.decode(padded), hasLength(32));
    expect(registry.authenticate(issued.token), 'primary');
  });

  test('managed token expiry is opt-in and enforced at its boundary',
      () async {
    var current = DateTime.utc(2026, 7, 18, 12);
    final registry = ManagedSyncAccountRegistry.memory(
      clock: () => current,
      tokenGenerator: () => 'at_expiry_secret',
      tokenLifetime: const Duration(hours: 1),
    );
    final issued = await registry.issueToken(
      accountId: 'primary',
      deviceName: 'Phone',
    );

    expect(registry.authenticate(issued.token), 'primary');
    current = current.add(const Duration(minutes: 59, seconds: 59));
    expect(registry.authenticate(issued.token), 'primary');
    current = current.add(const Duration(seconds: 1));
    expect(registry.authenticate(issued.token), isNull);
  });

  test('recovery code is single-use and replaces every device token', () async {
    final generatedTokens = Queue<String>.of(<String>[
      'at_original_secret',
      'at_recovered_secret',
    ]);
    final registry = ManagedSyncAccountRegistry.memory(
      tokenGenerator: generatedTokens.removeFirst,
      recoveryCodeGenerator: () => 'ar_recovery_secret',
    );
    final original = await registry.issueToken(
      accountId: 'primary',
      deviceName: 'Lost phone',
    );
    final recovery = await registry.issueRecoveryCode(accountId: 'primary');

    final recovered = await registry.redeemRecoveryCode(
      code: recovery.code,
      deviceName: 'Replacement phone',
    );

    expect(recovered, isNotNull);
    expect(recovered!.token, 'at_recovered_secret');
    expect(registry.authenticate(original.token), isNull);
    expect(registry.authenticate(recovered.token), 'primary');
    expect(registry.account('primary')!.tokens, hasLength(1));
    expect(registry.account('primary')!.tokens.single.deviceName, 'Replacement phone');
    expect(
      await registry.redeemRecoveryCode(
        code: recovery.code,
        deviceName: 'Another phone',
      ),
      isNull,
    );
  });

  test('recovery code remains digest-only and redeemable after restart',
      () async {
    final root = await Directory.systemTemp.createTemp('aethertune-recovery-');
    addTearDown(() => root.delete(recursive: true));
    final registry = await ManagedSyncAccountRegistry.open(
      root,
      tokenGenerator: () => 'at_recovered_after_restart',
      recoveryCodeGenerator: () => 'ar_restart_secret',
    );
    await registry.issueToken(accountId: 'primary', deviceName: 'Lost phone');
    final recovery = await registry.issueRecoveryCode(accountId: 'primary');
    final registryFile = await root
        .list()
        .where(
          (entity) => entity is File &&
              RegExp(r'^registry-\d+\.json$')
                  .hasMatch(entity.uri.pathSegments.last),
        )
        .cast<File>()
        .single;
    final stored = await registryFile.readAsString();

    expect(stored, isNot(contains(recovery.code)));

    final restarted = await ManagedSyncAccountRegistry.open(
      root,
      tokenGenerator: () => 'at_recovered_after_restart',
    );
    final redeemed = await restarted.redeemRecoveryCode(
      code: recovery.code,
      deviceName: 'Replacement phone',
    );

    expect(redeemed?.token, 'at_recovered_after_restart');
    expect(
      await restarted.redeemRecoveryCode(
        code: recovery.code,
        deviceName: 'Another phone',
      ),
      isNull,
    );
  });

  test('validates the managed token lifetime environment setting', () {
    expect(managedTokenLifetimeFromEnvironment(const <String, String>{}), isNull);
    expect(
      managedTokenLifetimeFromEnvironment(
        const <String, String>{'AETHERTUNE_MANAGED_TOKEN_TTL_DAYS': '30'},
      ),
      const Duration(days: 30),
    );
    expect(
      () => managedTokenLifetimeFromEnvironment(
        const <String, String>{'AETHERTUNE_MANAGED_TOKEN_TTL_DAYS': '0'},
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('records managed device activity at a bounded durable cadence',
      () async {
    var current = DateTime.utc(2026, 7, 16, 8);
    final root = await Directory.systemTemp.createTemp(
      'aethertune-managed-activity-',
    );
    addTearDown(() => root.delete(recursive: true));
    final registry = await ManagedSyncAccountRegistry.open(
      root,
      clock: () => current,
      tokenGenerator: () => 'at_activity_secret',
    );
    final issued = await registry.issueToken(
      accountId: 'primary',
      deviceName: 'Phone',
    );

    expect(
      await registry.recordAuthenticatedUse(
        accountId: 'primary',
        tokenId: issued.device.id,
      ),
      isTrue,
    );
    expect(
      registry.account('primary')!.tokens.single.lastAuthenticatedAt,
      current,
    );

    current = current.add(const Duration(hours: 23));
    expect(
      await registry.recordAuthenticatedUse(
        accountId: 'primary',
        tokenId: issued.device.id,
      ),
      isFalse,
    );
    current = current.add(const Duration(hours: 1));
    expect(
      await registry.recordAuthenticatedUse(
        accountId: 'primary',
        tokenId: issued.device.id,
      ),
      isTrue,
    );

    final restarted = await ManagedSyncAccountRegistry.open(root);
    expect(
      restarted.account('primary')!.tokens.single.lastAuthenticatedAt,
      current,
    );
  });

  test('managed profile updates persist without changing token identity',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'aethertune-managed-profile-',
    );
    addTearDown(() => root.delete(recursive: true));
    final registry = await ManagedSyncAccountRegistry.open(
      root,
      clock: () => DateTime.utc(2026, 7, 15, 9),
      tokenGenerator: Queue<String>.from(<String>[
        'at_profile_phone_secret',
        'at_profile_desktop_secret',
      ]).removeFirst,
    );
    final phone = await registry.issueToken(
      accountId: 'primary',
      displayName: 'Original account',
      deviceName: 'Phone',
    );
    await registry.issueToken(
      accountId: 'primary',
      deviceName: 'Desktop',
    );

    final updated = await registry.updateProfile(
      accountId: 'primary',
      tokenId: phone.device.id,
      displayName: 'Updated account',
      deviceName: 'Pocket player',
    );

    expect(updated?.account.displayName, 'Updated account');
    expect(updated?.device.id, phone.device.id);
    expect(updated?.device.deviceName, 'Pocket player');
    expect(updated?.device.createdAt, phone.device.createdAt);
    expect(registry.authenticate(phone.token), 'primary');
    await expectLater(
      registry.updateProfile(
        accountId: 'primary',
        tokenId: phone.device.id,
        deviceName: 'Desktop',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      registry.account('primary')!.tokens.first.deviceName,
      'Pocket player',
    );

    await registry.updateProfile(
      accountId: 'primary',
      tokenId: phone.device.id,
      displayName: 'Updated account',
      deviceName: 'Pocket player',
    );
    expect((await _registryFiles(root)).single.path, endsWith('registry-3.json'));

    final restarted = await ManagedSyncAccountRegistry.open(root);
    expect(restarted.authenticate(phone.token), 'primary');
    expect(restarted.account('primary')?.displayName, 'Updated account');
    expect(
      restarted.account('primary')!.tokens.first.deviceName,
      'Pocket player',
    );
  });

  test('failed managed profile persistence leaves active state unchanged',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'aethertune-managed-profile-rollback-',
    );
    addTearDown(() => root.delete(recursive: true));
    final registry = await ManagedSyncAccountRegistry.open(
      root,
      tokenGenerator: () => 'at_profile_rollback_secret',
    );
    final issued = await registry.issueToken(
      accountId: 'primary',
      displayName: 'Original account',
      deviceName: 'Phone',
    );
    await Directory('${root.path}${Platform.pathSeparator}registry-2.json')
        .create();

    await expectLater(
      registry.updateProfile(
        accountId: 'primary',
        tokenId: issued.device.id,
        displayName: 'Uncommitted account',
        deviceName: 'Uncommitted device',
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(registry.account('primary')?.displayName, 'Original account');
    expect(registry.account('primary')?.tokens.single.deviceName, 'Phone');
    expect(registry.authenticate(issued.token), 'primary');
  });

  test('managed registry persists one-time device tokens and lifecycle changes',
      () async {
    final root = await Directory.systemTemp.createTemp(
      'aethertune-managed-auth-',
    );
    addTearDown(() => root.delete(recursive: true));
    var now = DateTime.utc(2026, 7, 15, 10);
    final generated = Queue<String>.from(<String>[
      'at_phone_original_secret',
      'at_desktop_secret',
      'at_phone_rotated_secret',
    ]);
    final registry = await ManagedSyncAccountRegistry.open(
      root,
      clock: () => now,
      tokenGenerator: generated.removeFirst,
    );

    final phone = await registry.issueToken(
      accountId: 'primary',
      displayName: 'Primary listener',
      deviceName: 'Phone',
    );
    now = now.add(const Duration(minutes: 1));
    final desktop = await registry.issueToken(
      accountId: 'primary',
      deviceName: 'Desktop',
    );

    expect(phone.token, 'at_phone_original_secret');
    expect(registry.authenticate(phone.token), 'primary');
    expect(registry.authenticate(desktop.token), 'primary');
    expect(registry.accounts, hasLength(1));
    expect(
      registry.accounts.single.tokens.map((token) => token.deviceName),
      <String>['Phone', 'Desktop'],
    );

    final storedAfterIssue =
        await (await _onlyRegistryFile(root)).readAsString();
    expect(storedAfterIssue, isNot(contains(phone.token)));
    expect(storedAfterIssue, isNot(contains(desktop.token)));
    expect(storedAfterIssue, contains('"sha256"'));

    final restarted = await ManagedSyncAccountRegistry.open(
      root,
      clock: () => now,
      tokenGenerator: generated.removeFirst,
    );
    expect(restarted.authenticate(phone.token), 'primary');
    expect(restarted.authenticate(desktop.token), 'primary');

    expect(
      () => restarted.issueToken(
        accountId: 'primary',
        deviceName: 'Phone',
        replaceTokenId: 'does-not-exist',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(restarted.authenticate(phone.token), 'primary');

    now = now.add(const Duration(minutes: 1));
    final rotated = await restarted.issueToken(
      accountId: 'primary',
      deviceName: 'Phone',
      replaceTokenId: phone.device.id,
    );
    expect(rotated.replacedTokenId, phone.device.id);
    expect(restarted.authenticate(phone.token), isNull);
    expect(restarted.authenticate(rotated.token), 'primary');
    expect(restarted.authenticate(desktop.token), 'primary');

    expect(
      await restarted.revokeToken(
        accountId: 'primary',
        tokenId: desktop.device.id,
      ),
      isTrue,
    );
    expect(restarted.authenticate(desktop.token), isNull);
    expect(
      await restarted.revokeToken(
        accountId: 'primary',
        tokenId: desktop.device.id,
      ),
      isFalse,
    );

    final afterLifecycleRestart = await ManagedSyncAccountRegistry.open(root);
    expect(afterLifecycleRestart.authenticate(rotated.token), 'primary');
    expect(afterLifecycleRestart.authenticate(phone.token), isNull);
    expect(afterLifecycleRestart.authenticate(desktop.token), isNull);
    expect(
      (await _registryFiles(root)).single.path,
      endsWith('registry-4.json'),
    );
  });

  test('managed admin APIs issue, rotate, revoke, and share account snapshots',
      () async {
    final generated = Queue<String>.from(<String>[
      'at_api_phone_secret',
      'at_api_desktop_secret',
      'at_api_phone_rotated_secret',
    ]);
    final accounts = ManagedSyncAccountRegistry.memory(
      clock: () => DateTime.utc(2026, 7, 15, 12),
      tokenGenerator: generated.removeFirst,
    );
    final logs = <ServerRequestLogEntry>[];
    final handler = createServerHandler(
      clock: () => DateTime.utc(2026, 7, 15, 12),
      syncAuthenticator: accounts,
      managedSyncAccounts: accounts,
      operationsAuthenticator: StaticOperationsAuthenticator('ops-secret'),
      syncStore: MemoryLibrarySyncSnapshotStore(),
      requestLogger: logs.add,
    );

    final rejected = await handler(
      _request(
        'POST',
        '/api/v1/admin/sync-tokens',
        token: 'wrong-ops-secret',
        body: <String, Object?>{
          'accountId': 'primary',
          'deviceName': 'Phone',
        },
      ),
    );
    expect(rejected.statusCode, 401);

    final phoneIssue = await handler(
      _request(
        'POST',
        '/api/v1/admin/sync-tokens',
        token: 'ops-secret',
        body: <String, Object?>{
          'accountId': 'primary',
          'displayName': 'Primary listener',
          'deviceName': 'Phone',
        },
      ),
    );
    final phoneIssueBody = await _json(phoneIssue);
    final phoneToken = phoneIssueBody['token'] as String;
    final phoneDevice = phoneIssueBody['device'] as Map<String, dynamic>;
    expect(phoneIssue.statusCode, 201);
    expect(phoneIssueBody['tokenType'], 'Bearer');

    final desktopIssue = await handler(
      _request(
        'POST',
        '/api/v1/admin/sync-tokens',
        token: 'ops-secret',
        body: <String, Object?>{
          'accountId': 'primary',
          'deviceName': 'Desktop',
        },
      ),
    );
    final desktopIssueBody = await _json(desktopIssue);
    final desktopToken = desktopIssueBody['token'] as String;
    final desktopDevice = desktopIssueBody['device'] as Map<String, dynamic>;
    expect(desktopIssue.statusCode, 201);

    final upload = await handler(
      _request(
        'PUT',
        '/api/v1/sync/library',
        token: phoneToken,
        body: <String, Object?>{
          'baseRevision': 0,
          'deviceId': 'phone',
          'snapshot': _syncSnapshot(),
        },
      ),
    );
    expect(upload.statusCode, 200);

    final desktopDownload = await handler(
      _request('GET', '/api/v1/sync/library', token: desktopToken),
    );
    final desktopDownloadBody = await _json(desktopDownload);
    expect(desktopDownload.statusCode, 200);
    expect(desktopDownloadBody['revision'], 1);
    expect(
      (desktopDownloadBody['snapshot'] as Map<String, dynamic>)['name'],
      'Shared account library',
    );

    final profile = await handler(
      _request('GET', '/api/v1/auth/profile', token: desktopToken),
    );
    final profileBody = await _json(profile);
    expect(profile.statusCode, 200);
    expect(
      profileBody['account'],
      <String, Object?>{
        'id': 'primary',
        'displayName': 'Primary listener',
        'managed': true,
        'editable': true,
      },
    );
    expect(
      (profileBody['device'] as Map<String, dynamic>)['deviceName'],
      'Desktop',
    );
    expect(
      (profileBody['device'] as Map<String, dynamic>)['lastAuthenticatedAt'],
      '2026-07-15T12:00:00.000Z',
    );

    final profileUpdate = await handler(
      _request(
        'PATCH',
        '/api/v1/auth/profile',
        token: desktopToken,
        body: <String, Object?>{
          'displayName': 'Shared listeners',
          'deviceName': 'Workstation',
        },
      ),
    );
    final profileUpdateText = await profileUpdate.readAsString();
    final profileUpdateBody =
        jsonDecode(profileUpdateText) as Map<String, dynamic>;
    expect(profileUpdate.statusCode, 200);
    expect(
      (profileUpdateBody['account'] as Map)['displayName'],
      'Shared listeners',
    );
    expect(
      (profileUpdateBody['device'] as Map)['deviceName'],
      'Workstation',
    );
    expect(profileUpdateText, isNot(contains(desktopToken)));
    expect(profileUpdateText, isNot(contains('sha256')));

    final phoneProfile = await handler(
      _request('GET', '/api/v1/auth/profile', token: phoneToken),
    );
    final phoneProfileBody = await _json(phoneProfile);
    expect(
      (phoneProfileBody['account'] as Map)['displayName'],
      'Shared listeners',
    );
    expect(
      (phoneProfileBody['device'] as Map)['deviceName'],
      'Phone',
    );

    final duplicateDeviceUpdate = await handler(
      _request(
        'PATCH',
        '/api/v1/auth/profile',
        token: desktopToken,
        body: <String, Object?>{'deviceName': 'Phone'},
      ),
    );
    expect(duplicateDeviceUpdate.statusCode, 400);
    expect(
      (await _json(duplicateDeviceUpdate))['error'],
      'invalid_auth_request',
    );

    final emptyProfileUpdate = await handler(
      _request(
        'PATCH',
        '/api/v1/auth/profile',
        token: desktopToken,
        body: const <String, Object?>{},
      ),
    );
    expect(emptyProfileUpdate.statusCode, 400);
    expect(
      (await _json(emptyProfileUpdate))['error'],
      'invalid_auth_request',
    );

    final oversizedProfileUpdate = await handler(
      Request(
        'PATCH',
        Uri.parse('http://localhost/api/v1/auth/profile'),
        headers: <String, String>{
          'authorization': 'Bearer $desktopToken',
          'content-type': 'application/json',
        },
        body: Stream<List<int>>.value(
          List<int>.filled(maxManagedAuthRequestBytes + 1, 0),
        ),
      ),
    );
    expect(oversizedProfileUpdate.statusCode, 413);
    expect(
      (await _json(oversizedProfileUpdate))['error'],
      'payload_too_large',
    );

    final accountList = await handler(
      _request(
        'GET',
        '/api/v1/admin/sync-accounts',
        token: 'ops-secret',
      ),
    );
    final accountListText = await accountList.readAsString();
    final accountListBody = jsonDecode(accountListText) as Map<String, dynamic>;
    final listedAccount =
        (accountListBody['accounts'] as List<dynamic>).single as Map;
    expect(listedAccount['displayName'], 'Shared listeners');
    expect(
      (listedAccount['tokens'] as List<dynamic>)
          .map((token) => (token as Map)['deviceName']),
      <String>['Phone', 'Workstation'],
    );
    expect((listedAccount['tokens'] as List<dynamic>), hasLength(2));
    expect(accountListText, isNot(contains(phoneToken)));
    expect(accountListText, isNot(contains(desktopToken)));
    expect(accountListText, isNot(contains('sha256')));

    final rotation = await handler(
      _request(
        'POST',
        '/api/v1/admin/sync-tokens',
        token: 'ops-secret',
        body: <String, Object?>{
          'accountId': 'primary',
          'deviceName': 'Phone',
          'replaceTokenId': phoneDevice['id'],
        },
      ),
    );
    final rotationBody = await _json(rotation);
    final rotatedPhoneToken = rotationBody['token'] as String;
    expect(rotation.statusCode, 201);
    expect(rotationBody['replacedTokenId'], phoneDevice['id']);
    expect(
      (await handler(
        _request('GET', '/api/v1/auth/profile', token: phoneToken),
      ))
          .statusCode,
      401,
    );
    expect(
      (await handler(
        _request('GET', '/api/v1/auth/profile', token: rotatedPhoneToken),
      ))
          .statusCode,
      200,
    );

    final revocation = await handler(
      _request(
        'DELETE',
        '/api/v1/admin/sync-tokens',
        token: 'ops-secret',
        body: <String, Object?>{
          'accountId': 'primary',
          'tokenId': desktopDevice['id'],
        },
      ),
    );
    expect(revocation.statusCode, 200);
    expect(
      (await handler(
        _request('GET', '/api/v1/auth/profile', token: desktopToken),
      ))
          .statusCode,
      401,
    );

    final logText = jsonEncode(
      logs.map((entry) => entry.toJson()).toList(growable: false),
    );
    expect(logText, isNot(contains('primary')));
    expect(logText, isNot(contains(phoneToken)));
    expect(logText, isNot(contains(desktopToken)));
    expect(
      logs.map((entry) => entry.route),
      containsAll(<String>[
        '/api/v1/admin/sync-tokens',
        '/api/v1/admin/sync-accounts',
        '/api/v1/auth/profile',
        '/api/v1/sync/library',
      ]),
    );
  });

  test('managed administration fails closed without operations auth', () async {
    final accounts = ManagedSyncAccountRegistry.memory(
      tokenGenerator: () => 'at_unused_secret',
    );
    final response = await createServerHandler(
      syncAuthenticator: accounts,
      managedSyncAccounts: accounts,
    )(
      _request(
        'POST',
        '/api/v1/admin/sync-tokens',
        body: <String, Object?>{
          'accountId': 'primary',
          'deviceName': 'Phone',
        },
      ),
    );

    expect(response.statusCode, 503);
    expect(
      (await _json(response))['error'],
      'operations_auth_not_configured',
    );
    expect(accounts.isConfigured, isFalse);
  });

  test('static sync credentials cannot mutate managed profile metadata',
      () async {
    final authenticator = StaticSyncAuthenticator.fromJson(
      '{"static-account":"static-token"}',
    );
    final response = await createServerHandler(
      syncAuthenticator: authenticator,
    )(
      _request(
        'PATCH',
        '/api/v1/auth/profile',
        token: 'static-token',
        body: <String, Object?>{'displayName': 'Not persisted'},
      ),
    );

    expect(response.statusCode, 409);
    expect((await _json(response))['error'], 'profile_not_managed');
  });

  test('static identity wins without managed rights for an overlapping token',
      () async {
    final accounts = ManagedSyncAccountRegistry.memory(
      tokenGenerator: () => 'overlapping-token',
    );
    await accounts.issueToken(
      accountId: 'managed-account',
      displayName: 'Managed account',
      deviceName: 'Managed device',
    );
    final staticAccounts = StaticSyncAuthenticator.fromJson(
      '{"static-account":"overlapping-token"}',
    );
    final authenticator = CompositeSyncAuthenticator(
      <SyncAuthenticator>[staticAccounts, accounts],
    );
    final handler = createServerHandler(
      syncAuthenticator: authenticator,
      managedSyncAccounts: accounts,
    );

    final profile = await handler(
      _request(
        'GET',
        '/api/v1/auth/profile',
        token: 'overlapping-token',
      ),
    );
    final profileBody = await _json(profile);
    expect((profileBody['account'] as Map)['id'], 'static-account');
    expect((profileBody['account'] as Map)['managed'], isFalse);
    expect((profileBody['account'] as Map)['editable'], isFalse);
    expect(profileBody['device'], isNull);

    final update = await handler(
      _request(
        'PATCH',
        '/api/v1/auth/profile',
        token: 'overlapping-token',
        body: <String, Object?>{'displayName': 'Escalated account'},
      ),
    );
    expect(update.statusCode, 409);
    expect(accounts.account('managed-account')?.displayName, 'Managed account');
  });
}

Request _request(
  String method,
  String path, {
  String? token,
  Map<String, Object?>? body,
}) {
  return Request(
    method,
    Uri.parse('http://localhost$path'),
    headers: <String, String>{
      if (token != null) 'authorization': 'Bearer $token',
      if (body != null) 'content-type': 'application/json',
    },
    body: body == null ? null : jsonEncode(body),
  );
}

Map<String, Object?> _syncSnapshot() => <String, Object?>{
      'syncVersion': 1,
      'version': 1,
      'name': 'Shared account library',
      'tracks': <Object?>[],
      'offlineCacheQueue': <Object?>[],
    };

Future<Map<String, dynamic>> _json(Response response) async {
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}

Future<List<File>> _registryFiles(Directory root) async {
  return root
      .list()
      .where((entity) => entity is File && entity.path.endsWith('.json'))
      .cast<File>()
      .toList();
}

Future<File> _onlyRegistryFile(Directory root) async {
  return (await _registryFiles(root)).single;
}
