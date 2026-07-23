import 'package:flutter/services.dart';

/// Bridges Android local-library access. Persisted document trees are used for
/// recursive folder imports; the narrow media permission remains for callers
/// that explicitly need it.
abstract final class AndroidAudioLibraryAccess {
  static const MethodChannel _channel = MethodChannel(
    'dev.aethertune/storage_access',
  );

  static Future<bool> request() async {
    try {
      return await _channel.invokeMethod<bool>('requestAudioLibraryAccess') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens this app's system settings page after a user declines a folder
  /// import permission request. Individual-file imports never need this.
  static Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAudioLibrarySettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<String?> selectPersistedAudioTree() async {
    try {
      final value = await _channel.invokeMethod<String>('selectAudioTree');
      return _contentUriOrNull(value);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<AndroidSafTreeMaterialization> materializeTree(
    String treeUri,
  ) async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'materializeAudioTree',
        <String, Object?>{'treeUri': treeUri},
      );
      if (value == null) {
        throw const FormatException('Android did not return a SAF tree scan.');
      }
      return AndroidSafTreeMaterialization.fromChannel(value);
    } on MissingPluginException {
      throw UnsupportedError('Persisted Android folder access is unavailable.');
    }
  }

  static Future<void> discardMaterialization(String stagingRootPath) async {
    try {
      await _channel.invokeMethod<void>(
        'discardAudioTreeMaterialization',
        <String, Object?>{'stagingRootPath': stagingRootPath},
      );
    } on PlatformException {
      // The staging cache is disposable; failure is safe because Android owns it.
    } on MissingPluginException {
      // Non-Android hosts never create a SAF materialization.
    }
  }

  static String? _contentUriOrNull(String? value) {
    if (value == null) {
      return null;
    }
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null ||
        parsed.scheme.toLowerCase() != 'content' ||
        parsed.host.isEmpty) {
      return null;
    }
    return parsed.toString();
  }
}

final class AndroidSafTreeMaterialization {
  const AndroidSafTreeMaterialization({
    required this.stagingRootPath,
    required this.sourceUriByRelativePath,
    required this.inaccessibleDirectoryCount,
  });

  factory AndroidSafTreeMaterialization.fromChannel(
    Map<String, Object?> value,
  ) {
    final stagingRootPath = value['stagingRootPath'] as String?;
    final rawFiles = value['audioFiles'];
    if (stagingRootPath == null || stagingRootPath.trim().isEmpty ||
        rawFiles is! List) {
      throw const FormatException('Android returned an invalid SAF tree scan.');
    }
    final sourceUriByRelativePath = <String, String>{};
    for (final rawFile in rawFiles) {
      if (rawFile is! Map) {
        continue;
      }
      final relativePath = rawFile['relativePath'] as String?;
      final sourceUri = AndroidAudioLibraryAccess._contentUriOrNull(
        rawFile['sourceUri'] as String?,
      );
      if (relativePath == null || relativePath.isEmpty || sourceUri == null) {
        continue;
      }
      sourceUriByRelativePath[relativePath] = sourceUri;
    }
    return AndroidSafTreeMaterialization(
      stagingRootPath: stagingRootPath,
      sourceUriByRelativePath: Map.unmodifiable(sourceUriByRelativePath),
      inaccessibleDirectoryCount:
          (value['inaccessibleDirectoryCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String stagingRootPath;
  final Map<String, String> sourceUriByRelativePath;
  final int inaccessibleDirectoryCount;
}
