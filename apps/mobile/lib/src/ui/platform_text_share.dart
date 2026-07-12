import 'dart:ui';

import 'package:share_plus/share_plus.dart';

enum PlatformTextShareStatus { shared, dismissed, unavailable }

class PlatformTextShareRequest {
  PlatformTextShareRequest({
    required String text,
    this.title = 'AetherTune',
    this.subject = 'AetherTune share',
    this.sharePositionOrigin,
  }) : text = _requiredText(text);

  final String text;
  final String title;
  final String subject;
  final Rect? sharePositionOrigin;

  static String _requiredText(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'text', 'Share text cannot be empty.');
    }
    return normalized;
  }
}

abstract interface class PlatformTextShareService {
  Future<PlatformTextShareStatus> share(PlatformTextShareRequest request);
}

class SharePlusTextShareService implements PlatformTextShareService {
  const SharePlusTextShareService();

  @override
  Future<PlatformTextShareStatus> share(
    PlatformTextShareRequest request,
  ) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: request.text,
        title: request.title,
        subject: request.subject,
        sharePositionOrigin: request.sharePositionOrigin,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => PlatformTextShareStatus.shared,
      ShareResultStatus.dismissed => PlatformTextShareStatus.dismissed,
      ShareResultStatus.unavailable => PlatformTextShareStatus.unavailable,
    };
  }
}
