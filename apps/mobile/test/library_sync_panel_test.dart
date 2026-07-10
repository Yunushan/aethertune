import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/library_sync_credential_vault.dart';
import 'package:aethertune/src/data/library_sync_store.dart';
import 'package:aethertune/src/domain/library_sync_account.dart';
import 'package:aethertune/src/domain/track.dart';
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
    expect(find.byKey(const Key('library-sync-upload')), findsOneWidget);
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
      find.text(
        'Revision 4 was uploaded by Linux desktop. Choose which library to keep.',
      ),
      findsOneWidget,
    );
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

  testWidgets('offline mode disables every network sync control', (
    tester,
  ) async {
    _setPhoneSize(tester);
    final library = LibraryStore();
    final sync = LibrarySyncStore(
      credentialVault: _MemorySyncVault(),
      clientFactory: (account, token) => _FakeSyncGateway(
        remote: const LibrarySyncRemoteSnapshot(revision: 0),
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
    expect(configure.onPressed, isNull);
    expect(upload.onPressed, isNull);
    expect(download.onPressed, isNull);
    expect(find.text('Library sync paused by offline mode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _harness({
  required LibraryStore library,
  required LibrarySyncStore sync,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LibraryStore>.value(value: library),
      ChangeNotifierProvider<LibrarySyncStore>.value(value: sync),
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

class _FakeSyncGateway implements LibrarySyncGateway {
  _FakeSyncGateway({
    required this.remote,
    List<Object> pushResults = const <Object>[],
  }) : pushResults = List<Object>.from(pushResults);

  LibrarySyncRemoteSnapshot remote;
  final List<Object> pushResults;
  int fetchCalls = 0;
  final List<int> pushedBaseRevisions = <int>[];

  @override
  Future<LibrarySyncRemoteSnapshot> fetch() async {
    fetchCalls += 1;
    return remote;
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
}
