import 'package:aethertune/src/ui/widgets/offline_cache_foreground_worker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps automatic offline work in a resident desktop process', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        expect(
          shouldKeepOfflineQueueProcessingInProcess(
            platform: platform,
            state: state,
          ),
          isTrue,
        );
      }
      expect(
        shouldKeepOfflineQueueProcessingInProcess(
          platform: platform,
          state: AppLifecycleState.detached,
        ),
        isFalse,
      );
    }
  });

  test('hands mobile lifecycle pauses to the native background scheduler', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.fuchsia,
    ]) {
      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(
          shouldKeepOfflineQueueProcessingInProcess(
            platform: platform,
            state: state,
          ),
          isFalse,
        );
      }
    }
  });
}
