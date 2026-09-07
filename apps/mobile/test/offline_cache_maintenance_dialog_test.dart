import 'package:aethertune/src/ui/offline_cache_maintenance_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('cleanup needs explicit confirmation at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    confirmed = await confirmOfflineCacheClear(context),
                child: const Text('Open cleanup'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open cleanup'));
      await tester.pumpAndSettle();
      expect(confirmed, isNull);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
      await tester.tap(find.text('Open cleanup'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Clear media'));
      await tester.tap(find.text('Clear media'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
