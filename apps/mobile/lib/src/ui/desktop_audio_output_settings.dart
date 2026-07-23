import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

typedef DesktopAudioOutputSettingsLauncher = Future<bool> Function(Uri uri);

/// Windows exposes its real output-device controls through the documented
/// Settings URI. AetherTune intentionally defers device enumeration and the
/// default-device decision to Windows instead of maintaining a second list.
bool supportsDesktopAudioOutputSettings(TargetPlatform platform) {
  return platform == TargetPlatform.windows;
}

Uri? desktopAudioOutputSettingsUri(TargetPlatform platform) {
  if (!supportsDesktopAudioOutputSettings(platform)) {
    return null;
  }
  return Uri.parse('ms-settings:sound');
}

Future<bool> openDesktopAudioOutputSettings({
  TargetPlatform? platform,
  DesktopAudioOutputSettingsLauncher? launcher,
}) async {
  final target = platform ?? defaultTargetPlatform;
  final uri = desktopAudioOutputSettingsUri(target);
  if (kIsWeb || uri == null) {
    return false;
  }

  try {
    if (launcher != null) {
      return await launcher(uri);
    }
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Exception {
    return false;
  }
}
