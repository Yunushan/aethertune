import 'dart:ui' show SemanticsAction, Tristate;

import 'package:aethertune/src/ui/widgets/accessible_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final variant in <String>['material2', 'standard', 'filled', 'tonal']) {
    testWidgets('$variant keeps one named action and a visual tooltip', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        var taps = 0;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        final button = _button(
          variant,
          label: 'Play',
          focus: focus,
          onPressed: () => taps += 1,
        );
        await tester.pumpWidget(
          _app(button, material2: variant == 'material2'),
        );
        await tester.pumpAndSettle();

        expect(tester.widget<IconButton>(find.byKey(_buttonKey)), same(button));
        final node = _namedButton(tester, 'Play');
        final data = node.getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.flagsCollection.isEnabled, Tristate.isTrue);
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.tooltip, isEmpty);
        expect(
          _nodes(
            tester,
          ).where((n) => n.getSemanticsData().hasAction(SemanticsAction.tap)),
          hasLength(1),
        );

        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(taps, 1);
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(
          _namedButton(
            tester,
            'Play',
          ).getSemanticsData().flagsCollection.isFocused,
          Tristate.isTrue,
        );

        expect(
          tester
              .state<TooltipState>(find.byType(Tooltip))
              .ensureTooltipVisible(),
          isTrue,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Play'), findsOneWidget);
        expect(
          _nodes(
            tester,
          ).where((n) => n.getSemanticsData().label.contains('Play')),
          hasLength(1),
        );
        expect(
          _namedButton(tester, 'Play').getSemanticsData().tooltip,
          isEmpty,
        );
        expect(taps, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('$variant keeps explicit disabled state without a tap action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _app(
            _button(variant, label: 'Previous', onPressed: null),
            material2: variant == 'material2',
          ),
        );
        await tester.pumpAndSettle();
        final data = _namedButton(tester, 'Previous').getSemanticsData();
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        expect(
          _nodes(
            tester,
          ).where((n) => n.getSemanticsData().hasAction(SemanticsAction.tap)),
          isEmpty,
        );
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
    'keeps selected state and updates Play to Pause on the real action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var playing = false;
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: StatefulBuilder(
                  builder: (context, setState) => AccessibleIconButton(
                    button: IconButton.filled(
                      key: _buttonKey,
                      tooltip: playing ? 'Pause' : 'Play',
                      isSelected: playing,
                      onPressed: () => setState(() {
                        playing = !playing;
                        taps += 1;
                      }),
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = _namedButton(tester, 'Play');
        expect(
          before.getSemanticsData().flagsCollection.isSelected,
          Tristate.isFalse,
        );
        before.owner!.performAction(before.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        final after = _namedButton(tester, 'Pause');
        expect(
          after.getSemanticsData().flagsCollection.isSelected,
          Tristate.isTrue,
        );
        expect(after.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(
          _nodes(tester).where((n) => n.getSemanticsData().label == 'Play'),
          isEmpty,
        );
        expect(taps, 1);
      } finally {
        semantics.dispose();
      }
    },
  );
}

const _buttonKey = Key('existing-icon-button');

IconButton _button(
  String variant, {
  required String label,
  required VoidCallback? onPressed,
  FocusNode? focus,
}) {
  switch (variant) {
    case 'filled':
      return IconButton.filled(
        key: _buttonKey,
        tooltip: label,
        onPressed: onPressed,
        focusNode: focus,
        icon: const Icon(Icons.play_arrow),
      );
    case 'tonal':
      return IconButton.filledTonal(
        key: _buttonKey,
        tooltip: label,
        onPressed: onPressed,
        focusNode: focus,
        icon: const Icon(Icons.play_arrow),
      );
    default:
      return IconButton(
        key: _buttonKey,
        tooltip: label,
        onPressed: onPressed,
        focusNode: focus,
        icon: const Icon(Icons.play_arrow),
      );
  }
}

Widget _app(IconButton button, {bool material2 = false}) => MaterialApp(
  theme: ThemeData(useMaterial3: !material2),
  home: Scaffold(
    body: Center(child: AccessibleIconButton(button: button)),
  ),
);

List<SemanticsNode> _nodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.isMergedIntoParent) {
      return;
    }
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return nodes;
}

SemanticsNode _namedButton(WidgetTester tester, String label) {
  final matches = _nodes(tester)
      .where(
        (node) =>
            node.getSemanticsData().label == label &&
            node.getSemanticsData().flagsCollection.isButton,
      )
      .toList();
  expect(matches, hasLength(1));
  return matches.single;
}
