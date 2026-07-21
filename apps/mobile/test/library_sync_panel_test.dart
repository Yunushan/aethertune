import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/library_sync_credential_vault.dart';
import 'package:aethertune/src/data/library_sync_store.dart';
import 'package:aethertune/src/data/listen_together_store.dart';
import 'package:aethertune/src/domain/listen_together_session.dart';
import 'package:aethertune/src/domain/library_sync_account.dart';
import 'package:aethertune/src/domain/library_sync_profile.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/widgets/library_sync_panel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('configures sync with an obscured token at phone width', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final library = LibraryStore();
    final vault = _MemorySyncVault();
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
      profile: _managedProfile(),
    );
    final sync = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
    );
    await library.load();
    await sync.load();
    await tester.pumpWidget(_harness(library: library, sync: sync));

    await tester.tap(find.byKey(const Key('library-sync-configure')));
    await tester.pumpAndSettle();

    final tokenField = tester.widget<TextField>(
      find.byKey(const Key('library-sync-token')),
    );
    expect(tokenField.obscureText, isTrue);
    await tester.enterText(
      find.byKey(const Key('library-sync-url')),
      'https://sync.example.test',
    );
    await tester.enterText(
      find.byKey(const Key('library-sync-device')),
      'Android phone',
    );
    await tester.enterText(
      find.byKey(const Key('library-sync-token')),
      'private-token',
    );
    await tester.tap(find.byKey(const Key('library-sync-test-save')));
    await tester.pumpAndSettle();

    expect(vault.token, 'private-token');
    expect(gateway.fetchCalls, 1);
    expect(find.textContaining('sync.example.test'), findsOneWidget);
    expect(find.text('Primary listener'), findsOneWidget);
    expect(
      find.text('Account primary · Device Windows desktop'),
      findsOneWidget,
    );
    expect(find.text('0123456789abcdef01234567'), findsNothing);
    expect(find.byKey(const Key('library-sync-upload')), findsOneWidget);
    expect(find.byKey(const Key('library-sync-queue')), findsOneWidget);
    expect(
      find.byKey(const Key('library-sync-copy-public-profile-link')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('library-sync-discover-profiles')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('library-sync-profile-search-query')),
      'Mira',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Mira listener'), findsOneWidget);
    expect(find.text('public-mira'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    final queueSync = tester.widget<SwitchListTile>(
      find.byKey(const Key('library-sync-queue')),
    );
    expect(queueSync.onChanged, isNull);
    await tester.tap(find.byKey(const Key('library-sync-automatic-upload')));
    await tester.pumpAndSettle();
    expect(sync.automaticUploadEnabled, isTrue);
    gateway.profile = LibrarySyncProfile(
      id: 'primary',
      displayName: 'Updated listener',
      managed: true,
      device: _managedProfile().device,
      editable: true,
      avatarToneSupported: true,
      publicProfileSupported: true,
      publicProfileFieldAudienceSupported: true,
    );
    await tester.tap(find.byKey(const Key('library-sync-refresh-profile')));
    await tester.pumpAndSettle();
    expect(gateway.profileFetchCalls, 2);
    expect(find.text('Updated listener'), findsOneWidget);
    await tester.tap(find.byKey(const Key('library-sync-edit-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Edit account identity'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('library-sync-profile-display-name')),
      'Shared listeners',
    );
    await tester.enterText(
      find.byKey(const Key('library-sync-profile-device-name')),
      'Pocket player',
    );
    await tester.tap(
      find.byKey(const Key('library-sync-profile-avatar-tone')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Emerald').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('library-sync-profile-public-display-name')),
    );
    await tester.tap(
      find.byKey(const Key('library-sync-profile-public-avatar')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-sync-save-profile')));
    await tester.pumpAndSettle();
    expect(gateway.profileUpdateCalls, 1);
    expect(find.text('Shared listeners'), findsOneWidget);
    expect(find.text('Account primary · Device Pocket player'), findsOneWidget);
    expect(sync.profile?.avatarTone, LibrarySyncProfileAvatarTone.emerald);
    expect(sync.profile?.avatarToneSupported, isTrue);
    expect(sync.profile?.publicDisplayNameEnabled, isTrue);
    expect(sync.profile?.publicAvatarToneEnabled, isTrue);
    expect(sync.account?.deviceId, 'Pocket player');
    expect(
      find.byKey(const Key('library-sync-copy-public-profile-link')),
      findsOneWidget,
    );
    expect(find.text('private-token'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('requires explicit HTTP consent without exposing the token', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final library = LibraryStore();
    final vault = _MemorySyncVault();
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
    );
    final sync = LibrarySyncStore(
      credentialVault: vault,
      clientFactory: (account, token) => gateway,
    );
    await library.load();
    await sync.load();
    await tester.pumpWidget(_harness(library: library, sync: sync));
    await tester.tap(find.byKey(const Key('library-sync-configure')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('library-sync-url')),
      'http://192.168.1.10:8080',
    );
    await tester.enterText(
      find.byKey(const Key('library-sync-device')),
      'LAN phone',
    );
    await tester.enterText(
      find.byKey(const Key('library-sync-token')),
      'lan-private-token',
    );
    await tester.tap(find.byKey(const Key('library-sync-test-save')));
    await tester.pump();

    expect(gateway.fetchCalls, 0);
    expect(find.textContaining('Confirm insecure HTTP'), findsOneWidget);
    final errorText = tester.widget<Text>(
      find.byKey(const Key('library-sync-config-error')),
    );
    expect(errorText.data, isNot(contains('lan-private-token')));

    await tester.tap(find.byKey(const Key('library-sync-insecure-http')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('library-sync-test-save')));
    await tester.pumpAndSettle();

    expect(gateway.fetchCalls, 1);
    expect(vault.token, 'lan-private-token');
    expect(tester.takeException(), isNull);
  });

  testWidgets('never overwrites a newer server revision without a choice', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[
      Track(id: 'local', title: 'Local choice', localPath: '/music/local.mp3'),
    ]);
    final gateway = _FakeSyncGateway(
      remote: const LibrarySyncRemoteSnapshot(revision: 0),
      pushResults: <Object>[
        const LibrarySyncConflictException(
          currentRevision: 4,
          updatedByDevice: 'Linux desktop',
        ),
        LibrarySyncRemoteSnapshot(
          revision: 5,
          updatedAt: DateTime.utc(2026, 7, 10),
          updatedByDevice: 'Phone',
          checksum: 'checksum',
        ),
      ],
    );
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    await tester.pumpWidget(_harness(library: library, sync: sync));

    await tester.tap(find.byKey(const Key('library-sync-upload')));
    await tester.pumpAndSettle();

    expect(find.text('Library changed on server'), findsOneWidget);
    expect(
      find.textContaining('Revision 4 was uploaded by Linux desktop.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('library-sync-merge')), findsOneWidget);
    expect(gateway.pushedBaseRevisions, <int>[0]);

    await tester.tap(find.byKey(const Key('library-sync-use-local')));
    await tester.pumpAndSettle();

    expect(gateway.pushedBaseRevisions, <int>[0, 4]);
    expect(sync.lastKnownRevision, 5);
    expect(find.textContaining('Replaced server with revision 5'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('downloads only after confirmation and applies server state', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final remoteLibrary = LibraryStore();
    await remoteLibrary.load();
    await remoteLibrary.addTracks(<Track>[
      Track(id: 'remote', title: 'Remote track', streamUrl: 'https://example.test/audio.mp3'),
    ]);
    final remoteSnapshot = jsonDecode(remoteLibrary.exportSyncSnapshotJson())
        as Map<String, dynamic>;

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final localLibrary = LibraryStore();
    await localLibrary.load();
    await localLibrary.addTracks(<Track>[
      Track(id: 'local', title: 'Local track', localPath: '/music/local.mp3'),
    ]);
    final gateway = _FakeSyncGateway(
      remote: LibrarySyncRemoteSnapshot(
        revision: 2,
        updatedAt: DateTime.utc(2026, 7, 10),
        updatedByDevice: 'Desktop',
        checksum: 'checksum',
        snapshot: Map<String, Object?>.from(remoteSnapshot),
      ),
    );
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await sync.load();
    await sync.testAndSave(localLibrary, _account(), 'token');
    await tester.pumpWidget(_harness(library: localLibrary, sync: sync));

    await tester.tap(find.byKey(const Key('library-sync-download')));
    await tester.pumpAndSettle();
    expect(localLibrary.tracks.single.id, 'local');
    expect(find.text('Use server library?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('library-sync-confirm-download')));
    await tester.pumpAndSettle();

    expect(localLibrary.tracks.single.id, 'remote');
    expect(sync.lastKnownRevision, 2);
    expect(find.textContaining('Downloaded server revision 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides profile editing for a legacy managed server', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final library = LibraryStore();
    final legacyProfile = LibrarySyncProfile(
      id: 'primary',
      displayName: 'Legacy listener',
      managed: true,
      device: _managedProfile().device,
    );
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => _FakeSyncGateway(
        remote: const LibrarySyncRemoteSnapshot(revision: 0),
        profile: legacyProfile,
      ),
    );
    await library.load();
    await sync.load();
    await sync.testAndSave(library, _account(), 'private-token');
    await tester.pumpWidget(_harness(library: library, sync: sync));

    expect(find.text('Legacy listener'), findsOneWidget);
    expect(find.byKey(const Key('library-sync-edit-profile')), findsNothing);
    expect(
      find.byKey(const Key('library-sync-refresh-profile')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletes the remote snapshot only after confirmation', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[Track(id: 'local', title: 'Local track')]);
    final gateway = _FakeSyncGateway(
      remote: LibrarySyncRemoteSnapshot(
        revision: 2,
        updatedAt: DateTime.utc(2026, 7, 10),
        updatedByDevice: 'Desktop',
        checksum: 'checksum',
        snapshot: <String, Object?>{
          'syncVersion': 1,
          'version': 1,
          'tracks': <Object?>[],
          'offlineCacheQueue': <Object?>[],
        },
      ),
      deleteResults: <Object>[
        LibrarySyncRemoteSnapshot(
          revision: 3,
          updatedAt: DateTime.utc(2026, 7, 11),
          updatedByDevice: 'Phone',
        ),
      ],
    );
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    await sync.setAutomaticUploadEnabled(true);
    await tester.pumpWidget(_harness(library: library, sync: sync));

    await tester.tap(find.byKey(const Key('library-sync-delete-remote')));
    await tester.pumpAndSettle();
    expect(find.text('Delete server snapshot?'), findsOneWidget);
    expect(library.tracks.single.id, 'local');

    await tester.tap(
      find.byKey(const Key('library-sync-confirm-delete-remote')),
    );
    await tester.pumpAndSettle();

    expect(gateway.deletedBaseRevisions, <int>[2]);
    expect(library.tracks.single.id, 'local');
    expect(sync.automaticUploadEnabled, isFalse);
    expect(find.textContaining('Deleted server snapshot at revision 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline mode disables every network sync control', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final library = LibraryStore();
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => _FakeSyncGateway(
        remote: const LibrarySyncRemoteSnapshot(revision: 0),
        profile: _managedProfile(),
      ),
    );
    await library.load();
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    await library.setOfflineModeEnabled(true);
    await tester.pumpWidget(_harness(library: library, sync: sync));

    final configure = tester.widget<IconButton>(
      find.byKey(const Key('library-sync-configure')),
    );
    final upload = tester.widget<IconButton>(
      find.byKey(const Key('library-sync-upload')),
    );
    final download = tester.widget<IconButton>(
      find.byKey(const Key('library-sync-download')),
    );
    final refreshProfile = tester.widget<IconButton>(
      find.byKey(const Key('library-sync-refresh-profile')),
    );
    final editProfile = tester.widget<IconButton>(
      find.byKey(const Key('library-sync-edit-profile')),
    );
    expect(configure.onPressed, isNull);
    expect(upload.onPressed, isNull);
    expect(download.onPressed, isNull);
    expect(refreshProfile.onPressed, isNull);
    expect(editProfile.onPressed, isNull);
    expect(find.text('Library sync paused by offline mode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows and manually refreshes a joined listen-together session',
      (tester) async {
    _setPhoneSize(tester);
    final library = LibraryStore();
    await library.load();
    final track = Track(
      id: 'shared',
      title: 'Shared track',
      localPath: '/music/shared.mp3',
    );
    await library.addTracks(<Track>[track]);
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => _FakeSyncGateway(
        remote: const LibrarySyncRemoteSnapshot(revision: 0),
      ),
    );
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    final gateway = _ListenTogetherTestGateway()
      ..session = const ListenTogetherSession(
        trackIds: <String>['shared'],
        currentTrackId: 'shared',
        position: Duration.zero,
        playing: true,
      );
    final player = PlayerController(audioEngine: _ListenTogetherTestEngine());
    addTearDown(player.dispose);
    final listenTogether = ListenTogetherStore(
      gatewayFactory: () => gateway,
      clock: () => DateTime.utc(2026, 7, 18, 12),
    );
    await listenTogether.join(library, player);
    await tester.pumpWidget(
      _harness(
        library: library,
        sync: sync,
        listenTogether: listenTogether,
        player: player,
      ),
    );

    expect(find.byKey(const Key('listen-together-refresh')), findsOneWidget);
    expect(find.textContaining('updated by Test device'), findsOneWidget);

    await tester.tap(find.byKey(const Key('listen-together-refresh')));
    await tester.pumpAndSettle();

    expect(gateway.fetchCalls, 2);
    expect(listenTogether.joined, isTrue);
    expect(find.text('Shared playback is up to date.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _harness({
  required LibraryStore library,
  required LibrarySyncStore sync,
  ListenTogetherStore? listenTogether,
  PlayerController? player,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LibraryStore>.value(value: library),
      ChangeNotifierProvider<LibrarySyncStore>.value(value: sync),
      if (listenTogether != null)
        ChangeNotifierProvider<ListenTogetherStore>.value(value: listenTogether),
      if (player != null) ChangeNotifierProvider<PlayerController>.value(value: player),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: LibrarySyncPanel()),
      ),
    ),
  );
}

void _setPhoneSize(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

LibrarySyncAccount _account() {
  return createLibrarySyncAccount(
    baseUrl: 'https://sync.example.test',
    deviceId: 'Phone',
    allowInsecureHttp: false,
  );
}

LibrarySyncProfile _managedProfile() {
  return LibrarySyncProfile(
    id: 'primary',
    displayName: 'Primary listener',
    managed: true,
    device: LibrarySyncProfileDevice(
      id: '0123456789abcdef01234567',
      name: 'Windows desktop',
      createdAt: DateTime.utc(2026, 7, 15, 12),
    ),
    editable: true,
    avatarToneSupported: true,
  );
}

class _MemorySyncVault implements LibrarySyncCredentialVault {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async {
    this.token = token;
  }

  @override
  Future<void> delete() async {
    token = null;
  }
}

class _FakeSyncGateway
    implements
        LibrarySyncGateway,
        LibrarySyncProfileGateway,
        LibrarySyncPublicProfileGateway,
        LibrarySyncProfileEditorGateway {
  _FakeSyncGateway({
    required this.remote,
    this.profile,
    List<Object> pushResults = const <Object>[],
    List<Object> deleteResults = const <Object>[],
  })  : pushResults = List<Object>.from(pushResults),
        deleteResults = List<Object>.from(deleteResults);

  LibrarySyncRemoteSnapshot remote;
  LibrarySyncProfile? profile;
  final List<Object> pushResults;
  final List<Object> deleteResults;
  int fetchCalls = 0;
  int profileFetchCalls = 0;
  int profileUpdateCalls = 0;
  int publicProfileSearchCalls = 0;
  final List<int> pushedBaseRevisions = <int>[];
  final List<int> deletedBaseRevisions = <int>[];

  @override
  Future<LibrarySyncRemoteSnapshot> fetch() async {
    fetchCalls += 1;
    return remote;
  }

  @override
  Future<LibrarySyncProfile?> fetchProfile() async {
    profileFetchCalls += 1;
    return profile;
  }

  @override
  Future<List<LibrarySyncPublicProfile>> findPublicProfiles(
    String query,
  ) async {
    publicProfileSearchCalls += 1;
    if (query.trim().toLowerCase() != 'mira') {
      return const <LibrarySyncPublicProfile>[];
    }
    return const <LibrarySyncPublicProfile>[
      LibrarySyncPublicProfile(
        id: 'public-mira',
        displayName: 'Mira listener',
        avatarTone: 'violet',
      ),
    ];
  }

  @override
  Future<LibrarySyncProfile> updateProfile({
    required String displayName,
    required String deviceName,
    LibrarySyncProfileAvatarTone? avatarTone,
    bool includeAvatarTone = false,
    bool publicProfileEnabled = false,
    bool includePublicProfileEnabled = false,
    bool publicDisplayNameEnabled = false,
    bool includePublicDisplayNameEnabled = false,
    bool publicAvatarToneEnabled = false,
    bool includePublicAvatarToneEnabled = false,
  }) async {
    profileUpdateCalls += 1;
    final current = profile;
    if (current == null || current.device == null) {
      throw StateError('No managed profile.');
    }
    profile = LibrarySyncProfile(
      id: current.id,
      displayName: displayName,
      avatarTone: avatarTone,
      avatarToneSupported: current.avatarToneSupported,
      publicProfileEnabled: current.publicProfileFieldAudienceSupported
          ? publicDisplayNameEnabled || publicAvatarToneEnabled
          : publicProfileEnabled,
      publicProfileSupported: current.publicProfileSupported,
      publicProfileFieldAudienceSupported:
          current.publicProfileFieldAudienceSupported,
      publicDisplayNameEnabled: publicDisplayNameEnabled,
      publicAvatarToneEnabled: publicAvatarToneEnabled,
      managed: true,
      device: LibrarySyncProfileDevice(
        id: current.device!.id,
        name: deviceName,
        createdAt: current.device!.createdAt,
      ),
      editable: current.editable,
    );
    return profile!;
  }

  @override
  Future<LibrarySyncRemoteSnapshot> push({
    required int baseRevision,
    required Map<String, Object?> snapshot,
  }) async {
    pushedBaseRevisions.add(baseRevision);
    if (pushResults.isNotEmpty) {
      final result = pushResults.removeAt(0);
      if (result is Exception) {
        throw result;
      }
      return result as LibrarySyncRemoteSnapshot;
    }
    return LibrarySyncRemoteSnapshot(
      revision: baseRevision + 1,
      updatedAt: DateTime.utc(2026, 7, 10),
      updatedByDevice: 'Phone',
      checksum: 'checksum',
    );
  }

  @override
  Future<LibrarySyncRemoteSnapshot> delete({
    required int baseRevision,
  }) async {
    deletedBaseRevisions.add(baseRevision);
    if (deleteResults.isNotEmpty) {
      final result = deleteResults.removeAt(0);
      if (result is Exception) {
        throw result;
      }
      return result as LibrarySyncRemoteSnapshot;
    }
    return LibrarySyncRemoteSnapshot(
      revision: baseRevision + 1,
      updatedAt: DateTime.utc(2026, 7, 10),
      updatedByDevice: 'Phone',
    );
  }
}

class _ListenTogetherTestGateway implements ListenTogetherGateway {
  int revision = 1;
  int fetchCalls = 0;
  ListenTogetherSession? session;

  @override
  Future<ListenTogetherRemoteSession> fetchListenTogetherSession() async {
    fetchCalls += 1;
    return _remote();
  }

  @override
  Future<ListenTogetherRemoteSession> publishListenTogetherSession({
    required int baseRevision,
    required ListenTogetherSession session,
  }) async {
    this.session = session;
    revision += 1;
    return _remote();
  }

  @override
  Future<ListenTogetherRemoteSession> leaveListenTogetherSession({
    required int baseRevision,
  }) async {
    session = null;
    revision += 1;
    return _remote();
  }

  @override
  Future<String> issueListenTogetherInvite() async =>
      'AAAAAAAAAAAAAAAAAAAAAAAA';

  @override
  Future<ListenTogetherRemoteSession> fetchListenTogetherInvite(
    String inviteCode,
  ) => fetchListenTogetherSession();

  ListenTogetherRemoteSession _remote() => ListenTogetherRemoteSession(
    revision: revision,
    updatedAt: DateTime.utc(2026, 7, 18, 12),
    updatedByDevice: 'Test device',
    session: session,
  );
}

class _ListenTogetherTestEngine implements PlaybackAudioEngine {
  Duration positionValue = Duration.zero;
  bool playingValue = false;

  @override
  Stream<Object?> get stateChanges => const Stream<Object?>.empty();
  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();
  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();
  @override
  Stream<ProcessingState> get processingStateStream =>
      const Stream<ProcessingState>.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream<int?>.empty();
  @override
  bool get playing => playingValue;
  @override
  bool get shuffleModeEnabled => false;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  Duration get position => positionValue;
  @override
  Duration get bufferedPosition => positionValue;
  @override
  double get speed => 1;
  @override
  double get volume => 1;
  @override
  bool get hasNext => false;
  @override
  bool get hasPrevious => false;
  @override
  Future<void> setQueue(List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    positionValue = initialPosition;
  }
  @override
  Future<void> play() async => playingValue = true;
  @override
  Future<void> pause() async => playingValue = false;
  @override
  Future<void> stop() async => playingValue = false;
  @override
  Future<void> seek(Duration position, {int? index}) async =>
      positionValue = position;
  @override
  Future<void> seekToNext() async {}
  @override
  Future<void> seekToPrevious() async {}
  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {}
}
