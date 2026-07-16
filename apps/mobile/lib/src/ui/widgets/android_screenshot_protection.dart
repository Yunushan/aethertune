import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';

class AndroidScreenshotProtection extends StatefulWidget {
  const AndroidScreenshotProtection({super.key, required this.child});

  final Widget child;

  @override
  State<AndroidScreenshotProtection> createState() =>
      _AndroidScreenshotProtectionState();
}

class _AndroidScreenshotProtectionState extends State<AndroidScreenshotProtection> {
  static const _channel = MethodChannel('dev.aethertune/screenshot_protection');
  bool? _applied;

  void _apply(bool enabled) {
    if (!Platform.isAndroid || _applied == enabled) {
      return;
    }
    _applied = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _channel.invokeMethod<void>('setEnabled', <String, Object?>{
        'enabled': enabled,
      }).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    _apply(context.watch<LibraryStore>().screenshotProtectionEnabled);
    return widget.child;
  }
}
