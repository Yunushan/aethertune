import 'package:aethertune/src/data/android_audio_library_access.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('dev.aethertune/storage_access');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'requests explicit Android audio-library access through its channel',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          expect(call.method, 'requestAudioLibraryAccess');
          return true;
        },
      );

      expect(await AndroidAudioLibraryAccess.request(), isTrue);
    },
  );

  test(
    'treats unavailable Android access bridges as a denied request',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          throw PlatformException(code: 'not-available');
        },
      );

      expect(await AndroidAudioLibraryAccess.request(), isFalse);
    },
  );

  test('opens the app settings page only through its storage channel',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        expect(call.method, 'openAudioLibrarySettings');
        return true;
      },
    );

    expect(await AndroidAudioLibraryAccess.openAppSettings(), isTrue);
  });

  test('treats unavailable settings bridges as a no-op', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'not-available'),
    );

    expect(await AndroidAudioLibraryAccess.openAppSettings(), isFalse);
  });

  test('accepts only persisted content URIs from the Android tree picker',
      () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        expect(call.method, 'selectAudioTree');
        return 'content://com.android.providers.media.documents/tree/primary%3AMusic';
      },
    );

    expect(
      await AndroidAudioLibraryAccess.selectPersistedAudioTree(),
      'content://com.android.providers.media.documents/tree/primary%3AMusic',
    );
  });
}
