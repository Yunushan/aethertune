import 'package:aethertune/src/player/android_audio_virtualizer_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.aethertune/audio_virtualizer');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('clamps native Android virtualizer strength to its documented range', () {
    expect(normalizeAndroidVirtualizerStrength(-1), 0);
    expect(normalizeAndroidVirtualizerStrength(0), 0);
    expect(normalizeAndroidVirtualizerStrength(650), 650);
    expect(normalizeAndroidVirtualizerStrength(1000), 1000);
    expect(normalizeAndroidVirtualizerStrength(1001), 1000);
  });

  test('routes primary and crossfade sessions to the native virtualizer',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    final bridge = AndroidAudioVirtualizerBridge();

    expect(
      await bridge.attach(
        42,
        slot: AndroidAudioVirtualizerSlot.primary,
      ),
      isTrue,
    );
    expect(
      await bridge.attach(
        84,
        slot: AndroidAudioVirtualizerSlot.crossfade,
      ),
      isTrue,
    );
    expect(await bridge.setStrength(1250), isTrue);
    expect(await bridge.setEnabled(true), isTrue);

    expect(calls.map((call) => call.method), <String>[
      'attach',
      'attach',
      'setStrength',
      'setEnabled',
    ]);
    expect(calls[0].arguments, <String, Object>{
      'audioSessionId': 42,
      'slot': 'primary',
    });
    expect(calls[1].arguments, <String, Object>{
      'audioSessionId': 84,
      'slot': 'crossfade',
    });
    expect(calls[2].arguments, <String, Object>{'strength': 1000});
  });
}
