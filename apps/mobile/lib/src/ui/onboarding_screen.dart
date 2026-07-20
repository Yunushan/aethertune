import 'package:flutter/material.dart';
import 'package:aethertune/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../data/self_hosted_provider_store.dart';
import '../domain/self_hosted_provider_account.dart';
import 'widgets/self_hosted_account_editor.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.onImportLocalLibrary,
  });

  final Future<void> Function(int destination) onFinished;
  final Future<void> Function()? onImportLocalLibrary;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _submitting = false;

  Future<void> _finish(int destination) async {
    if (_submitting) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onFinished(destination);
    } catch (_) {
      if (mounted) {
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.setupSaveError),
          ),
        );
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _startLocalLibraryImport() async {
    final onImportLocalLibrary = widget.onImportLocalLibrary;
    if (onImportLocalLibrary == null) {
      return _finish(1);
    }
    if (_submitting) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await onImportLocalLibrary();
    } catch (_) {
      if (mounted) {
        final localizations = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.setupSaveError),
          ),
        );
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _connectSelfHostedLibrary() async {
    if (_submitting) {
      return;
    }
    final kind = await showModalBottomSheet<SelfHostedProviderKind>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final candidate in SelfHostedProviderKind.values)
              ListTile(
                leading: Icon(
                  candidate == SelfHostedProviderKind.jellyfin
                      ? Icons.video_library_outlined
                      : Icons.cloud_queue_outlined,
                ),
                title: Text(candidate.label),
                onTap: () => Navigator.of(sheetContext).pop(candidate),
              ),
          ],
        ),
      ),
    );
    if (!mounted || kind == null) {
      return;
    }

    final saved = await showSelfHostedAccountEditor(
      context,
      kind: kind,
      onSave: (account, secret) =>
          context.read<SelfHostedProviderStore>().testAndSave(account, secret),
    );
    if (!mounted || saved != true) {
      return;
    }
    await _finish(4);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: <Widget>[
                Icon(
                  Icons.graphic_eq,
                  size: 56,
                  color: colorScheme.primary,
                  semanticLabel: localizations.appTitle,
                ),
                const SizedBox(height: 24),
                Text(
                  localizations.welcomeTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  localizations.welcomeDescription,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                _SetupChoice(
                  icon: Icons.folder_open_outlined,
                  title: localizations.localLibraryTitle,
                  description: localizations.localLibraryDescription,
                  actionLabel: widget.onImportLocalLibrary == null
                      ? localizations.openLibrary
                      : localizations.importAudio,
                  enabled: !_submitting,
                  onPressed: _startLocalLibraryImport,
                ),
                const SizedBox(height: 12),
                _SetupChoice(
                  icon: Icons.extension_outlined,
                  title: localizations.legalSourcesTitle,
                  description: localizations.legalSourcesDescription,
                  actionLabel: localizations.openSources,
                  enabled: !_submitting,
                  onPressed: () => _finish(4),
                ),
                const SizedBox(height: 12),
                _SetupChoice(
                  icon: Icons.dns_outlined,
                  title: localizations.selfHostedLibraryTitle,
                  description: localizations.selfHostedLibraryDescription,
                  actionLabel: localizations.connectServer,
                  enabled: !_submitting,
                  onPressed: _connectSelfHostedLibrary,
                ),
                const SizedBox(height: 12),
                _SetupChoice(
                  icon: Icons.shield_outlined,
                  title: localizations.privacyFirstTitle,
                  description: localizations.privacyFirstDescription,
                  actionLabel: localizations.startAtHome,
                  enabled: !_submitting,
                  onPressed: () => _finish(0),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submitting ? null : () => _finish(0),
                    child: Text(localizations.skipSetup),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupChoice extends StatelessWidget {
  const _SetupChoice({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(description),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: enabled ? onPressed : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(actionLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
