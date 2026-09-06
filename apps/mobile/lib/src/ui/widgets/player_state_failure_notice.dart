import 'package:flutter/material.dart';

import '../../player/player_controller.dart';

class PlayerStateFailureNotice extends StatelessWidget {
  const PlayerStateFailureNotice({
    super.key,
    required this.player,
    required this.child,
    this.navigatorKey,
  });

  final PlayerController player;
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: player,
    child: child,
    builder: (context, child) {
      final error = player.persistenceError;
      if (error == null) return child!;
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: SafeArea(
                  bottom: false,
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: player.restoringPlayerState
                              ? null
                              : player.reloadSavedPlayerState,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reload saved player data'),
                        ),
                        TextButton.icon(
                          onPressed: player.restoringPlayerState
                              ? null
                              : () => _restorePrevious(context),
                          icon: const Icon(Icons.restore),
                          label: const Text('Restore previous player data'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: child!),
          ],
        ),
      );
    },
  );

  Future<void> _restorePrevious(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: navigatorKey?.currentContext ?? context,
      builder: (context) => Dialog(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                namesRoute: true,
                child: Text(
                  'Restore previous player data?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Playback will stop. The previous saved queues and playback settings will replace the current player snapshot. Current files are archived for recovery.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Restore'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && context.mounted) {
      await player.reloadSavedPlayerState(previous: true);
    }
  }
}
