import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/library_sync_credential_vault.dart';
import 'package:aethertune/src/data/library_sync_store.dart';
import 'package:aethertune/src/domain/library_sync_account.dart';
import 'package:aethertune/src/ui/widgets/library_sync_automatic_upload.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('uploads a configured library when the app enters foreground', (
    tester,
  ) async {
    final library = LibraryStore();
    final gateway = _SyncGateway();
    final sync = LibrarySyncStore(
      credentialVault: _SyncVault(),
      clientFactory: (account, token) => gateway,
    );
    await library.load();
    await sync.load();
    await sync.testAndSave(library, _account(), 'token');
    await sync.setAutomaticUploadEnabled(true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: library),
          ChangeNotifierProvider<LibrarySyncStore>.value(value: sync),
        ],
        child: const MaterialApp(
          home: LibrarySyncAutomaticUpload(child: SizedBox()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(gateway.pushCalls, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

LibrarySyncAccount _account() {
  return createLibrarySyncAccount(
    baseUrl: 'https://sync.example.test',
    deviceId: 'Phone',
    allowInsecureHttp: false,
  );
}

class _SyncVault implements LibrarySyncCredentialVault {
  String? token;

  @override
  Future<void> delete() async {
    token = null;
  }

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async {
    this.token = token;
  }
}

class _SyncGateway implements LibrarySyncGateway {
  int pushCalls = 0;

  @override
  Future<LibrarySyncRemoteSnapshot> fetch() async {
    return const LibrarySyncRemoteSnapshot(revision: 0);
  }

  @override
  Future<LibrarySyncRemoteSnapshot> push({
    required int baseRevision,
    required Map<String, Object?> snapshot,
  }) async {
    pushCalls += 1;
    return LibrarySyncRemoteSnapshot(revision: baseRevision + 1);
  }
}
