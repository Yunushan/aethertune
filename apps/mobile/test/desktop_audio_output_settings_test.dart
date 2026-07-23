import 'package:aethertune/src/ui/desktop_audio_output_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exposes Windows Sound settings only on Windows', () {
    expect(supportsDesktopAudioOutputSettings(TargetPlatform.windows), isTrue);
    expect(supportsDesktopAudioOutputSettings(TargetPlatform.linux), isFalse);
    expect(supportsDesktopAudioOutputSettings(TargetPlatform.macOS), isFalse);
    expect(
      desktopAudioOutputSettingsUri(TargetPlatform.windows),
      Uri.parse('ms-settings:sound'),
    );
    expect(desktopAudioOutputSettingsUri(TargetPlatform.linux), isNull);
  });

  test('opens Windows Sound settings through an external launcher', () async {
    Uri? opened;

    final result = await openDesktopAudioOutputSettings(
      platform: TargetPlatform.windows,
      launcher: (uri) async {
        opened = uri;
        return true;
      },
    );

    expect(result, isTrue);
    expect(opened, Uri.parse('ms-settings:sound'));
  });

  test('does not invoke a launcher from unsupported platforms', () async {
    var invoked = false;

    final result = await openDesktopAudioOutputSettings(
      platform: TargetPlatform.linux,
      launcher: (_) async {
        invoked = true;
        return true;
      },
    );

    expect(result, isFalse);
    expect(invoked, isFalse);
  });
}
