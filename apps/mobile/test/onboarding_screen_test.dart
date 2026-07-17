import 'package:aethertune/src/data/provider_credential_vault.dart';
import 'package:aethertune/src/data/self_hosted_provider_store.dart';
import 'package:aethertune/src/ui/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aethertune/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _localizedOnboarding({
  required Future<void> Function(int destination) onFinished,
  Locale locale = const Locale('en'),
  SelfHostedProviderStore? selfHosted,
}) {
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: OnboardingScreen(onFinished: onFinished),
  );
  return selfHosted == null
      ? app
      : ChangeNotifierProvider<SelfHostedProviderStore>.value(
          value: selfHosted,
          child: app,
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

  testWidgets('connects a self-hosted library before opening Sources', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final testedAccounts = <String>[];
    final selfHosted = SelfHostedProviderStore(
      credentialVault: _MemoryCredentialVault(),
      connectionTester: (account, secret) async {
        testedAccounts.add('${account.kind.name}:$secret');
      },
    );
    addTearDown(selfHosted.dispose);
    int? destination;

    await tester.pumpWidget(
      _localizedOnboarding(
        selfHosted: selfHosted,
        onFinished: (tab) async => destination = tab,
      ),
    );

    final connectServer = find.text('Connect server');
    await tester.scrollUntilVisible(connectServer, 300);
    await tester.tap(connectServer);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jellyfin'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('self-hosted-url')),
      'https://music.example.test',
    );
    await tester.enterText(
      find.byKey(const Key('self-hosted-identity')),
      'user-1',
    );
    await tester.enterText(
      find.byKey(const Key('self-hosted-secret')),
      'private-api-key',
    );
    await tester.tap(find.byKey(const Key('self-hosted-test-save')));
    await tester.pumpAndSettle();

    expect(destination, 4);
    expect(testedAccounts, <String>['jellyfin:private-api-key']);
    expect(selfHosted.accounts, hasLength(1));
    expect(selfHosted.hasCredential(selfHosted.accounts.single.id), isTrue);
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
    await tester.scrollUntilVisible(find.text('Kurulumu atla'), 300);
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

class _MemoryCredentialVault implements ProviderCredentialVault {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
