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

  test('redeems a recovery code without bearer authentication', () async {
    Uri? uri;
    Map<String, String>? capturedHeaders;
    String? requestBody;

    final token = await redeemLibrarySyncRecoveryCode(
      _account(),
      'ar_recovery_secret',
      httpExecutor: (method, capturedUri, {required headers, String? body}) async {
        expect(method, 'POST');
        uri = capturedUri;
        capturedHeaders = headers;
        requestBody = body;
        return const LibrarySyncHttpResponse(
          statusCode: 201,
          body: '{"token":"at_recovered_secret"}',
        );
      },
    );

    expect(uri, _account().recoveryEndpointUri);
    expect(capturedHeaders?['authorization'], isNull);
    expect(jsonDecode(requestBody!) as Map<String, dynamic>, <String, dynamic>{
      'recoveryCode': 'ar_recovery_secret',
      'deviceName': _account().deviceId,
    });
    expect(token, 'at_recovered_secret');
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
    const session = ListenTogetherSession(
      trackIds: <String>['track-1', 'track-2'],
      currentTrackId: 'track-1',
      position: Duration(seconds: 12),
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
        session: const ListenTogetherSession(
          trackIds: <String>['track-1'],
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

  test('issues and reads cross-account listen-together invites', () async {
    const inviteCode = 'AAAAAAAAAAAAAAAAAAAAAAAA';
    const session = ListenTogetherSession(
      trackIds: <String>['track-1'],
      currentTrackId: 'track-1',
      position: Duration(seconds: 5),
      playing: true,
    );
    final client = LibrarySyncClient(
      account: _account(),
      token: 'private-sync-token',
      httpExecutor: (method, uri, {required headers, body}) async {
        if (method == 'POST') {
          expect(uri, _account().listenTogetherInviteIssueEndpointUri);
          return LibrarySyncHttpResponse(
            statusCode: 201,
            body: jsonEncode(<String, Object?>{'inviteCode': inviteCode}),
          );
        }
        expect(method, 'GET');
        expect(uri, _account().listenTogetherInviteEndpointUri(inviteCode));
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'revision': 2,
            'session': session.toJson(),
          }),
        );
      },
    );

    expect(await client.issueListenTogetherInvite(), inviteCode);
    final remote = await client.fetchListenTogetherInvite(inviteCode);
    expect(remote.revision, 2);
    expect(remote.session?.currentTrackId, 'track-1');
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
              'avatarTone': 'emerald',
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
    expect(profile?.avatarTone, LibrarySyncProfileAvatarTone.emerald);
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
              '"avatarTone":"violet",'
              '"publicProfileEnabled":true,'
              '"publicProfileFieldAudienceSupported":true,'
              '"publicDisplayNameEnabled":true,'
              '"publicAvatarToneEnabled":false,'
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
      avatarTone: LibrarySyncProfileAvatarTone.violet,
      includeAvatarTone: true,
      publicDisplayNameEnabled: true,
      includePublicDisplayNameEnabled: true,
      publicAvatarToneEnabled: false,
      includePublicAvatarToneEnabled: true,
    );

    expect(requestedMethod, 'PATCH');
    expect(requestedUri, _account().profileEndpointUri);
    expect(requestedHeaders?['authorization'], 'Bearer $token');
    expect(requestedHeaders?['content-type'], 'application/json');
    expect(requestedBody, <String, Object?>{
      'displayName': 'Shared listeners',
      'deviceName': 'Pocket player',
      'avatarTone': 'violet',
      'publicDisplayNameEnabled': true,
      'publicAvatarToneEnabled': false,
    });
    expect(jsonEncode(requestedBody), isNot(contains(token)));
    expect(updated.effectiveDisplayName, 'Shared listeners');
    expect(updated.avatarTone, LibrarySyncProfileAvatarTone.violet);
    expect(updated.avatarToneSupported, isTrue);
    expect(updated.publicProfileFieldAudienceSupported, isTrue);
    expect(updated.publicDisplayNameEnabled, isTrue);
    expect(updated.publicAvatarToneEnabled, isFalse);
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
    expect(legacyManagedProfile.avatarTone, isNull);
    expect(legacyManagedProfile.avatarToneSupported, isFalse);
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
    expect(
      () => LibrarySyncProfile.fromServerJson(<String, Object?>{
        'account': <String, Object?>{
          'id': 'primary',
          'managed': true,
          'avatarTone': 'not-a-tone',
        },
        'device': <String, Object?>{
          'id': '0123456789abcdef01234567',
          'deviceName': 'Desktop',
          'createdAt': '2026-07-15T12:00:00.000Z',
        },
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

  test('omits avatar changes for a profile API that did not advertise them',
      () async {
    Map<String, Object?>? requestBody;
    final client = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        requestBody = jsonDecode(body!) as Map<String, Object?>;
        return const LibrarySyncHttpResponse(
          statusCode: 200,
          body: '{'
              '"account":{'
              '"id":"primary",'
              '"displayName":"Older server",'
              '"managed":true,'
              '"editable":true'
              '},'
              '"device":{'
              '"id":"0123456789abcdef01234567",'
              '"deviceName":"Desktop",'
              '"createdAt":"2026-07-15T12:00:00.000Z"'
              '}'
              '}',
        );
      },
    );

    final profile = await client.updateProfile(
      displayName: 'Older server',
      deviceName: 'Desktop',
    );

    expect(requestBody, <String, Object?>{
      'displayName': 'Older server',
      'deviceName': 'Desktop',
    });
    expect(profile.avatarToneSupported, isFalse);
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

  test('creates a private shared playlist with a portable document', () async {
    final playlist = <String, Object?>{
      'version': 1,
      'name': 'Collaborative mix',
      'trackIds': <String>['track-1', 'track-2'],
    };
    final checksum = sha256.convert(utf8.encode(jsonEncode(playlist))).toString();
    final client = LibrarySyncClient(
      account: _account(),
      token: 'private-sync-token',
      httpExecutor: (method, uri, {required headers, body}) async {
        expect(method, 'POST');
        expect(uri, _account().sharedPlaylistCollectionEndpointUri);
        expect(headers['authorization'], 'Bearer private-sync-token');
        expect(jsonDecode(body!), <String, Object?>{
          'baseRevision': 0,
          'deviceId': 'Test device',
          'playlist': playlist,
        });
        return LibrarySyncHttpResponse(
          statusCode: 201,
          body: jsonEncode(<String, Object?>{
            'id': 'AAAAAAAAAAAAAAAAAAAAAAAA',
            'revision': 1,
            'role': 'owner',
            'updatedAt': '2026-07-17T10:00:00.000Z',
            'updatedByDevice': 'Test device',
            'checksum': checksum,
            'playlist': playlist,
            'collaborators': <String, Object?>{},
          }),
        );
      },
    );

    final shared = await client.createSharedPlaylist(
      name: 'Collaborative mix',
      trackIds: <String>['track-1', 'track-2'],
    );

    expect(shared.id, 'AAAAAAAAAAAAAAAAAAAAAAAA');
    expect(shared.role, SharedPlaylistAccessRole.owner);
    expect(shared.trackIds, <String>['track-1', 'track-2']);
    expect(shared.collaborators, isEmpty);
  });

  test('creates and parses a private shared smart-playlist definition', () async {
    final rule = <String, Object?>{
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
    };
    final document = <String, Object?>{
      'version': 2,
      'kind': 'smart',
      'name': 'Mira discoveries',
      'rule': rule,
    };
    final checksum = sha256.convert(utf8.encode(jsonEncode(document))).toString();
    final client = LibrarySyncClient(
      account: _account(),
      token: 'private-sync-token',
      httpExecutor: (method, uri, {required headers, body}) async {
        expect(method, 'POST');
        expect(jsonDecode(body!)['playlist'], document);
        return LibrarySyncHttpResponse(
          statusCode: 201,
          body: jsonEncode(<String, Object?>{
            'id': 'AAAAAAAAAAAAAAAAAAAAAAAA',
            'revision': 1,
            'role': 'owner',
            'updatedAt': '2026-07-20T12:00:00.000Z',
            'updatedByDevice': 'Test device',
            'checksum': checksum,
            'playlist': document,
            'collaborators': <String, Object?>{},
          }),
        );
      },
    );

    final shared = await client.createSharedSmartPlaylist(
      name: 'Mira discoveries',
      rule: rule,
    );

    expect(shared.kind, SharedPlaylistKind.smart);
    expect(shared.trackIds, isEmpty);
    expect(shared.smartPlaylist?.name, 'Mira discoveries');
    expect(shared.smartPlaylist?.rule['artist'], 'Mira');
  });

  test('issues private shared playlist invites and reports conflicts', () async {
    var requests = 0;
    final client = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        requests += 1;
        if (requests == 1) {
          expect(method, 'POST');
          expect(
            uri,
            _account().sharedPlaylistInviteIssueEndpointUri(
              'AAAAAAAAAAAAAAAAAAAAAAAA',
            ),
          );
          expect(jsonDecode(body!), <String, Object?>{'role': 'editor'});
          return const LibrarySyncHttpResponse(
            statusCode: 201,
            body: '{"inviteCode":"BBBBBBBBBBBBBBBBBBBBBBBB","role":"editor","expiresAt":"2026-07-24T10:00:00.000Z"}',
          );
        }
        expect(method, 'PUT');
        return const LibrarySyncHttpResponse(
          statusCode: 409,
          body: '{"currentRevision":4,"updatedByDevice":"Other device"}',
        );
      },
    );

    final invitation = await client.issueSharedPlaylistInvite(
      playlistId: 'AAAAAAAAAAAAAAAAAAAAAAAA',
      role: SharedPlaylistAccessRole.editor,
    );
    expect(invitation.code, 'BBBBBBBBBBBBBBBBBBBBBBBB');
    expect(invitation.role, SharedPlaylistAccessRole.editor);
    expect(invitation.expiresAt, DateTime.utc(2026, 7, 24, 10));
    await expectLater(
      client.updateSharedPlaylist(
        playlistId: 'AAAAAAAAAAAAAAAAAAAAAAAA',
        baseRevision: 3,
        name: 'Collaborative mix',
        trackIds: const <String>['track-1'],
      ),
      throwsA(
        isA<SharedPlaylistConflictException>()
            .having((error) => error.currentRevision, 'current revision', 4),
      ),
    );
  });

  test('revokes a shared playlist collaborator against the current revision',
      () async {
    final playlist = <String, Object?>{
      'version': 1,
      'name': 'Collaborative mix',
      'trackIds': <String>['track-1'],
    };
    final checksum = sha256.convert(utf8.encode(jsonEncode(playlist))).toString();
    final client = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        expect(method, 'DELETE');
        expect(
          uri,
          _account().sharedPlaylistCollaboratorEndpointUri(
            'AAAAAAAAAAAAAAAAAAAAAAAA',
            'viewer-account',
          ),
        );
        expect(jsonDecode(body!), <String, Object?>{
          'baseRevision': 4,
          'deviceId': 'Test device',
        });
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'id': 'AAAAAAAAAAAAAAAAAAAAAAAA',
            'revision': 5,
            'role': 'owner',
            'updatedAt': '2026-07-17T11:00:00.000Z',
            'updatedByDevice': 'Test device',
            'checksum': checksum,
            'playlist': playlist,
            'collaborators': <String, Object?>{},
          }),
        );
      },
    );

    final remote = await client.revokeSharedPlaylistCollaborator(
      playlistId: 'AAAAAAAAAAAAAAAAAAAAAAAA',
      collaboratorId: 'viewer-account',
      baseRevision: 4,
    );

    expect(remote.revision, 5);
    expect(remote.collaborators, isEmpty);
  });

  test('invalidates outstanding shared playlist invitation codes', () async {
    final client = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        expect(method, 'DELETE');
        expect(
          uri,
          _account().sharedPlaylistInviteIssueEndpointUri(
            'AAAAAAAAAAAAAAAAAAAAAAAA',
          ),
        );
        expect(body, isNull);
        return const LibrarySyncHttpResponse(
          statusCode: 200,
          body: '{"invalidated":2}',
        );
      },
    );

    expect(
      await client.invalidateSharedPlaylistInvites(
        playlistId: 'AAAAAAAAAAAAAAAAAAAAAAAA',
      ),
      2,
    );
  });

  test('fetches checksum-verified shared playlist revision history', () async {
    final playlist = <String, Object?>{
      'version': 1,
      'name': 'Archive mix',
      'trackIds': <String>['track-1', 'track-2'],
    };
    final checksum = sha256.convert(utf8.encode(jsonEncode(playlist))).toString();
    final client = LibrarySyncClient(
      account: _account(),
      token: 'token',
      httpExecutor: (method, uri, {required headers, body}) async {
        expect(method, 'GET');
        expect(
          uri,
          _account().sharedPlaylistHistoryEndpointUri(
            'AAAAAAAAAAAAAAAAAAAAAAAA',
          ),
        );
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'revisions': <Object?>[
              <String, Object?>{
                'revision': 3,
                'updatedAt': '2026-07-17T12:00:00.000Z',
                'updatedByDevice': 'Desktop',
                'checksum': checksum,
                'playlist': playlist,
              },
              <String, Object?>{
                'revision': 2,
                'updatedAt': '2026-07-17T11:00:00.000Z',
                'updatedByDevice': 'Phone',
                'checksum': checksum,
                'playlist': playlist,
              },
            ],
          }),
        );
      },
    );

    final history = await client.fetchSharedPlaylistHistory(
      'AAAAAAAAAAAAAAAAAAAAAAAA',
    );

    expect(history.map((revision) => revision.revision), <int>[3, 2]);
    expect(history.first.trackIds, <String>['track-1', 'track-2']);
  });
}

LibrarySyncAccount _account() {
  return createLibrarySyncAccount(
    baseUrl: 'https://sync.example.test/base',
    deviceId: 'Test device',
    allowInsecureHttp: false,
  );
}
