import 'package:aethertune/src/ui/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethertune/l10n/app_localizations.dart';

Widget _localizedOnboarding({
  required Future<void> Function(int destination) onFinished,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: OnboardingScreen(onFinished: onFinished),
  );
}

void main() {
  testWidgets('routes local-library setup to the Library tab', (tester) async {
    int? destination;

    await tester.pumpWidget(
      _localizedOnboarding(
        onFinished: (tab) async {
          destination = tab;
        },
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
      _localizedOnboarding(
        onFinished: (tab) async {
          destination = tab;
        },
      ),
    );

    await tester.tap(find.text('Open Sources'));
    await tester.pumpAndSettle();

    expect(destination, 4);
  });

  testWidgets('uses Turkish onboarding translations', (tester) async {
    await tester.pumpWidget(
      _localizedOnboarding(
        locale: const Locale('tr'),
        onFinished: (_) async {},
      ),
    );

    expect(find.text("AetherTune'a hoş geldiniz"), findsOneWidget);
    expect(find.text('Kitaplığı aç'), findsOneWidget);
    expect(find.text('Kurulumu atla'), findsOneWidget);
  });

  testWidgets('uses Arabic onboarding translations with RTL directionality',
      (tester) async {
    await tester.pumpWidget(
      _localizedOnboarding(
        locale: const Locale('ar'),
        onFinished: (_) async {},
      ),
    );

    expect(find.text('مرحبًا بك في AetherTune'), findsOneWidget);
    expect(find.text('فتح المكتبة'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(OnboardingScreen))),
      TextDirection.rtl,
    );
  });
}
