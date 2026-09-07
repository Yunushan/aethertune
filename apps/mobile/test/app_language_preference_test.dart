import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/ui/aethertune_app.dart';
import 'package:aethertune/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in <List<Locale>?, Locale>{
    null: const Locale('en'),
    const []: const Locale('en'),
    const [Locale('de', 'DE')]: const Locale('en'),
    const [Locale('C')]: const Locale('en'),
    const [Locale('ar', 'SA')]: const Locale('ar'),
    const [Locale('tr', 'TR')]: const Locale('tr'),
    const [Locale('de'), Locale('tr')]: const Locale('tr'),
  }.entries) {
    test('resolves system locales ${entry.key} to ${entry.value}', () {
      expect(
        resolveAppLocale(entry.key, AppLocalizations.supportedLocales),
        entry.value,
      );
    });
  }

  test('maps language preferences to supported locale overrides', () {
    expect(localeForLanguagePreference(AppLanguagePreference.system), isNull);
    expect(
      localeForLanguagePreference(AppLanguagePreference.english)?.languageCode,
      'en',
    );
    expect(
      localeForLanguagePreference(AppLanguagePreference.turkish)?.languageCode,
      'tr',
    );
    expect(
      localeForLanguagePreference(AppLanguagePreference.arabic)?.languageCode,
      'ar',
    );
  });

  testWidgets('uses the selected language override in MaterialApp', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: localeForLanguagePreference(AppLanguagePreference.turkish),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: resolveAppLocale,
        home: Builder(
          builder: (context) => Text(AppLocalizations.of(context)!.home),
        ),
      ),
    );

    expect(find.text('Ana Sayfa'), findsOneWidget);
  });

  testWidgets('unsupported system locale uses English and LTR layout', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: resolveAppLocale,
        home: Builder(
          builder: (context) {
            expect(Directionality.of(context), TextDirection.ltr);
            return Text(AppLocalizations.of(context)!.options);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Options'), findsOneWidget);
  });
}
