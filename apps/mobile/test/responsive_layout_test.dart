import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/ui/responsive_layout.dart';

void main() {
  test('uses navigation rail only at desktop widths', () {
    expect(usesDesktopNavigationRail(320), isFalse);
    expect(
      usesDesktopNavigationRail(desktopNavigationRailBreakpoint - 1),
      isFalse,
    );
    expect(usesDesktopNavigationRail(desktopNavigationRailBreakpoint), isTrue);
    expect(usesDesktopNavigationRail(1440), isTrue);
  });

  test('uses the queue pane only on wide desktop workspaces', () {
    expect(usesDesktopQueuePane(1199), isFalse);
    expect(usesDesktopQueuePane(desktopQueuePaneBreakpoint), isTrue);
    expect(usesDesktopQueuePane(1600), isTrue);
  });
}
