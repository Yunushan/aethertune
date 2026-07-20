import 'package:aethertune/src/ui/android_video_picture_in_picture.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.aethertune/video_picture_in_picture-test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('enters Android Picture-in-Picture through its platform channel', () async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (incoming) async {
          call = incoming;
          return true;
        });
    final bridge = AndroidVideoPictureInPictureBridge(
      channel: channel,
      isAndroid: () => true,
    );

    expect(await bridge.enter(), isTrue);
    expect(call?.method, 'enter');
  });

  test('does not invoke PiP outside Android and absorbs failures', () async {
    final outsideAndroid = AndroidVideoPictureInPictureBridge(
      channel: channel,
      isAndroid: () => false,
    );
    expect(outsideAndroid.isSupportedPlatform, isFalse);
    expect(await outsideAndroid.enter(), isFalse);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'unavailable');
        });
    final failingBridge = AndroidVideoPictureInPictureBridge(
      channel: channel,
      isAndroid: () => true,
    );
    expect(await failingBridge.enter(), isFalse);
  });
}
