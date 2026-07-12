import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DesktopNavigationShortcutScope extends StatelessWidget {
  const DesktopNavigationShortcutScope({
    super.key,
    required this.enabled,
    required this.onDestinationSelected,
    required this.onPreviousDestination,
    required this.onNextDestination,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onPreviousDestination;
  final VoidCallback onNextDestination;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.digit1, control: true):
              () => onDestinationSelected(0),
          const SingleActivator(LogicalKeyboardKey.digit2, control: true):
              () => onDestinationSelected(1),
          const SingleActivator(LogicalKeyboardKey.digit3, control: true):
              () => onDestinationSelected(2),
          const SingleActivator(LogicalKeyboardKey.digit4, control: true):
              () => onDestinationSelected(3),
          const SingleActivator(LogicalKeyboardKey.digit5, control: true):
              () => onDestinationSelected(4),
          const SingleActivator(LogicalKeyboardKey.digit6, control: true):
              () => onDestinationSelected(5),
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
              onPreviousDestination,
          const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
              onNextDestination,
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
