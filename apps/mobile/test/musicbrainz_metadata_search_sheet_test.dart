import 'package:aethertune/src/data/musicbrainz_metadata_provider.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/musicbrainz_metadata_search_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('searches only after explicit action and renders candidates', (
    tester,
  ) async {
    var requests = 0;
    final provider = MusicBrainzMetadataProvider(
      limiter: MusicBrainzRequestLimiter(),
      loader: (_, _) async {
        requests += 1;
        return _response;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicBrainzMetadataSearchSheet(
            track: _track,
            provider: provider,
            offlineModeEnabled: false,
          ),
        ),
      ),
    );

    expect(requests, 0);
    expect(find.textContaining('Audio files and library paths are never sent'), findsOneWidget);

    await tester.tap(find.byKey(const Key('musicbrainz-metadata-search')));
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(find.text('Aether Song'), findsOneWidget);
    expect(find.textContaining('Mira Sol'), findsOneWidget);
  });

  testWidgets('offline mode disables the metadata request', (tester) async {
    var requests = 0;
    final provider = MusicBrainzMetadataProvider(
      limiter: MusicBrainzRequestLimiter(),
      loader: (_, _) async {
        requests += 1;
        return _response;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicBrainzMetadataSearchSheet(
            track: _track,
            provider: provider,
            offlineModeEnabled: true,
          ),
        ),
      ),
    );

    expect(
      tester.widget<FilledButton>(
        find.byKey(const Key('musicbrainz-metadata-search')),
      ).onPressed,
      isNull,
    );
    expect(find.textContaining('No MusicBrainz request can be made'), findsOneWidget);
    expect(requests, 0);
  });
}

final _track = Track(
  id: 'local-aether-song',
  title: 'Aether Song',
  artist: 'Mira Sol',
  album: 'Night Signal',
  genre: 'Ambient',
  duration: const Duration(minutes: 3, seconds: 35),
);

const _response = '''
{
  "recordings": [
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "title": "Aether Song",
      "artist-credit": [{"name": "Mira Sol"}],
      "releases": [{"title": "Night Signal"}],
      "genres": [{"name": "Ambient"}],
      "length": 215000,
      "score": 99
    }
  ]
}
''';
