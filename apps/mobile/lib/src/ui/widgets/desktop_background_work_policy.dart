import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether a desktop process that remains resident in its system tray should
/// continue app-owned background work after its window is hidden or inactive.
bool shouldKeepBackgroundWorkInDesktopProcess({
  required TargetPlatform platform,
  required AppLifecycleState state,
}) {
  final isDesktop =
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows;
  return isDesktop &&
      (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused);
}
