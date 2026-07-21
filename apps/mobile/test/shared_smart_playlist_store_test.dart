import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/shared_smart_playlist_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

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
  });
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
