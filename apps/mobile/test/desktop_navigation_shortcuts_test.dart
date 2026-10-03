import 'package:aethertune/src/ui/desktop_navigation_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation shortcuts work after retained app focus finishes setup', (
    tester,
  ) async {
    final appFocus = FocusNode(debugLabel: 'retained application focus');
    addTearDown(appFocus.dispose);
    var finishedSetup = false;
    int? selectedDestination;
    var mediaCalls = 0;
    late VoidCallback finishSetup;
    final outerKeyEvents = <LogicalKeyboardKey>[];

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            finishSetup = () => setState(() => finishedSetup = true);
            // Mirrors AetherTuneApp's retained media shortcuts + autofocus
            // around the ordinary setup-to-Home branch transition.
            return CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(
                  LogicalKeyboardKey.keyK,
                  control: true,
                ): () =>
                    mediaCalls += 1,
              },
              child: Focus(
                focusNode: appFocus,
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    outerKeyEvents.add(event.logicalKey);
                  }
                  return KeyEventResult.ignored;
                },
                child: finishedSetup
                    ? DesktopNavigationShortcutScope(
                        enabled: true,
                        onDestinationSelected: (index) =>
                            selectedDestination = index,
                        onPreviousDestination: () {},
                        onNextDestination: () {},
                        child: const SizedBox.expand(
                          key: Key('ordinary desktop content'),
                        ),
                      )
                    : const SizedBox.expand(key: Key('ordinary setup content')),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(appFocus));

    finishSetup();
    await tester.pump();
    await tester.pump();
    final navigationFocus = Focus.of(
      tester.element(find.byKey(const Key('ordinary desktop content'))),
    );
    final primary = FocusManager.instance.primaryFocus!;
    debugPrint(
      'Setup transition focus: retainedOuter=${identical(primary, appFocus)}, '
      'navigationDescendsFromOuter=${navigationFocus.ancestors.contains(appFocus)}, '
      'navigationInPrimaryChain=${identical(primary, navigationFocus) || primary.ancestors.contains(navigationFocus)}',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    debugPrint(
      'Outer focus received digit2=${outerKeyEvents.contains(LogicalKeyboardKey.digit2)}',
    );
    expect(selectedDestination, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(mediaCalls, 1);
  });

  testWidgets('desktop rebuild preserves text entry focus and content', (
    tester,
  ) async {
    final inputFocus = FocusNode();
    final text = TextEditingController();
    addTearDown(inputFocus.dispose);
    addTearDown(text.dispose);
    late StateSetter rebuild;
    var revision = 0;
    int? selectedDestination;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return DesktopNavigationShortcutScope(
              enabled: true,
              onDestinationSelected: (index) => selectedDestination = index,
              onPreviousDestination: () {},
              onNextDestination: () {},
              child: Scaffold(
                body: Column(
                  children: <Widget>[
                    Text('Revision $revision'),
                    TextField(
                      key: const Key('ordinary search field'),
                      focusNode: inputFocus,
                      controller: text,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('ordinary search field')));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(inputFocus));
    await tester.enterText(
      find.byKey(const Key('ordinary search field')),
      'ordinary search',
    );
    rebuild(() => revision += 1);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(inputFocus));
    expect(text.text, 'ordinary search');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selectedDestination, 1);
    expect(FocusManager.instance.primaryFocus, same(inputFocus));
    expect(text.text, 'ordinary search');
  });

  testWidgets('focused descendant handles keys before desktop shortcuts', (
    tester,
  ) async {
    final inputFocus = FocusNode();
    addTearDown(inputFocus.dispose);
    var handled = 0;
    int? selectedDestination;
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopNavigationShortcutScope(
          enabled: true,
          onDestinationSelected: (index) => selectedDestination = index,
          onPreviousDestination: () {},
          onNextDestination: () {},
          child: Scaffold(
            body: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.digit2 &&
                    HardwareKeyboard.instance.isControlPressed) {
                  handled += 1;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                key: const Key('focused editor'),
                focusNode: inputFocus,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('focused editor')));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(inputFocus));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(handled, 1);
    expect(selectedDestination, isNull);
    expect(FocusManager.instance.primaryFocus, same(inputFocus));
  });

  testWidgets(
    'dialog focus survives desktop rebuild and restores after close',
    (tester) async {
      final dialogFocus = FocusNode();
      final text = TextEditingController();
      addTearDown(dialogFocus.dispose);
      addTearDown(text.dispose);
      late StateSetter rebuild;
      late BuildContext dialogContext;
      var revision = 0;
      int? selectedDestination;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return DesktopNavigationShortcutScope(
                enabled: true,
                onDestinationSelected: (index) => selectedDestination = index,
                onPreviousDestination: () {},
                onNextDestination: () {},
                child: Scaffold(
                  body: Column(
                    children: <Widget>[
                      Text('Revision $revision'),
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) {
                            dialogContext = context;
                            return AlertDialog(
                              content: TextField(
                                key: const Key('ordinary dialog field'),
                                focusNode: dialogFocus,
                                controller: text,
                                autofocus: true,
                              ),
                            );
                          },
                        ),
                        child: const Text('Open ordinary dialog'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open ordinary dialog'));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(dialogFocus));
      await tester.enterText(
        find.byKey(const Key('ordinary dialog field')),
        'dialog entry',
      );
      rebuild(() => revision += 1);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, same(dialogFocus));
      expect(text.text, 'dialog entry');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(selectedDestination, isNull);
      expect(FocusManager.instance.primaryFocus, same(dialogFocus));

      Navigator.of(dialogContext).pop();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(selectedDestination, 1);
    },
  );

  testWidgets('selects desktop navigation destinations with Ctrl+digits', (
    tester,
  ) async {
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

  testWidgets('cycles desktop navigation destinations with Alt+arrows', (
    tester,
  ) async {
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

  testWidgets('does not install shortcuts outside desktop layout', (
    tester,
  ) async {
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
