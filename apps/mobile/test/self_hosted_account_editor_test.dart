import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/self_hosted_provider_account.dart';
import 'package:aethertune/src/ui/widgets/self_hosted_account_editor.dart';

void main() {
  testWidgets('obscures credentials and submits a tested HTTPS account', (
    tester,
  ) async {
    final saved = <SelfHostedProviderAccount>[];
    String? savedSecret;
    await tester.pumpWidget(
      _EditorHarness(
        kind: SelfHostedProviderKind.jellyfin,
        onSave: (account, secret) async {
          saved.add(account);
          savedSecret = secret;
        },
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    final secretField = tester.widget<TextField>(
      find.byKey(const Key('self-hosted-secret')),
    );
    expect(secretField.obscureText, isTrue);
    await tester.enterText(
      find.byKey(const Key('self-hosted-url')),
      'https://media.example.test/jellyfin',
    );
    await tester.enterText(
      find.byKey(const Key('self-hosted-identity')),
      'user-1',
    );
    await tester.enterText(
      find.byKey(const Key('self-hosted-secret')),
      'api-key',
    );
    await tester.tap(find.byKey(const Key('self-hosted-test-save')));
    await tester.pumpAndSettle();

    expect(saved.single.baseUri.path, '/jellyfin');
    expect(saved.single.identity, 'user-1');
    expect(savedSecret, 'api-key');
    expect(find.text('Saved: Jellyfin'), findsOneWidget);
  });

  testWidgets('requires explicit consent before sending credentials over HTTP', (
    tester,
  ) async {
    var saveCalls = 0;
    await tester.pumpWidget(
      _EditorHarness(
        kind: SelfHostedProviderKind.subsonic,
        onSave: (account, secret) async => saveCalls += 1,
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('self-hosted-url')),
      'http://192.168.1.10:4533',
    );
    await tester.enterText(
      find.byKey(const Key('self-hosted-identity')),
      'yunus',
    );
    await tester.enterText(
      find.byKey(const Key('self-hosted-secret')),
      'password',
    );
    await tester.tap(find.byKey(const Key('self-hosted-test-save')));
    await tester.pump();

    expect(saveCalls, 0);
    expect(find.textContaining('Confirm insecure HTTP'), findsOneWidget);

    await tester.tap(find.byKey(const Key('allow-insecure-http')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('self-hosted-test-save')));
    await tester.pumpAndSettle();

    expect(saveCalls, 1);
  });
}

class _EditorHarness extends StatefulWidget {
  const _EditorHarness({required this.kind, required this.onSave});

  final SelfHostedProviderKind kind;
  final SelfHostedAccountSaver onSave;

  @override
  State<_EditorHarness> createState() => _EditorHarnessState();
}

class _EditorHarnessState extends State<_EditorHarness> {
  String? _savedName;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: <Widget>[
              TextButton(
                onPressed: () async {
                  final result = await showSelfHostedAccountEditor(
                    context,
                    kind: widget.kind,
                    onSave: (account, secret) async {
                      await widget.onSave(account, secret);
                      _savedName = account.name;
                    },
                  );
                  if (mounted && result == true) {
                    setState(() {});
                  }
                },
                child: const Text('Open editor'),
              ),
              Text('Saved: ${_savedName ?? 'none'}'),
            ],
          ),
        ),
      ),
    );
  }
}
