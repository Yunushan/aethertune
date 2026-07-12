const double desktopNavigationRailBreakpoint = 900;
const double desktopQueuePaneBreakpoint = 1200;

bool usesDesktopNavigationRail(double width) {
  return width >= desktopNavigationRailBreakpoint;
}

bool usesDesktopQueuePane(double width) {
  return width >= desktopQueuePaneBreakpoint;
}
