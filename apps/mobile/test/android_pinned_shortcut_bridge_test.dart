import 'package:aethertune/src/player/android_pinned_shortcut_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.aethertune/pinned_shortcuts-test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'requests an Android launcher pin for the selected transport action',
    () async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (incoming) async {
            call = incoming;
            return true;
          });
      final bridge = AndroidPinnedShortcutBridge(
        channel: channel,
        isAndroid: () => true,
      );

      expect(await bridge.requestPin(AndroidPinnedShortcut.playPause), isTrue);
      expect(call?.method, 'requestPin');
      expect(call?.arguments, <String, Object?>{'shortcut': 'playPause'});
    },
  );

  test(
    'does not invoke the channel outside Android and absorbs failures',
    () async {
      final outsideAndroid = AndroidPinnedShortcutBridge(
        channel: channel,
        isAndroid: () => false,
      );
      expect(
        await outsideAndroid.requestPin(AndroidPinnedShortcut.next),
        isFalse,
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'unsupported');
          });
      final failingBridge = AndroidPinnedShortcutBridge(
        channel: channel,
        isAndroid: () => true,
      );
      expect(
        await failingBridge.requestPin(AndroidPinnedShortcut.previous),
        isFalse,
      );
    },
  );
}
