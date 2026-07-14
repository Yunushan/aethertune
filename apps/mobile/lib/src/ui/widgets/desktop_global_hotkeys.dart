import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

bool supportsDesktopGlobalHotkeys(TargetPlatform platform) {
  return platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows;
}

abstract interface class DesktopHotkeyRegistry {
  Future<void> register(
    HotKey hotKey, {
    required HotKeyHandler keyDownHandler,
  });

  Future<void> unregister(HotKey hotKey);
}

class SystemDesktopHotkeyRegistry implements DesktopHotkeyRegistry {
  const SystemDesktopHotkeyRegistry();

  @override
  Future<void> register(
    HotKey hotKey, {
    required HotKeyHandler keyDownHandler,
  }) {
    return hotKeyManager.register(hotKey, keyDownHandler: keyDownHandler);
  }

  @override
  Future<void> unregister(HotKey hotKey) {
    return hotKeyManager.unregister(hotKey);
  }
}

/// Registers desktop-wide transport keys while keeping each registration
/// independent: operating systems may reserve an individual media key.
class DesktopGlobalHotkeyController {
  DesktopGlobalHotkeyController({
    required Future<void> Function() onTogglePlayPause,
    required Future<void> Function() onPrevious,
    required Future<void> Function() onNext,
    DesktopHotkeyRegistry? registry,
  }) : _registry = registry ?? const SystemDesktopHotkeyRegistry(),
       _bindings = <_DesktopHotkeyBinding>[
         _DesktopHotkeyBinding(
           HotKey(
             identifier: 'aethertune.media_play_pause',
             key: PhysicalKeyboardKey.mediaPlayPause,
           ),
           onTogglePlayPause,
         ),
         _DesktopHotkeyBinding(
           HotKey(
             identifier: 'aethertune.media_previous',
             key: PhysicalKeyboardKey.mediaTrackPrevious,
           ),
           onPrevious,
         ),
         _DesktopHotkeyBinding(
           HotKey(
             identifier: 'aethertune.media_next',
             key: PhysicalKeyboardKey.mediaTrackNext,
           ),
           onNext,
         ),
       ];

  final DesktopHotkeyRegistry _registry;
  final List<_DesktopHotkeyBinding> _bindings;
  final List<HotKey> _registeredHotkeys = <HotKey>[];
  bool _started = false;
  bool _disposed = false;

  Future<void> start({TargetPlatform? platform}) async {
    if (_started ||
        _disposed ||
        kIsWeb ||
        !supportsDesktopGlobalHotkeys(platform ?? defaultTargetPlatform)) {
      return;
    }
    _started = true;
    for (final binding in _bindings) {
      try {
        await _registry.register(
          binding.hotKey,
          keyDownHandler: (_) => unawaited(binding.onPressed()),
        );
        if (_disposed) {
          await _registry.unregister(binding.hotKey);
        } else {
          _registeredHotkeys.add(binding.hotKey);
        }
      } on Object {
        // Reserved or unavailable system keys must not block the other keys.
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final hotKey in _registeredHotkeys.reversed) {
      try {
        await _registry.unregister(hotKey);
      } on Object {
        // Shutdown continues even if an OS has already released a key.
      }
    }
    _registeredHotkeys.clear();
  }
}

class DesktopGlobalHotkeys extends StatefulWidget {
  const DesktopGlobalHotkeys({
    required this.onTogglePlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.child,
    super.key,
  });

  final Future<void> Function() onTogglePlayPause;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;
  final Widget child;

  @override
  State<DesktopGlobalHotkeys> createState() => _DesktopGlobalHotkeysState();
}

class _DesktopGlobalHotkeysState extends State<DesktopGlobalHotkeys> {
  late final DesktopGlobalHotkeyController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DesktopGlobalHotkeyController(
      onTogglePlayPause: () => widget.onTogglePlayPause(),
      onPrevious: () => widget.onPrevious(),
      onNext: () => widget.onNext(),
    );
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _DesktopHotkeyBinding {
  const _DesktopHotkeyBinding(this.hotKey, this.onPressed);

  final HotKey hotKey;
  final Future<void> Function() onPressed;
}
