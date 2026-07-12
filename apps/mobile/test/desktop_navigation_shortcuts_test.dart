import 'package:aethertune/src/ui/desktop_navigation_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects desktop navigation destinations with Ctrl+digits',
      (tester) async {
    int? selectedDestination;

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopNavigationShortcutScope(
          enabled: true,
          onDestinationSelected: (index) => selectedDestination = index,
          onPreviousDestination: () {},
          onNextDestination: () {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(selectedDestination, 3);
  });

  testWidgets('cycles desktop navigation destinations with Alt+arrows',
      (tester) async {
    var previousCalls = 0;
    var nextCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopNavigationShortcutScope(
          enabled: true,
          onDestinationSelected: (_) {},
          onPreviousDestination: () => previousCalls += 1,
          onNextDestination: () => nextCalls += 1,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(previousCalls, 1);
    expect(nextCalls, 1);
  });

  testWidgets('does not install shortcuts outside desktop layout', (tester) async {
    var selected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: DesktopNavigationShortcutScope(
          enabled: false,
          onDestinationSelected: (_) => selected = true,
          onPreviousDestination: () {},
          onNextDestination: () {},
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(selected, isFalse);
  });
}
