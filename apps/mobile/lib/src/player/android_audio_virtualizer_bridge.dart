import 'package:flutter/services.dart';

enum AndroidAudioVirtualizerSlot { primary, crossfade }

/// Android-only bridge for spatial virtualization attached to just_audio
/// sessions. The native side keeps separate effects for normal and crossfade
/// playback so an active overlap has the same spatial treatment.
class AndroidAudioVirtualizerBridge {
  static const MethodChannel _methods = MethodChannel(
    'dev.aethertune/audio_virtualizer',
  );

  Future<bool> attach(
    int audioSessionId, {
    required AndroidAudioVirtualizerSlot slot,
  }) async {
    if (audioSessionId <= 0) {
      return false;
    }
    try {
      return await _methods.invokeMethod<bool>(
            'attach',
            <String, Object>{
              'audioSessionId': audioSessionId,
              'slot': slot.name,
            },
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    try {
      return await _methods.invokeMethod<bool>(
            'setEnabled',
            <String, Object>{'enabled': enabled},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> setStrength(int strength) async {
    final normalized = normalizeAndroidVirtualizerStrength(strength);
    try {
      return await _methods.invokeMethod<bool>(
            'setStrength',
            <String, Object>{'strength': normalized},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> release() => _methods.invokeMethod<void>('release');
}

int normalizeAndroidVirtualizerStrength(int strength) {
  return strength.clamp(0, 1000);
}
