import 'package:aethertune/src/ui/platform_audio_route_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.aethertune/audio_routes');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('exposes the route picker only on mobile platforms', () {
    expect(supportsPlatformAudioRoutePicker(TargetPlatform.android), isTrue);
    expect(supportsPlatformAudioRoutePicker(TargetPlatform.iOS), isTrue);
    expect(supportsPlatformAudioRoutePicker(TargetPlatform.linux), isFalse);
    expect(supportsPlatformAudioRoutePicker(TargetPlatform.macOS), isFalse);
    expect(supportsPlatformAudioRoutePicker(TargetPlatform.windows), isFalse);
  });

  test('asks the native mobile route picker to open', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });

    expect(
      await showPlatformAudioRoutePicker(platform: TargetPlatform.android),
      isTrue,
    );
    expect(calls, <MethodCall>[const MethodCall('showAudioRoutePicker')]);
  });

  test('does not send a platform message from desktop platforms', () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          invoked = true;
          return true;
        });

    expect(
      await showPlatformAudioRoutePicker(platform: TargetPlatform.windows),
      isFalse,
    );
    expect(invoked, isFalse);
  });
}
