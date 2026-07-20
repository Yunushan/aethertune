import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../domain/desktop_tray_action.dart';

bool supportsDesktopTray(TargetPlatform platform) {
  return platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows;
}

enum DesktopTrayCommand { showWindow, togglePlayPause, previous, next, quit }

List<DesktopTrayCommand> desktopTrayCommandsForActions(
  Set<DesktopTrayTransportAction> actions,
) {
  return <DesktopTrayCommand>[
    DesktopTrayCommand.showWindow,
    if (actions.contains(DesktopTrayTransportAction.previous))
      DesktopTrayCommand.previous,
    if (actions.contains(DesktopTrayTransportAction.togglePlayPause))
      DesktopTrayCommand.togglePlayPause,
    if (actions.contains(DesktopTrayTransportAction.next))
      DesktopTrayCommand.next,
    DesktopTrayCommand.quit,
  ];
}

enum DesktopWindowCloseAction { hide, quit }

DesktopWindowCloseAction desktopWindowCloseAction({
  required bool minimizeToTray,
}) {
  return minimizeToTray
      ? DesktopWindowCloseAction.hide
      : DesktopWindowCloseAction.quit;
}

class DesktopTrayCommandController {
  DesktopTrayCommandController({
    required this.onShowWindow,
    required this.onTogglePlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onQuit,
  });

  final Future<void> Function() onShowWindow;
  final Future<void> Function() onTogglePlayPause;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;
  final Future<void> Function() onQuit;

  Future<bool> handleMenuKey(String? key) async {
    final command = switch (key) {
      'show' => DesktopTrayCommand.showWindow,
      'toggle-play-pause' => DesktopTrayCommand.togglePlayPause,
      'previous' => DesktopTrayCommand.previous,
      'next' => DesktopTrayCommand.next,
      'quit' => DesktopTrayCommand.quit,
      _ => null,
    };
    if (command == null) {
      return false;
    }
    switch (command) {
      case DesktopTrayCommand.showWindow:
        await onShowWindow();
      case DesktopTrayCommand.togglePlayPause:
        await onTogglePlayPause();
      case DesktopTrayCommand.previous:
        await onPrevious();
      case DesktopTrayCommand.next:
        await onNext();
      case DesktopTrayCommand.quit:
        await onQuit();
    }
    return true;
  }
}

class DesktopTrayControls extends StatefulWidget {
  const DesktopTrayControls({
    required this.onTogglePlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.minimizeToTray,
    required this.transportActions,
    required this.child,
    super.key,
  });

  final Future<void> Function() onTogglePlayPause;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;
  final bool minimizeToTray;
  final Set<DesktopTrayTransportAction> transportActions;
  final Widget child;

  @override
  State<DesktopTrayControls> createState() => _DesktopTrayControlsState();
}

class _DesktopTrayControlsState extends State<DesktopTrayControls>
    with TrayListener, WindowListener {
  DesktopTrayCommandController? _commands;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || !supportsDesktopTray(defaultTargetPlatform)) {
      return;
    }
    _commands = DesktopTrayCommandController(
      onShowWindow: _showWindow,
      onTogglePlayPause: () => widget.onTogglePlayPause(),
      onPrevious: () => widget.onPrevious(),
      onNext: () => widget.onNext(),
      onQuit: _quit,
    );
    trayManager.addListener(this);
    windowManager.addListener(this);
    unawaited(_initializeTray());
    unawaited(_configureWindowCloseBehavior());
  }

  @override
  void didUpdateWidget(covariant DesktopTrayControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minimizeToTray != widget.minimizeToTray &&
        !kIsWeb &&
        supportsDesktopTray(defaultTargetPlatform)) {
      unawaited(_configureWindowCloseBehavior());
    }
    if (!setEquals(oldWidget.transportActions, widget.transportActions) &&
        !kIsWeb &&
        supportsDesktopTray(defaultTargetPlatform)) {
      unawaited(_refreshContextMenu());
    }
  }

  Future<void> _initializeTray() async {
    try {
      final iconPath = await DesktopTrayIconStore.instance.prepare();
      await trayManager.setIcon(
        iconPath,
        isTemplate: defaultTargetPlatform == TargetPlatform.macOS,
      );
      await trayManager.setToolTip('AetherTune');
      await _setContextMenu();
      _initialized = true;
    } on Object {
      // A missing desktop integration must not interfere with playback.
    }
  }

  Future<void> _setContextMenu() {
    final commands = desktopTrayCommandsForActions(widget.transportActions);
    final transportCommands = commands.sublist(1, commands.length - 1);
    return trayManager.setContextMenu(
      Menu(
        items: <MenuItem>[
          MenuItem(key: 'show', label: 'Show AetherTune'),
          MenuItem.separator(),
          for (final command in transportCommands)
            switch (command) {
              DesktopTrayCommand.previous => MenuItem(
                key: 'previous',
                label: 'Previous',
              ),
              DesktopTrayCommand.togglePlayPause => MenuItem(
                key: 'toggle-play-pause',
                label: 'Play / Pause',
              ),
              DesktopTrayCommand.next => MenuItem(key: 'next', label: 'Next'),
              _ => throw StateError('Unexpected tray transport command.'),
            },
          if (transportCommands.isNotEmpty) MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit AetherTune'),
        ],
      ),
    );
  }

  Future<void> _refreshContextMenu() async {
    try {
      await _setContextMenu();
    } on Object {
      // An unavailable desktop host must not interrupt app state updates.
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() => windowManager.destroy();

  Future<void> _configureWindowCloseBehavior() async {
    try {
      await windowManager.setPreventClose(widget.minimizeToTray);
    } on Object {
      // The app remains usable when a host cannot intercept close events.
    }
  }

  @override
  Future<void> onWindowClose() async {
    switch (
      desktopWindowCloseAction(minimizeToTray: widget.minimizeToTray)
    ) {
      case DesktopWindowCloseAction.hide:
        await windowManager.hide();
      case DesktopWindowCloseAction.quit:
        await windowManager.destroy();
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    unawaited(
      _commands?.handleMenuKey(menuItem.key) ?? Future<bool>.value(false),
    );
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    if (_initialized) {
      unawaited(trayManager.destroy());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class DesktopTrayIconStore {
  DesktopTrayIconStore._();

  static final instance = DesktopTrayIconStore._();
  Future<String>? _preparedIconPath;

  Future<String> prepare() => _preparedIconPath ??= _writeIconFiles();

  Future<String> _writeIconFiles() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = 64.0;
    const center = ui.Offset(size / 2, size / 2);
    canvas.drawCircle(
      center,
      30,
      ui.Paint()..color = const ui.Color(0xff00897b),
    );
    final play = ui.Path()
      ..moveTo(27, 20)
      ..lineTo(27, 44)
      ..lineTo(47, 32)
      ..close();
    canvas.drawPath(play, ui.Paint()..color = const ui.Color(0xffffffff));
    final image = await recorder.endRecording().toImage(64, 64);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      throw StateError('Unable to encode the desktop tray icon.');
    }
    final directory = await getApplicationSupportDirectory();
    final pngBytes = data.buffer.asUint8List();
    final pngPath = path.join(directory.path, 'aethertune_tray.png');
    await File(pngPath).writeAsBytes(pngBytes, flush: true);
    if (!Platform.isWindows) {
      return pngPath;
    }
    final icoPath = path.join(directory.path, 'aethertune_tray.ico');
    await File(icoPath).writeAsBytes(
      icoFileFromPng(pngBytes, width: 64, height: 64),
      flush: true,
    );
    return icoPath;
  }
}

Uint8List icoFileFromPng(
  Uint8List pngBytes, {
  required int width,
  required int height,
}) {
  if (width < 1 || width > 256 || height < 1 || height > 256) {
    throw ArgumentError.value(width, 'width', 'must be between 1 and 256');
  }
  final bytes = Uint8List(22 + pngBytes.length);
  final header = ByteData.sublistView(bytes);
  header
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, 1, Endian.little)
    ..setUint8(6, width == 256 ? 0 : width)
    ..setUint8(7, height == 256 ? 0 : height)
    ..setUint16(10, 1, Endian.little)
    ..setUint16(12, 32, Endian.little)
    ..setUint32(14, pngBytes.length, Endian.little)
    ..setUint32(18, 22, Endian.little);
  bytes.setRange(22, bytes.length, pngBytes);
  return bytes;
}
