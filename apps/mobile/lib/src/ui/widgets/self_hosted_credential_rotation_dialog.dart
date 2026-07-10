import 'package:flutter/material.dart';

import '../../domain/self_hosted_provider_account.dart';

typedef SelfHostedCredentialRotator = Future<void> Function(String newSecret);

Future<bool?> showSelfHostedCredentialRotationDialog(
  BuildContext context, {
  required SelfHostedProviderAccount account,
  required SelfHostedCredentialRotator onRotate,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => SelfHostedCredentialRotationDialog(
      account: account,
      onRotate: onRotate,
    ),
  );
}

class SelfHostedCredentialRotationDialog extends StatefulWidget {
  const SelfHostedCredentialRotationDialog({
    required this.account,
    required this.onRotate,
    super.key,
  });

  final SelfHostedProviderAccount account;
  final SelfHostedCredentialRotator onRotate;

  @override
  State<SelfHostedCredentialRotationDialog> createState() =>
      _SelfHostedCredentialRotationDialogState();
}

class _SelfHostedCredentialRotationDialogState
    extends State<SelfHostedCredentialRotationDialog> {
  final TextEditingController _secretController = TextEditingController();
  final TextEditingController _confirmationController =
      TextEditingController();
  bool _obscureSecret = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _secretController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secretLabel = widget.account.kind.secretLabel;
    return AlertDialog(
      title: Text('Rotate $secretLabel'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const Key('self-hosted-new-secret'),
              controller: _secretController,
              enabled: !_saving,
              obscureText: _obscureSecret,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'New $secretLabel',
                suffixIcon: IconButton(
                  tooltip: _obscureSecret
                      ? 'Show credentials'
                      : 'Hide credentials',
                  onPressed: _saving
                      ? null
                      : () => setState(
                            () => _obscureSecret = !_obscureSecret,
                          ),
                  icon: Icon(
                    _obscureSecret ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _error = null),
            ),
            TextField(
              key: const Key('self-hosted-confirm-secret'),
              controller: _confirmationController,
              enabled: !_saving,
              obscureText: _obscureSecret,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(labelText: 'Confirm $secretLabel'),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _rotate(),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  key: const Key('self-hosted-rotation-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
            if (_saving) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(
                key: Key('self-hosted-rotation-saving'),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('self-hosted-test-rotate'),
          onPressed: _saving ? null : _rotate,
          icon: const Icon(Icons.key_outlined),
          label: const Text('Test and rotate'),
        ),
      ],
    );
  }

  Future<void> _rotate() async {
    final secret = _secretController.text;
    if (secret.isEmpty) {
      setState(() => _error = '${widget.account.kind.secretLabel} is required.');
      return;
    }
    if (secret != _confirmationController.text) {
      setState(() => _error = 'Credential confirmation does not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onRotate(secret);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString().replaceAll(secret, '[redacted]');
      });
    }
  }
}
