import 'dart:convert';

import 'package:aethertune/src/data/library_storage.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/library_recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/library_storage_fixture.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'aethertune.tracks.v1': '{damaged',
    }),
  );

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('recovery actions fit ${size.width} without resetting data', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final library = LibraryStore();
      addTearDown(library.dispose);
      await library.load();
      String? exported;
      await tester.pumpWidget(
        _recoveryApp(library, saveRecovery: (data) async => exported = data),
      );
      await tester.pumpAndSettle();
      expect(find.text('Library recovery'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Export recovery data'));
      await tester.tap(find.text('Export recovery data'));
      await tester.pumpAndSettle();
      expect(
        (jsonDecode(exported!) as Map)['legacy'],
        containsPair('aethertune.tracks.v1', '{damaged'),
      );
      await tester.ensureVisible(find.text('Start empty library'));
      await tester.tap(find.text('Start empty library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(library.loaded, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'aethertune.tracks.v1',
        ),
        '{damaged',
      );
      await tester.tap(find.text('Start empty library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start empty'));
      await tester.pumpAndSettle();
      expect(find.text('Library restored'), findsOneWidget);
      expect(library.loaded, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 480), const Size(480, 320)]) {
    for (final direction in TextDirection.values) {
      testWidgets('recovery remains usable at 3x text in $size $direction', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final library = LibraryStore();
        addTearDown(library.dispose);
        await library.load();
        await tester.pumpWidget(
          _recoveryApp(library, textScale: 3, direction: direction),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in [
          'Retry',
          'Export recovery data',
          'Restore previous snapshot',
          'Import backup',
          'Start empty library',
        ]) {
          final button = find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          );
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          final bounds = tester.getRect(button);
          final text = tester.getRect(find.text(label));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(size.width));
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.bottom, lessThanOrEqualTo(size.height));
          expect(text.left, greaterThanOrEqualTo(bounds.left));
          expect(text.right, lessThanOrEqualTo(bounds.right));
          expect(text.top, greaterThanOrEqualTo(bounds.top));
          expect(text.bottom, lessThanOrEqualTo(bounds.bottom));
        }
        await tester.tap(find.text('Start empty library'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(library.loaded, isFalse);
      });
    }
  }

  testWidgets('save failure preserves a usable page with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 320);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final storage = _RejectingStorage();
    final library = LibraryStore(storage: storage);
    addTearDown(library.dispose);
    await library.load();
    storage.reject = true;
    await expectLater(
      library.addTracks([Track(id: 'unsaved', title: 'Unsaved')]),
      throwsA(isA<LibraryStorageException>()),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3)),
          child: child!,
        ),
        home: LibrarySaveFailureNotice(
          library: library,
          child: const Scaffold(body: Text('Current library')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSemantics(find.text(library.saveError!)),
      isSemantics(label: library.saveError, isLiveRegion: true),
    );
    expect(tester.getSize(find.byType(Scaffold)).height, greaterThan(80));
    await tester.ensureVisible(find.text('Reload saved library'));
    await tester.pumpAndSettle();
    expect(find.text('Reload saved library').hitTestable(), findsOneWidget);
    storage.reject = false;
    await tester.tap(find.text('Reload saved library'));
    await tester.pumpAndSettle();
    expect(library.saveError, isNull);
    expect(library.tracks, isEmpty);
  });

  testWidgets('invalid backup stays recoverable and a valid backup restores', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final source = LibraryStore();
    await source.load();
    await source.addTracks([Track(id: 'saved', title: 'Saved')]);
    final backup = source.exportBackupJson();
    source.dispose();
    SharedPreferences.setMockInitialValues({
      'aethertune.tracks.v1': '{damaged',
    });
    final library = LibraryStore();
    addTearDown(library.dispose);
    await library.load();
    var valid = false;
    await tester.pumpWidget(
      _recoveryApp(
        library,
        chooseBackup: () async => valid ? backup : '{invalid',
      ),
    );
    await tester.tap(find.text('Import backup'));
    await tester.pumpAndSettle();
    expect(library.loaded, isFalse);
    expect(find.textContaining('FormatException'), findsOneWidget);
    valid = true;
    await tester.tap(find.text('Import backup'));
    await tester.pumpAndSettle();
    expect(library.tracks.single.id, 'saved');
    expect(find.text('Library restored'), findsOneWidget);
  });

  testWidgets(
    'save failures remain visible until the saved state is reloaded',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = _RejectingStorage();
      final library = LibraryStore(storage: storage);
      addTearDown(library.dispose);
      await library.load();
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: library,
          builder: (_, _) => MaterialApp(
            home: LibrarySaveFailureNotice(
              library: library,
              child: const Scaffold(body: Text('Current library')),
            ),
          ),
        ),
      );
      storage.reject = true;
      await expectLater(
        library.addTracks([Track(id: 'unsaved', title: 'Unsaved')]),
        throwsA(isA<LibraryStorageException>()),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(library.tracks, isEmpty);
      storage.reject = false;
      await tester.tap(find.text('Reload saved library'));
      await tester.pumpAndSettle();
      expect(library.saveError, isNull);
      expect(find.textContaining('could not be saved'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _recoveryApp(
  LibraryStore library, {
  Future<void> Function(String)? saveRecovery,
  Future<String?> Function()? chooseBackup,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
}) => ListenableBuilder(
  listenable: library,
  builder: (_, _) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: library.loaded
        ? const Scaffold(body: Text('Library restored'))
        : LibraryRecoveryScreen(
            library: library,
            saveRecovery: saveRecovery,
            chooseBackup: chooseBackup,
          ),
  ),
);

final class _RejectingStorage implements LibraryStorage {
  final LibraryStorage delegate = PreferencesLibraryStorageFixture();
  bool reject = false;
  @override
  Future<LibraryStoredSnapshot?> read() => delegate.read();
  @override
  Future<LibraryStoredSnapshot> write(
    Map<String, Object?> values, {
    required String? expectedRevision,
  }) {
    if (reject) throw const LibraryStorageException('Rejected write');
    return delegate.write(values, expectedRevision: expectedRevision);
  }

  @override
  Future<void> recoverPrevious() => delegate.recoverPrevious();
  @override
  Future<Map<String, Object?>> recoveryData() => delegate.recoveryData();
  @override
  Future<LibraryStoredSnapshot> replaceForRecovery(
    Map<String, Object?> values,
  ) => delegate.replaceForRecovery(values);
}
