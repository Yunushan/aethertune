import 'dart:async';

import 'package:aethertune/src/ui/video_playback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as media;

void main() {
  Future<void> show(
    WidgetTester tester,
    VideoPlaybackFactory factory, {
    String source = 'https://example.invalid/fixture.mp4',
    TextDirection direction = TextDirection.ltr,
    double textScale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: VideoPlaybackScreen(
            source: Uri.parse(source),
            title: 'Fixture',
            playbackFactory: factory,
          ),
        ),
      ),
    ),
  );

  testWidgets('opens the requested source and releases its owned player', (
    tester,
  ) async {
    final engine = _VideoEngine();
    await show(tester, () => engine.playback);
    await tester.pumpAndSettle();
    expect(engine.sources, ['https://example.invalid/fixture.mp4']);
    expect(find.byKey(engine.surfaceKey), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Could not open this video.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(engine.disposals, 1);
  });

  testWidgets('native error events replace loading with a safe retry state', (
    tester,
  ) async {
    final engine = _VideoEngine();
    final semantics = tester.ensureSemantics();
    try {
      await show(tester, () => engine.playback);
      await tester.pumpAndSettle();
      engine.emitError('Failed at https://host/?token=synthetic-secret');
      await tester.pumpAndSettle();
      expect(find.text('Could not open this video.'), findsOneWidget);
      expect(find.textContaining('synthetic-secret'), findsNothing);
      expect(find.byKey(engine.surfaceKey), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(engine.stops, 1);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Audio tracks',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.byTooltip('Retry video'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a late open completion cannot erase the native error', (
    tester,
  ) async {
    final opened = Completer<void>();
    final engine = _VideoEngine(openResult: opened.future);
    await show(tester, () => engine.playback);
    await tester.pump();
    engine.emitError('Unrecognized format');
    await tester.pump();
    opened.complete();
    await tester.pumpAndSettle();
    expect(find.text('Could not open this video.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('retry replaces the failed native player and recovers', (
    tester,
  ) async {
    final first = _VideoEngine();
    final second = _VideoEngine();
    var created = 0;
    await show(tester, () => created++ == 0 ? first.playback : second.playback);
    await tester.pumpAndSettle();
    first.emitError('Unrecognized format');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Retry video'));
    // Stream cancellation completes in the Dart root zone, outside fake async.
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(created, 2);
    expect(first.disposals, 1);
    expect(first.disposed, isTrue);
    expect(second.sources, ['https://example.invalid/fixture.mp4']);
    expect(find.byKey(second.surfaceKey), findsOneWidget);
    expect(find.text('Could not open this video.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source replacement ignores failures from the old open', (
    tester,
  ) async {
    final opened = Completer<void>();
    final first = _VideoEngine(openResult: opened.future);
    final second = _VideoEngine();
    var created = 0;
    VideoPlayback factory() =>
        created++ == 0 ? first.playback : second.playback;
    await show(tester, factory);
    await tester.pump();
    await show(tester, factory, source: 'https://example.invalid/new.webm');
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    opened.completeError(StateError('old source failed'));
    await tester.pumpAndSettle();
    expect(first.disposals, 1);
    expect(first.disposed, isTrue);
    expect(second.sources, ['https://example.invalid/new.webm']);
    expect(find.byKey(second.surfaceKey), findsOneWidget);
    expect(find.text('Could not open this video.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unmount during opening cancels error delivery and owns cleanup',
    (tester) async {
      final opened = Completer<void>();
      final engine = _VideoEngine(openResult: opened.future);
      await show(tester, () => engine.playback);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {});
      opened.completeError(StateError('closed source'));
      await tester.pumpAndSettle();
      expect(engine.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('initialization failure offers retry without exposing details', (
    tester,
  ) async {
    final engine = _VideoEngine();
    var attempts = 0;
    await show(tester, () {
      if (attempts++ == 0) throw StateError('private native path');
      return engine.playback;
    });
    await tester.pumpAndSettle();
    expect(find.text('Could not open this video.'), findsOneWidget);
    expect(find.textContaining('private native path'), findsNothing);
    await tester.tap(find.byTooltip('Retry video'));
    await tester.pumpAndSettle();
    expect(find.byKey(engine.surfaceKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening expires and a late completion cannot clear the error', (
    tester,
  ) async {
    final opened = Completer<void>();
    final engine = _VideoEngine(openResult: opened.future);
    await show(tester, () => engine.playback);
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Could not open this video.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(engine.stops, 1);
    opened.complete();
    await tester.pumpAndSettle();
    expect(find.text('Could not open this video.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening remains pending until the first frame renders', (
    tester,
  ) async {
    final frame = Completer<void>();
    final engine = _VideoEngine(firstFrameResult: frame.future);
    await show(tester, () => engine.playback);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 29));
    expect(find.text('Could not open this video.'), findsNothing);
    frame.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Could not open this video.'), findsNothing);
    expect(engine.stops, 0);
  });

  testWidgets('a missing first frame times out even when open completed', (
    tester,
  ) async {
    final frame = Completer<void>();
    final first = _VideoEngine(firstFrameResult: frame.future);
    final second = _VideoEngine();
    var created = 0;
    await show(tester, () => created++ == 0 ? first.playback : second.playback);
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Could not open this video.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byTooltip('Retry video'));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(first.disposed, isTrue);
    expect(created, 2);
    expect(find.byKey(second.surfaceKey), findsOneWidget);
    frame.completeError(StateError('stale native frame failure'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open this video.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stalled cleanup stays owned and cannot allocate retry players', (
    tester,
  ) async {
    final released = Completer<void>();
    final first = _VideoEngine(disposeResult: released.future);
    final second = _VideoEngine();
    var created = 0;
    await show(tester, () => created++ == 0 ? first.playback : second.playback);
    await tester.pumpAndSettle();
    first.emitError('failed media');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Retry video'));
    await tester.runAsync(() async {});
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Could not open this video.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(first.disposals, 1);
    expect(created, 1);

    await tester.tap(find.byTooltip('Retry video'));
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Could not open this video.'), findsOneWidget);
    expect(first.disposals, 1);
    expect(created, 1);
    released.complete();
    await tester.pumpAndSettle();
    expect(find.text('Could not open this video.'), findsOneWidget);
    await tester.tap(find.byTooltip('Retry video'));
    await tester.pumpAndSettle();
    expect(first.disposed, isTrue);
    expect(created, 2);
    expect(find.byKey(second.surfaceKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the latest source opens after slow owned cleanup', (
    tester,
  ) async {
    final released = Completer<void>();
    final first = _VideoEngine(disposeResult: released.future);
    final second = _VideoEngine();
    var created = 0;
    VideoPlayback factory() =>
        created++ == 0 ? first.playback : second.playback;
    await show(tester, factory);
    await tester.pumpAndSettle();
    await show(tester, factory, source: 'https://example.invalid/second.mp4');
    await tester.runAsync(() async {});
    await tester.pump();
    await show(tester, factory, source: 'https://example.invalid/third.mp4');
    await tester.pump();
    expect(created, 1);
    released.complete();
    await tester.pumpAndSettle();
    expect(created, 2);
    expect(first.disposals, 1);
    expect(second.sources, ['https://example.invalid/third.mp4']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unmount during cleanup does not lose ownership or open a player',
    (tester) async {
      final released = Completer<void>();
      final first = _VideoEngine(disposeResult: released.future);
      var created = 0;
      VideoPlayback factory() {
        created++;
        return first.playback;
      }

      await show(tester, factory);
      await tester.pumpAndSettle();
      await show(tester, factory, source: 'https://example.invalid/new.mp4');
      await tester.runAsync(() async {});
      await tester.pumpWidget(const SizedBox.shrink());
      released.complete();
      await tester.pumpAndSettle();
      expect(first.disposals, 1);
      expect(first.disposed, isTrue);
      expect(created, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cleanup failure prevents replacement and keeps details private',
    (tester) async {
      final released = Completer<void>();
      final first = _VideoEngine(disposeResult: released.future);
      var created = 0;
      VideoPlayback factory() {
        created++;
        return first.playback;
      }

      await show(tester, factory);
      await tester.pumpAndSettle();
      await show(tester, factory, source: 'https://example.invalid/new.mp4');
      await tester.runAsync(() async {});
      released.completeError(StateError('private native cleanup path'));
      await tester.pumpAndSettle();
      expect(find.text('Could not open this video.'), findsOneWidget);
      expect(find.textContaining('private native cleanup path'), findsNothing);
      await tester.tap(find.byTooltip('Retry video'));
      await tester.pumpAndSettle();
      expect(created, 1);
      expect(first.disposals, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('first-frame failure does not wait for a stalled open command', (
    tester,
  ) async {
    final opened = Completer<void>();
    final frame = Completer<void>();
    final engine = _VideoEngine(
      openResult: opened.future,
      firstFrameResult: frame.future,
    );
    await show(tester, () => engine.playback);
    await tester.pump();
    frame.completeError(StateError('native frame creation failed'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open this video.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    opened.completeError(StateError('late command failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('unmount cancels the first-frame deadline', (tester) async {
    final frame = Completer<void>();
    final engine = _VideoEngine(firstFrameResult: frame.future);
    await show(tester, () => engine.playback);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(engine.disposed, isTrue);
    frame.completeError(StateError('disposed native frame'));
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 480), const Size(480, 320)]) {
    for (final direction in TextDirection.values) {
      testWidgets('error and retry fit $size $direction at 3x text', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final engine = _VideoEngine();
        await show(
          tester,
          () => engine.playback,
          direction: direction,
          textScale: 3,
        );
        await tester.pumpAndSettle();
        engine.emitError('Unrecognized format');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Retry video'));
        expect(find.byTooltip('Retry video').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _VideoEngine extends media.PlatformPlayer {
  _VideoEngine({this.openResult, this.firstFrameResult, this.disposeResult})
    : super(configuration: const media.PlayerConfiguration());

  final Future<void>? openResult;
  final Future<void>? firstFrameResult;
  final Future<void>? disposeResult;
  final surfaceKey = UniqueKey();
  final sources = <String>[];
  int stops = 0;
  int disposals = 0;
  bool disposed = false;

  void emitError(String message) => errorController.add(message);

  VideoPlayback get playback => (
    player: media.Player(platformPlayer: this),
    video: ColoredBox(key: surfaceKey, color: Colors.black),
    firstFrame: firstFrameResult ?? Future<void>.value(),
  );

  @override
  Future<void> open(media.Playable playable, {bool play = true}) async {
    sources.add((playable as media.Media).uri);
    await openResult;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {
    disposals++;
    await disposeResult;
    await super.dispose();
    disposed = true;
  }
}
