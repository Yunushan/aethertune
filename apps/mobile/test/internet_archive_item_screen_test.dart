import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/internet_archive_provider.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/ui/internet_archive_item_screen.dart';

void main() {
  testWidgets('shows archive item details and saves every playable file', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final item = parseInternetArchiveItem(_itemMetadataJson);

    String? openedCollection;
    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: InternetArchiveItemScreen(
            item: item,
            provider: InternetArchiveProvider(
              baseUri: Uri.parse('https://archive.org'),
            ),
            onOpenCollection: (collection) => openedCollection = collection,
          ),
        ),
      ),
    );

    expect(find.text('Aether Public Session'), findsOneWidget);
    expect(find.text('Open Artist'), findsOneWidget);
    expect(find.text('opensource_audio'), findsOneWidget);
    expect(find.text('ambient'), findsOneWidget);
    expect(
      find.text('Aether Public Session - aether-session-vbr'),
      findsOneWidget,
    );
    expect(find.text('Aether Public Session - aether-session'), findsOneWidget);

    await tester.tap(find.text('opensource_audio'));
    expect(openedCollection, 'opensource_audio');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Save all'));
    await tester.pump();

    expect(library.tracks, hasLength(2));
  });
}

const _itemMetadataJson = '''
{
  "metadata": {
    "identifier": "aether_session",
    "title": "Aether Public Session",
    "creator": ["Open Artist"],
    "subject": ["ambient"],
    "collection": ["opensource_audio"],
    "date": "2021"
  },
  "files": [
    {
      "name": "aether-session.flac",
      "format": "Flac",
      "length": "123.5"
    },
    {
      "name": "aether-session-vbr.mp3",
      "format": "VBR MP3",
      "length": "123.5"
    }
  ]
}
''';
