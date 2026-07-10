import 'package:flutter/material.dart';

import '../../domain/self_hosted_provider_account.dart';

typedef SelfHostedAccountSaver = Future<void> Function(
  SelfHostedProviderAccount account,
  String secret,
);

Future<bool?> showSelfHostedAccountEditor(
  BuildContext context, {
  required SelfHostedProviderKind kind,
  required SelfHostedAccountSaver onSave,
  SelfHostedProviderAccount? account,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => SelfHostedAccountEditor(
      kind: kind,
      account: account,
      onSave: onSave,
    ),
  );
}

class SelfHostedAccountEditor extends StatefulWidget {
  const SelfHostedAccountEditor({
    required this.kind,
    required this.onSave,
    this.account,
    super.key,
  });

  final SelfHostedProviderKind kind;
  final SelfHostedProviderAccount? account;
  final SelfHostedAccountSaver onSave;

  @override
  State<SelfHostedAccountEditor> createState() =>
      _SelfHostedAccountEditorState();
}

class _SelfHostedAccountEditorState extends State<SelfHostedAccountEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _identityController;
  late final TextEditingController _secretController;
  late bool _allowInsecureHttp;
  bool _obscureSecret = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _nameController = TextEditingController(
      text: account?.name ?? widget.kind.label,
    );
    _baseUrlController = TextEditingController(
      text: account?.baseUri.toString() ?? 'https://',
    );
    _identityController = TextEditingController(text: account?.identity ?? '');
    _secretController = TextEditingController();
    _allowInsecureHttp = account?.allowInsecureHttp ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _identityController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.account != null;
    final usesHttp = _baseUrlController.text.trim().toLowerCase().startsWith(
          'http://',
        );

    return AlertDialog(
      title: Text(editing ? 'Edit ${widget.kind.label}' : 'Add ${widget.kind.label}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                key: const Key('self-hosted-name'),
                controller: _nameController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Display name'),
                textInputAction: TextInputAction.next,
              ),
              TextField(
                key: const Key('self-hosted-url'),
                controller: _baseUrlController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Server URL'),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _error = null),
              ),
              TextField(
                key: const Key('self-hosted-identity'),
                controller: _identityController,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: widget.kind.identityLabel,
                ),
                textInputAction: TextInputAction.next,
              ),
              if (!editing)
                TextField(
                  key: const Key('self-hosted-secret'),
                  controller: _secretController,
                  enabled: !_saving,
                  obscureText: _obscureSecret,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: widget.kind.secretLabel,
                    suffixIcon: IconButton(
                      tooltip:
                          _obscureSecret ? 'Show credential' : 'Hide credential',
                      onPressed: _saving
                          ? null
                          : () => setState(
                                () => _obscureSecret = !_obscureSecret,
                              ),
                      icon: Icon(
                        _obscureSecret
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                ),
              if (usesHttp)
                CheckboxListTile(
                  key: const Key('allow-insecure-http'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow insecure HTTP'),
                  subtitle: const Text(
                    'Credentials will be sent without TLS. Use HTTPS whenever possible.',
                  ),
                  value: _allowInsecureHttp,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                            () => _allowInsecureHttp = value ?? false,
                          ),
                ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    key: const Key('self-hosted-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (_saving) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  key: Key('self-hosted-saving'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('self-hosted-test-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Test and save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final account = widget.account == null
          ? createSelfHostedProviderAccount(
              kind: widget.kind,
              name: _nameController.text,
              baseUrl: _baseUrlController.text,
              identity: _identityController.text,
              allowInsecureHttp: _allowInsecureHttp,
            )
          : validateSelfHostedProviderAccount(
              widget.account!.copyWith(
                name: _nameController.text,
                baseUri: normalizeSelfHostedBaseUri(_baseUrlController.text),
                identity: _identityController.text,
                allowInsecureHttp: _allowInsecureHttp,
              ),
            );
      await widget.onSave(account, _secretController.text);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }
}
