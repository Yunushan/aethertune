import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/data/shared_smart_playlist_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('keeps existing private bindings when metadata upgrades', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.shared_smart_playlists.v1': jsonEncode(<Object?>[
        <String, Object?>{
          'remoteId': 'AAAAAAAAAAAAAAAAAAAAAAAA',
          'localSmartPlaylistId': 'legacy-local-rule',
          'revision': 1,
          'role': 'owner',
        },
      ]),
    });
    final store = SharedSmartPlaylistStore();

    await store.load();

    expect(store.bindings, hasLength(1));
    expect(store.bindings.single.localSmartPlaylistId, 'legacy-local-rule');
    expect(store.publicSubscriptions, isEmpty);
  });

  test('hosts only a portable smart-playlist rule definition', () async {
    final library = LibraryStore();
    await library.load();
    final local = await library.createCustomSmartPlaylist(
      name: 'Mira discoveries',
      artist: 'Mira',
      ruleGroups: <CustomSmartPlaylistRuleGroup>[
        CustomSmartPlaylistRuleGroup(
          rules: const <CustomSmartPlaylistRule>[
            CustomSmartPlaylistRule(
              field: CustomSmartPlaylistRuleField.genre,
              value: 'Jazz',
            ),
          ],
        ),
      ],
      sortMode: CustomSmartPlaylistSortMode.title,
      limit: 25,
    );
    final gateway = _FakeSharedSmartPlaylistGateway();
    final store = SharedSmartPlaylistStore(gatewayFactory: () => gateway);
    await store.load();

    final binding = await store.host(library, local);

    expect(binding.role, SharedPlaylistAccessRole.owner);
    expect(gateway.createdRule?['artist'], 'Mira');
    expect(gateway.createdRule?['ruleGroups'], isNotEmpty);
    expect(gateway.createdRule, isNot(contains('id')));
    expect(gateway.createdRule, isNot(contains('artworkUri')));
    expect(
      store.bindingForLocalSmartPlaylist(local.id)?.remoteId,
      _FakeSharedSmartPlaylistGateway.id,
    );
  });

  test('normalizes device-specific source IDs in shared smart rules', () async {
    final library = LibraryStore();
    await library.load();
    final local = await library.createCustomSmartPlaylist(
      name: 'Portable sources',
      sourceId: 'self-hosted-jellyfin-device-a',
      ruleGroups: <CustomSmartPlaylistRuleGroup>[
        CustomSmartPlaylistRuleGroup(
          rules: const <CustomSmartPlaylistRule>[
            CustomSmartPlaylistRule(
              field: CustomSmartPlaylistRuleField.sourceId,
              value: 'custom-catalog-device-b',
            ),
          ],
        ),
      ],
    );
    final gateway = _FakeSharedSmartPlaylistGateway();
    final store = SharedSmartPlaylistStore(gatewayFactory: () => gateway);
    await store.load();

    await store.host(library, local);

    expect(
      gateway.createdRule?['sourceId'],
      'aethertune-source-kind:self-hosted-jellyfin',
    );
    final groups = gateway.createdRule?['ruleGroups'] as List<Object?>;
    final group = groups.single as Map<String, Object?>;
    final rules = group['rules'] as List<Object?>;
    final rule = rules.single as Map<String, Object?>;
    expect(rule['value'], 'aethertune-source-kind:custom-catalog');
  });

  test('joins a shared smart definition as a local dynamic playlist', () async {
    final library = LibraryStore();
    await library.load();
    final gateway = _FakeSharedSmartPlaylistGateway();
    final store = SharedSmartPlaylistStore(gatewayFactory: () => gateway);
    await store.load();

    final binding = await store.joinInvite('AAAAAAAAAAAAAAAAAAAAAAAA', library);
    final local = library.customSmartPlaylistById(binding.localSmartPlaylistId);

    expect(local?.name, 'Shared jazz');
    expect(local?.artist, 'Mira');
    expect(local?.sortMode, CustomSmartPlaylistSortMode.title);
    expect(local?.ruleGroups.single.rules.single.value, 'Jazz');
  });

  test('rotates a public link and retains the newer shared revision', () async {
    final library = LibraryStore();
    await library.load();
    final local = await library.createCustomSmartPlaylist(name: 'Public rules');
    final gateway = _FakeSharedSmartPlaylistGateway();
    final store = SharedSmartPlaylistStore(gatewayFactory: () => gateway);
    await store.load();
    final binding = await store.host(library, local);

    final link = await store.createPublicLink(binding, library);

    expect(
      link.uri.toString(),
      'https://sync.example.test/public/${_FakeSharedSmartPlaylistGateway.id}',
    );
    expect(
      store.bindingForLocalSmartPlaylist(local.id)?.revision,
      2,
    );
    await store.revokePublicLink(
      store.bindingForLocalSmartPlaylist(local.id)!,
      library,
    );
    expect(
      store.bindingForLocalSmartPlaylist(local.id)?.revision,
      3,
    );
  });

  test('imports a public smart playlist without creating a private binding',
      () async {
    final library = LibraryStore();
    await library.load();
    final store = SharedSmartPlaylistStore();
    await store.load();
    final document = <String, Object?>{
      'version': 2,
      'kind': 'smart',
      'name': 'Public jazz',
      'rule': _rule(),
    };
    final checksum = sha256.convert(utf8.encode(jsonEncode(document))).toString();

    final imported = await store.importPublicLink(
      'https://sync.example.test/api/v1/public-smart-playlists/AAAAAAAAAAAAAAAAAAAAAAAA/BBBBBBBBBBBBBBBBBBBBBBBB',
      library,
      httpExecutor: (method, uri, {required headers, body}) async {
        expect(method, 'GET');
        expect(headers, <String, String>{'accept': 'application/json'});
        expect(body, isNull);
        return LibrarySyncHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'revision': 4,
            'checksum': checksum,
            'playlist': document,
          }),
        );
      },
    );

    expect(imported.name, 'Public jazz');
    expect(imported.artist, 'Mira');
    expect(imported.sortMode, CustomSmartPlaylistSortMode.title);
    expect(imported.ruleGroups.single.rules.single.value, 'Jazz');
    expect(store.bindings, isEmpty);
  });

  test('securely subscribes, refreshes, and unsubscribes public smart rules',
      () async {
    final library = LibraryStore();
    await library.load();
    final vault = _MemoryCredentialVault();
    final store = SharedSmartPlaylistStore(publicLinkVault: vault);
    await store.load();
    var revision = 4;
    var artist = 'Mira';
    Future<LibrarySyncHttpResponse> executor(
      String method,
      Uri uri, {
      required Map<String, String> headers,
      String? body,
    }) async {
      final rule = Map<String, Object?>.from(_rule())..['artist'] = artist;
      final document = <String, Object?>{
        'version': 2,
        'kind': 'smart',
        'name': 'Subscribed jazz',
        'rule': rule,
      };
      final checksum = sha256
          .convert(utf8.encode(jsonEncode(document)))
          .toString();
      return LibrarySyncHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'revision': revision,
          'checksum': checksum,
          'playlist': document,
        }),
      );
    }

    final subscription = await store.subscribeToPublicLink(
      'https://sync.example.test/api/v1/public-smart-playlists/AAAAAAAAAAAAAAAAAAAAAAAA/BBBBBBBBBBBBBBBBBBBBBBBB',
      library,
      httpExecutor: executor,
    );

    expect(store.publicSubscriptions, <PublicSmartPlaylistSubscription>[subscription]);
    expect(vault.values.values.single, contains('BBBBBBBBBBBBBBBBBBBBBBBB'));
    final rawMetadata = (await SharedPreferences.getInstance()).getString(
      'aethertune.shared_smart_playlists.v1',
    );
    expect(rawMetadata, isNot(contains('BBBBBBBBBBBBBBBBBBBBBBBB')));

    final restoredStore = SharedSmartPlaylistStore(publicLinkVault: vault);
    await restoredStore.load();
    expect(restoredStore.publicSubscriptions, hasLength(1));
    expect(restoredStore.publicSubscriptions.single.id, subscription.id);
    expect(
      restoredStore.publicSubscriptions.single.localSmartPlaylistId,
      subscription.localSmartPlaylistId,
    );

    revision = 5;
    artist = 'Nia';
    final refreshed = await restoredStore.refreshPublicSubscription(
      subscription,
      library,
      httpExecutor: executor,
    );
    expect(refreshed.revision, 5);
    expect(
      library.customSmartPlaylistById(subscription.localSmartPlaylistId)?.artist,
      'Nia',
    );

    await restoredStore.unsubscribeFromPublicLink(refreshed);
    expect(restoredStore.publicSubscriptions, isEmpty);
    expect(vault.values, isEmpty);
    expect(
      library.customSmartPlaylistById(subscription.localSmartPlaylistId)?.name,
      'Subscribed jazz',
    );
  });
}

class _MemoryCredentialVault implements ProviderCredentialVault {
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

class _FakeSharedSmartPlaylistGateway implements SharedSmartPlaylistGateway {
  static const id = 'AAAAAAAAAAAAAAAAAAAAAAAA';
  Map<String, Object?>? createdRule;

  @override
  Future<SharedPlaylistRemote> createSharedSmartPlaylist({
    required String name,
    required Map<String, Object?> rule,
  }) async {
    createdRule = rule;
    return _remote(name: name, rule: rule, role: SharedPlaylistAccessRole.owner);
  }

  @override
  Future<SharedPlaylistRemote> joinSharedPlaylistInvite(String inviteCode) async =>
      _remote(
        name: 'Shared jazz',
        rule: _rule(),
        role: SharedPlaylistAccessRole.viewer,
      );

  @override
  Future<SharedPlaylistRemote> fetchSharedPlaylist(String playlistId) async =>
      _remote(
        name: 'Shared jazz',
        rule: _rule(),
        role: SharedPlaylistAccessRole.viewer,
      );

  @override
  Future<SharedPlaylistRemote> updateSharedSmartPlaylist({
    required String playlistId,
    required int baseRevision,
    required String name,
    required Map<String, Object?> rule,
  }) async =>
       _remote(name: name, rule: rule, role: SharedPlaylistAccessRole.editor);

  @override
  Future<SharedSmartPlaylistPublicLink> issueSharedSmartPlaylistPublicLink({
    required String playlistId,
    required int baseRevision,
  }) async =>
      SharedSmartPlaylistPublicLink(
        uri: Uri.parse('https://sync.example.test/public/$id'),
        revision: baseRevision + 1,
      );

  @override
  Future<int> revokeSharedSmartPlaylistPublicLink({
    required String playlistId,
    required int baseRevision,
  }) async => baseRevision + 1;

  @override
  Future<SharedPlaylistInvitation> issueSharedPlaylistInvite({
    required String playlistId,
    required SharedPlaylistAccessRole role,
  }) async =>
      SharedPlaylistInvitation(
        code: 'BBBBBBBBBBBBBBBBBBBBBBBB',
        role: role,
        expiresAt: DateTime.utc(2026, 7, 27),
      );

  @override
  Future<SharedPlaylistRemote> createSharedPlaylist({
    required String name,
    required List<String> trackIds,
  }) => throw UnimplementedError();

  @override
  Future<List<SharedPlaylistRevision>> fetchSharedPlaylistHistory(
    String playlistId,
  ) => throw UnimplementedError();

  @override
  Future<SharedPlaylistRemote> updateSharedPlaylist({
    required String playlistId,
    required int baseRevision,
    required String name,
    required List<String> trackIds,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteSharedPlaylist({
    required String playlistId,
    required int baseRevision,
  }) async {}

  @override
  Future<int> invalidateSharedPlaylistInvites({
    required String playlistId,
  }) async => 0;

  @override
  Future<SharedPlaylistRemote> revokeSharedPlaylistCollaborator({
    required String playlistId,
    required String collaboratorId,
    required int baseRevision,
  }) => throw UnimplementedError();

  SharedPlaylistRemote _remote({
    required String name,
    required Map<String, Object?> rule,
    required SharedPlaylistAccessRole role,
  }) =>
      SharedPlaylistRemote(
        id: id,
        revision: 1,
        role: role,
        name: name,
        trackIds: const <String>[],
        kind: SharedPlaylistKind.smart,
        smartPlaylist: SharedSmartPlaylistDocument(name: name, rule: rule),
      );
}

Map<String, Object?> _rule() => <String, Object?>{
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
      'matchMode': 'all',
      'rules': <Object?>[
        <String, Object?>{'field': 'genre', 'value': 'Jazz'},
      ],
      'groups': <Object?>[],
    },
  ],
  'sortMode': 'title',
  'limit': 25,
};
