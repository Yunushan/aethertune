import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/l10n/app_localizations.dart';
import 'package:aethertune/src/ui/onboarding_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("onboarding 'Open Library' triggers the Library-tab handoff", (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    int? destination;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OnboardingScreen(onFinished: (tab) async => destination = tab),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to AetherTune'), findsOneWidget);
    expect(find.text('Set up a local library'), findsOneWidget);

    await tester.tap(find.text('Open Library'));
    await tester.pumpAndSettle();

    expect(destination, 1);
  });
}
