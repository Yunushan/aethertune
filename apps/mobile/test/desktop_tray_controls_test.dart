import 'package:aethertune/src/ui/widgets/desktop_tray_controls.dart';
import 'package:aethertune/src/domain/desktop_tray_action.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('routes desktop tray menu commands to their matching actions', () async {
    final actions = <String>[];
    final controller = DesktopTrayCommandController(
      onShowWindow: () {
        actions.add('show');
        return Future<void>.value();
      },
      onTogglePlayPause: () {
        actions.add('toggle');
        return Future<void>.value();
      },
      onPrevious: () {
        actions.add('previous');
        return Future<void>.value();
      },
      onNext: () {
        actions.add('next');
        return Future<void>.value();
      },
      onQuit: () {
        actions.add('quit');
        return Future<void>.value();
      },
    );

    for (final key in <String>[
      'show',
      'toggle-play-pause',
      'previous',
      'next',
      'quit',
    ]) {
      expect(await controller.handleMenuKey(key), isTrue);
    }
    expect(actions, <String>['show', 'toggle', 'previous', 'next', 'quit']);
    expect(await controller.handleMenuKey('unknown'), isFalse);
    expect(await controller.handleMenuKey(null), isFalse);
  });

  test('declares tray support only for desktop platforms', () {
    expect(supportsDesktopTray(TargetPlatform.linux), isTrue);
    expect(supportsDesktopTray(TargetPlatform.macOS), isTrue);
    expect(supportsDesktopTray(TargetPlatform.windows), isTrue);
    expect(supportsDesktopTray(TargetPlatform.android), isFalse);
    expect(supportsDesktopTray(TargetPlatform.iOS), isFalse);
  });

  test('keeps Show and Quit while filtering configured transport commands', () {
    expect(
      desktopTrayCommandsForActions(<DesktopTrayTransportAction>{
        DesktopTrayTransportAction.next,
      }),
      <DesktopTrayCommand>[
        DesktopTrayCommand.showWindow,
        DesktopTrayCommand.next,
        DesktopTrayCommand.quit,
      ],
    );
    expect(
      desktopTrayCommandsForActions(<DesktopTrayTransportAction>{}),
      <DesktopTrayCommand>[
        DesktopTrayCommand.showWindow,
        DesktopTrayCommand.quit,
      ],
    );
  });

  test('uses the selected policy for desktop window close events', () {
    expect(
      desktopWindowCloseAction(minimizeToTray: true),
      DesktopWindowCloseAction.hide,
    );
    expect(
      desktopWindowCloseAction(minimizeToTray: false),
      DesktopWindowCloseAction.quit,
    );
  });

  Future<List<MethodCall>> mountTray(
    WidgetTester tester, {
    required bool minimizeToTray,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        calls.add(call);
        return true;
      },
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DesktopTrayControls(
          minimizeToTray: minimizeToTray,
          transportActions: const <DesktopTrayTransportAction>{},
          onTogglePlayPause: () async {},
          onPrevious: () async {},
          onNext: () async {},
          child: const Text('ordinary desktop fixture'),
        ),
      ),
    );
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
    return calls;
  }

  Future<void> nativeClose(WidgetTester tester) async {
    tester.binding.channelBuffers.push(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onEvent', <String, Object>{'eventName': 'close'}),
      ),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets('allowed native close does not issue a second close', (
    tester,
  ) async {
    final calls = await mountTray(tester, minimizeToTray: false);
    expect(
      calls.singleWhere((call) => call.method == 'setPreventClose').arguments,
      <String, Object>{'isPreventClose': false},
    );
    calls.clear();
    await nativeClose(tester);
    expect(calls, isEmpty);
  });

  testWidgets('intercepted native close hides the retained window', (
    tester,
  ) async {
    final calls = await mountTray(tester, minimizeToTray: true);
    expect(
      calls.singleWhere((call) => call.method == 'setPreventClose').arguments,
      <String, Object>{'isPreventClose': true},
    );
    calls.clear();
    await nativeClose(tester);
    expect(calls.map((call) => call.method), <String>['hide']);
  });

  testWidgets('tray Quit still explicitly destroys its window once', (
    tester,
  ) async {
    final calls = await mountTray(tester, minimizeToTray: false);
    calls.clear();
    final listener =
        tester.state(find.byType(DesktopTrayControls)) as TrayListener;
    listener.onTrayMenuItemClick(
      MenuItem(key: 'quit', label: 'Quit AetherTune'),
    );
    await tester.pump();
    expect(calls.map((call) => call.method), <String>['destroy']);
  });

  test('embeds the generated PNG payload in a valid single-image ICO', () {
    final png = Uint8List.fromList(<int>[137, 80, 78, 71]);
    final ico = icoFileFromPng(png, width: 64, height: 32);
    final header = ByteData.sublistView(ico);

    expect(ico.length, 22 + png.length);
    expect(header.getUint16(2, Endian.little), 1);
    expect(header.getUint16(4, Endian.little), 1);
    expect(header.getUint8(6), 64);
    expect(header.getUint8(7), 32);
    expect(header.getUint16(10, Endian.little), 1);
    expect(header.getUint16(12, Endian.little), 32);
    expect(header.getUint32(14, Endian.little), png.length);
    expect(header.getUint32(18, Endian.little), 22);
    expect(ico.sublist(22), png);
  });

  test('rejects invalid ICO dimensions', () {
    expect(
      () => icoFileFromPng(Uint8List(1), width: 0, height: 64),
      throwsArgumentError,
    );
    expect(
      () => icoFileFromPng(Uint8List(1), width: 64, height: 257),
      throwsArgumentError,
    );
  });
}
