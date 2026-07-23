import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/listen_together_store.dart';
import 'package:aethertune/src/ui/widgets/listen_together_foreground_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('synchronizes a joined session when a desktop enters the tray', (
    tester,
  ) async {
    final library = LibraryStore();
    await library.load();
    var calls = 0;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: library),
          ChangeNotifierProvider<ListenTogetherStore>.value(
            value: _JoinedListenTogetherStore(),
          ),
        ],
        child: MaterialApp(
          home: ListenTogetherForegroundSync(
            platform: TargetPlatform.windows,
            runSynchronization: (_, _) async {
              calls += 1;
            },
            child: const SizedBox(),
          ),
        ),
      ),
    );

    await _sendLifecycleState(tester, AppLifecycleState.hidden);
    await tester.pump();

    expect(calls, 1);
  });
}

Future<void> _sendLifecycleState(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}

final class _JoinedListenTogetherStore extends ListenTogetherStore {
  _JoinedListenTogetherStore()
    : super(gatewayFactory: () => throw UnimplementedError());

  @override
  bool get joined => true;
}
