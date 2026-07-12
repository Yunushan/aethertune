import 'package:aethertune/src/ui/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('routes local-library setup to the Library tab', (tester) async {
    int? destination;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onFinished: (tab) async {
            destination = tab;
          },
        ),
      ),
    );

    expect(find.text('Welcome to AetherTune'), findsOneWidget);
    expect(find.text('Set up a local library'), findsOneWidget);

    await tester.tap(find.text('Open Library'));
    await tester.pumpAndSettle();

    expect(destination, 1);
  });

  testWidgets('routes source setup to the Sources tab', (tester) async {
    int? destination;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onFinished: (tab) async {
            destination = tab;
          },
        ),
      ),
    );

    await tester.tap(find.text('Open Sources'));
    await tester.pumpAndSettle();

    expect(destination, 4);
  });
}
