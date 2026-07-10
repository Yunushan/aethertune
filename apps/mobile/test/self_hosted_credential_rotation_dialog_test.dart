import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/self_hosted_provider_account.dart';
import 'package:aethertune/src/ui/widgets/self_hosted_credential_rotation_dialog.dart';

void main() {
  testWidgets('requires matching obscured credentials before rotation', (
    tester,
  ) async {
    final rotatedSecrets = <String>[];
    await tester.pumpWidget(
      _RotationHarness(
        onRotate: (secret) async => rotatedSecrets.add(secret),
      ),
    );

    await tester.tap(find.text('Open rotation'));
    await tester.pumpAndSettle();

    final secretField = tester.widget<TextField>(
      find.byKey(const Key('self-hosted-new-secret')),
    );
    final confirmationField = tester.widget<TextField>(
      find.byKey(const Key('self-hosted-confirm-secret')),
    );
    expect(secretField.obscureText, isTrue);
    expect(confirmationField.obscureText, isTrue);

    await tester.enterText(
      find.byKey(const Key('self-hosted-new-secret')),
      'new-api-key',
    );
    await tester.enterText(
      find.byKey(const Key('self-hosted-confirm-secret')),
      'different-api-key',
    );
    await tester.tap(find.byKey(const Key('self-hosted-test-rotate')));
    await tester.pump();

    expect(rotatedSecrets, isEmpty);
    expect(
      find.text('Credential confirmation does not match.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('self-hosted-confirm-secret')),
      'new-api-key',
    );
    await tester.tap(find.byKey(const Key('self-hosted-test-rotate')));
    await tester.pumpAndSettle();

    expect(rotatedSecrets, <String>['new-api-key']);
    expect(find.text('Rotation result: true'), findsOneWidget);
  });

  testWidgets('keeps the dialog open and redacts a rejected credential', (
    tester,
  ) async {
    await tester.pumpWidget(
      _RotationHarness(
        onRotate: (secret) async {
          throw StateError('Server rejected $secret.');
        },
      ),
    );

    await tester.tap(find.text('Open rotation'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('self-hosted-new-secret')),
      'rejected-api-key',
    );
    await tester.enterText(
      find.byKey(const Key('self-hosted-confirm-secret')),
      'rejected-api-key',
    );
    await tester.tap(find.byKey(const Key('self-hosted-test-rotate')));
    await tester.pumpAndSettle();

    expect(find.byType(SelfHostedCredentialRotationDialog), findsOneWidget);
    final error = tester.widget<Text>(
      find.byKey(const Key('self-hosted-rotation-error')),
    );
    expect(error.data, contains('[redacted]'));
    expect(error.data, isNot(contains('rejected-api-key')));
  });
}

class _RotationHarness extends StatefulWidget {
  const _RotationHarness({required this.onRotate});

  final SelfHostedCredentialRotator onRotate;

  @override
  State<_RotationHarness> createState() => _RotationHarnessState();
}

class _RotationHarnessState extends State<_RotationHarness> {
  bool? _result;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: <Widget>[
              TextButton(
                onPressed: () async {
                  final result = await showSelfHostedCredentialRotationDialog(
                    context,
                    account: createSelfHostedProviderAccount(
                      kind: SelfHostedProviderKind.jellyfin,
                      name: 'Home server',
                      baseUrl: 'https://media.example.test',
                      identity: 'user-1',
                      allowInsecureHttp: false,
                    ),
                    onRotate: widget.onRotate,
                  );
                  if (mounted) {
                    setState(() => _result = result);
                  }
                },
                child: const Text('Open rotation'),
              ),
              Text('Rotation result: ${_result ?? 'none'}'),
            ],
          ),
        ),
      ),
    );
  }
}
