import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/ui/aethertune_app.dart';
import 'package:aethertune/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        home: Builder(
          builder: (context) => Text(AppLocalizations.of(context)!.home),
        ),
      ),
    );

    expect(find.text('Ana Sayfa'), findsOneWidget);
  });
}
