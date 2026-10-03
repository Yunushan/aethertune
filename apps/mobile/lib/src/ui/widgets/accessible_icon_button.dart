import 'package:flutter/material.dart';

/// Gives an existing icon button one explicit name on platforms whose
/// accessibility bridge does not use tooltip text as the button's name.
class AccessibleIconButton extends StatelessWidget {
  const AccessibleIconButton({required this.button, super.key});

  final IconButton button;

  @override
  Widget build(BuildContext context) {
    final label = button.tooltip;
    if (label == null || label.trim().isEmpty) {
      throw ArgumentError(
        'An accessible icon button needs a nonempty tooltip.',
      );
    }

    return TooltipTheme(
      data: TooltipTheme.of(context).copyWith(excludeFromSemantics: true),
      child: MergeSemantics(
        child: Semantics(label: label, child: button),
      ),
    );
  }
}
