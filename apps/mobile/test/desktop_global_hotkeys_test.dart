import 'package:aethertune/src/ui/widgets/desktop_global_hotkeys.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sends valid Windows media codes and modifier lists to the native channel',
    () async {
      const channel = MethodChannel('dev.leanflutter.plugins/hotkey_manager');
      const events = MethodChannel(
        'dev.leanflutter.plugins/hotkey_manager_event',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      messenger.setMockMethodCallHandler(events, (_) async => null);
      final controller = DesktopGlobalHotkeyController(
        onTogglePlayPause: () async {},
        onPrevious: () async {},
        onNext: () async {},
      );
      try {
        await controller.start(platform: TargetPlatform.windows);
        final registrations = calls
            .where((call) => call.method == 'register')
            .toList();
        expect(registrations, hasLength(3));
        expect(
          registrations.map((call) => (call.arguments as Map)['keyCode']),
          <int>[0xb3, 0xb1, 0xb0],
        );
        for (final call in registrations) {
          final arguments = call.arguments as Map<Object?, Object?>;
          expect(arguments['identifier'], isA<String>());
          expect(arguments['keyCode'], isA<int>());
          expect(arguments['modifiers'], isA<List<Object?>>());
          expect(arguments['modifiers'], isEmpty);
        }
        await controller.dispose();
        expect(
          calls.where((call) => call.method == 'unregister'),
          hasLength(3),
        );
      } finally {
        await controller.dispose();
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(events, null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test('keeps native key-code lookup on non-Windows desktops', () async {
    final registry = _FakeDesktopHotkeyRegistry();
    final controller = DesktopGlobalHotkeyController(
      registry: registry,
      onTogglePlayPause: () async {},
      onPrevious: () async {},
      onNext: () async {},
    );
    for (final platform in <TargetPlatform>[
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await controller.start(platform: platform);
        expect(registry._hotkeys, hasLength(3));
        for (final hotKey in registry._hotkeys.values) {
          expect(hotKey.toJson().containsKey('keyCode'), isFalse);
          expect(hotKey.toJson()['modifiers'], isEmpty);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
    await controller.dispose();
  });

  test(
    'registers desktop-wide transport keys and routes their commands',
    () async {
      final registry = _FakeDesktopHotkeyRegistry();
      final actions = <String>[];
      final controller = DesktopGlobalHotkeyController(
        registry: registry,
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
      );

      await controller.start(platform: TargetPlatform.windows);

      expect(
        registry.registered.keys,
        unorderedEquals(<String>[
          'aethertune.media_play_pause',
          'aethertune.media_previous',
          'aethertune.media_next',
        ]),
      );
      registry.press('aethertune.media_play_pause');
      registry.press('aethertune.media_previous');
      registry.press('aethertune.media_next');
      expect(actions, <String>['toggle', 'previous', 'next']);

      await controller.dispose();
      expect(
        registry.unregistered,
        unorderedEquals(<String>[
          'aethertune.media_play_pause',
          'aethertune.media_previous',
          'aethertune.media_next',
        ]),
      );
    },
  );

  test(
    'keeps available global media keys when one is reserved by the OS',
    () async {
      final registry = _FakeDesktopHotkeyRegistry()
        ..failingIdentifiers.add('aethertune.media_play_pause');
      final controller = DesktopGlobalHotkeyController(
        registry: registry,
        onTogglePlayPause: () => Future<void>.value(),
        onPrevious: () => Future<void>.value(),
        onNext: () => Future<void>.value(),
      );

      await controller.start(platform: TargetPlatform.linux);

      expect(
        registry.registered.keys,
        unorderedEquals(<String>[
          'aethertune.media_previous',
          'aethertune.media_next',
        ]),
      );
    },
  );

  test(
    'does not register global media keys outside supported desktops',
    () async {
      final registry = _FakeDesktopHotkeyRegistry();
      final controller = DesktopGlobalHotkeyController(
        registry: registry,
        onTogglePlayPause: () => Future<void>.value(),
        onPrevious: () => Future<void>.value(),
        onNext: () => Future<void>.value(),
      );

      await controller.start(platform: TargetPlatform.android);

      expect(registry.registered, isEmpty);
    },
  );
}

class _FakeDesktopHotkeyRegistry implements DesktopHotkeyRegistry {
  final Map<String, HotKeyHandler> registered = <String, HotKeyHandler>{};
  final Set<String> failingIdentifiers = <String>{};
  final List<String> unregistered = <String>[];
  final Map<String, HotKey> _hotkeys = <String, HotKey>{};

  @override
  Future<void> register(
    HotKey hotKey, {
    required HotKeyHandler keyDownHandler,
  }) async {
    if (failingIdentifiers.contains(hotKey.identifier)) {
      throw StateError('Reserved by the operating system.');
    }
    registered[hotKey.identifier] = keyDownHandler;
    _hotkeys[hotKey.identifier] = hotKey;
  }

  @override
  Future<void> unregister(HotKey hotKey) async {
    unregistered.add(hotKey.identifier);
  }

  void press(String identifier) {
    registered[identifier]!(_hotkeys[identifier]!);
  }
}
