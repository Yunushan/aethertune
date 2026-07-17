import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

enum PlatformImageShareStatus { shared, dismissed, unavailable }

/// A private, in-memory PNG handoff to the platform share sheet.
final class PlatformImageShareRequest {
  PlatformImageShareRequest({
    required Uint8List bytes,
    required String fileName,
    this.title = 'AetherTune',
    this.subject = 'AetherTune image',
    this.text,
    this.sharePositionOrigin,
  }) : bytes = _requiredBytes(bytes),
       fileName = _requiredPngFileName(fileName),
       text = _optionalText(text);

  final Uint8List bytes;
  final String fileName;
  final String title;
  final String subject;
  final String? text;
  final Rect? sharePositionOrigin;

  static Uint8List _requiredBytes(Uint8List value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'bytes', 'PNG data cannot be empty.');
    }
    return Uint8List.fromList(value);
  }

  static String _requiredPngFileName(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,119}\.png$').hasMatch(
      normalized,
    )) {
      throw ArgumentError.value(
        value,
        'fileName',
        'PNG file names must use safe characters and end in .png.',
      );
    }
    return normalized;
  }

  static String? _optionalText(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}

abstract interface class PlatformImageShareService {
  Future<PlatformImageShareStatus> share(PlatformImageShareRequest request);
}

final class SharePlusImageShareService implements PlatformImageShareService {
  const SharePlusImageShareService();

  @override
  Future<PlatformImageShareStatus> share(
    PlatformImageShareRequest request,
  ) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        title: request.title,
        subject: request.subject,
        text: request.text,
        files: <XFile>[
          XFile.fromData(
            request.bytes,
            mimeType: 'image/png',
            name: request.fileName,
          ),
        ],
        fileNameOverrides: <String>[request.fileName],
        sharePositionOrigin: request.sharePositionOrigin,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => PlatformImageShareStatus.shared,
      ShareResultStatus.dismissed => PlatformImageShareStatus.dismissed,
      ShareResultStatus.unavailable => PlatformImageShareStatus.unavailable,
    };
  }
}

Rect? platformSharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return null;
  }
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}
