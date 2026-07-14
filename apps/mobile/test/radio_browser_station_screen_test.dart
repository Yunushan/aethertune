import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/radio_browser_provider.dart';
import 'package:aethertune/src/ui/radio_browser_station_screen.dart';

void main() {
  testWidgets('shows station details, saves, and validates the stream', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    var saved = false;
    var validationCalls = 0;
    final provider = RadioBrowserProvider(
      streamValidator: (uri) async {
        validationCalls += 1;
        return RadioBrowserStreamValidation(
          streamUri: uri,
          isPlayable: true,
          statusCode: 200,
          contentType: 'audio/aac',
          reason: 'Stream responded as audio/aac.',
        );
      },
    );
    final station = parseRadioBrowserStations(_stationJson).single;

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: RadioBrowserStationScreen(
            station: station,
            provider: provider,
            onPlay: (_) async {},
            onSave: (_) async => saved = true,
          ),
        ),
      ),
    );

    expect(find.text('Aether Radio'), findsOneWidget);
    expect(find.text('jazz'), findsOneWidget);
    expect(find.text('ambient'), findsOneWidget);
    expect(find.text('AAC / 128 kbps'), findsOneWidget);
    expect(find.text('https://station.example.test'), findsOneWidget);

    await tester.tap(find.byKey(const Key('radio-station-save')));
    await tester.pump();
    expect(saved, isTrue);

    await tester.tap(find.byKey(const Key('radio-station-validate')));
    await tester.pump();
    await tester.pump();
    expect(validationCalls, 1);
    await tester.fling(find.byType(ListView), const Offset(0, -500), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Stream validated'), findsOneWidget);
    expect(find.textContaining('audio/aac'), findsOneWidget);
  });
}

const _stationJson = '''
[
  {
    "stationuuid": "station-1",
    "name": "Aether Radio",
    "url_resolved": "https://stream.example.test/aac",
    "homepage": "https://station.example.test",
    "tags": "jazz, ambient",
    "countrycode": "US",
    "language": "english",
    "codec": "AAC",
    "bitrate": 128,
    "lastcheckok": 1
  }
]
''';
