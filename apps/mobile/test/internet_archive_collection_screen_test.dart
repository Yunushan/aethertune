import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/internet_archive_provider.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/ui/internet_archive_collection_screen.dart';

void main() {
  testWidgets('browses a paginated Internet Archive collection', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final library = LibraryStore();
    await library.load();
    addTearDown(library.dispose);
    final requestedPages = <int>[];
    final provider = InternetArchiveProvider(
      limit: 1,
      searchLoader: (uri) async {
        expect(uri.queryParameters['q'], contains('collection:opensource_audio'));
        final page = int.parse(uri.queryParameters['page']!);
        requestedPages.add(page);
        return page == 1 ? _searchPage('first') : _searchPage('second');
      },
      metadataLoader: (uri) async => _metadataFor(uri.pathSegments.last),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: InternetArchiveCollectionScreen(
            collection: 'opensource_audio',
            provider: provider,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Collection first'), findsOneWidget);
    expect(find.text('Collection second'), findsNothing);
    expect(find.text('Load more archive items (1 remaining)'), findsOneWidget);

    await tester.tap(find.text('Load more archive items (1 remaining)'));
    await tester.pumpAndSettle();

    expect(find.text('Collection first'), findsOneWidget);
    expect(find.text('Collection second'), findsOneWidget);
    expect(find.text('All 2 archive results loaded.'), findsOneWidget);
    expect(requestedPages, <int>[1, 2]);
  });
}

String _searchPage(String identifier) {
  return '''
{
  "response": {
    "numFound": 2,
    "docs": [{"identifier": "$identifier"}]
  }
}
''';
}

String _metadataFor(String identifier) {
  return '''
{
  "metadata": {
    "identifier": "$identifier",
    "title": "Collection $identifier",
    "creator": "Archive Curator",
    "collection": "opensource_audio",
    "date": "2024"
  },
  "files": [
    {"name": "$identifier.mp3", "format": "VBR MP3", "length": "60"}
  ]
}
''';
}
