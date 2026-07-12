import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final Future<void> Function(int destination) onFinished;

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save setup. Please try again.'),
          ),
        );
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
                  semanticLabel: 'AetherTune',
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome to AetherTune',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Start with music you control, or choose a legal source. You can change every choice later in Options.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                _SetupChoice(
                  icon: Icons.folder_open_outlined,
                  title: 'Set up a local library',
                  description:
                      'Import audio files or a folder, then keep watched folders in sync while the app is open.',
                  actionLabel: 'Open Library',
                  enabled: !_submitting,
                  onPressed: () => _finish(1),
                ),
                const SizedBox(height: 12),
                _SetupChoice(
                  icon: Icons.extension_outlined,
                  title: 'Explore legal sources',
                  description:
                      'Add podcast RSS feeds, browse Radio Browser, Internet Archive, or connect your own supported media server.',
                  actionLabel: 'Open Sources',
                  enabled: !_submitting,
                  onPressed: () => _finish(4),
                ),
                const SizedBox(height: 12),
                _SetupChoice(
                  icon: Icons.shield_outlined,
                  title: 'Privacy first',
                  description:
                      'AetherTune has no telemetry. Network providers disclose the domains they contact before use.',
                  actionLabel: 'Start at Home',
                  enabled: !_submitting,
                  onPressed: () => _finish(0),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submitting ? null : () => _finish(0),
                    child: const Text('Skip setup'),
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
