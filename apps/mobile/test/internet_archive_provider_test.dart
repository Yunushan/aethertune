import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/internet_archive_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';

void main() {
  test('parses Internet Archive metadata into a playable track', () {
    final item = parseInternetArchiveItem(_itemMetadataJson);

    expect(item.identifier, 'aether_session');
    expect(item.title, 'Aether Public Session');
    expect(item.creator, 'Open Artist');
    expect(item.subjects, <String>['ambient', 'public domain']);
    expect(item.playableAudioFile!.name, 'aether-session-vbr.mp3');

    final track = item.toTrack(
      sourceId: 'internet-archive',
      baseUri: Uri.parse('https://archive.org'),
    );

    expect(track, isNotNull);
    expect(track!.title, 'Aether Public Session');
    expect(track.artist, 'Open Artist');
    expect(track.album, 'Internet Archive / 2021');
    expect(track.genre, 'ambient');
    expect(track.duration, const Duration(milliseconds: 123500));
    expect(
      track.streamUrl,
      'https://archive.org/download/aether_session/aether-session-vbr.mp3',
    );
    expect(
      track.artworkUri,
      Uri.parse('https://archive.org/services/img/aether_session'),
    );
    expect(track.externalId, 'aether_session|aether-session-vbr.mp3');
    expect(
      item
          .toTracks(
            sourceId: 'internet-archive',
            baseUri: Uri.parse('https://archive.org'),
          )
          .map((track) => track.title),
      <String>[
        'Aether Public Session - aether-session-vbr',
        'Aether Public Session - aether-session',
      ],
    );
  });

  test(
    'search builds filtered archive queries and resolves playable files',
    () async {
      Uri? capturedSearchUri;
      final metadataUris = <Uri>[];
      final provider = InternetArchiveProvider(
        baseUri: Uri.parse('https://archive.org'),
        searchLoader: (uri) async {
          capturedSearchUri = uri;
          return _searchResultsJson;
        },
        metadataLoader: (uri) async {
          metadataUris.add(uri);
          if (uri.path.endsWith('/no_audio_item')) {
            return _noAudioMetadataJson;
          }
          return _itemMetadataJson;
        },
        limit: 5,
      );

      expect(
        provider.capabilities,
        containsAll(const <MusicSourceCapability>[
          MusicSourceCapability.metadataSearch,
          MusicSourceCapability.streamResolution,
          MusicSourceCapability.directPlayback,
        ]),
      );
      expect(provider.disclosure.networkDomains, <String>['archive.org']);
      expect(provider.disclosure.dataSent, <String>[
        'item search query',
        'item metadata identifier',
      ]);

      final tracks = await provider.searchAudio(
        'aether ambient',
        filters: const InternetArchiveSearchFilters(
          collection: 'opensource_audio',
          subject: 'ambient',
          creator: 'Open Artist',
          year: '2021',
        ),
      );

      expect(tracks.map((track) => track.title), <String>[
        'Aether Public Session - aether-session-vbr',
        'Aether Public Session - aether-session',
      ]);
      expect(capturedSearchUri!.path, '/advancedsearch.php');
      expect(
        capturedSearchUri!.queryParameters['q'],
        'mediatype:audio AND (aether ambient) AND '
        'collection:(opensource_audio) AND subject:(ambient) AND '
        'creator:(Open Artist) AND year:(2021)',
      );
      expect(
        capturedSearchUri!.queryParametersAll['fl[]'],
        contains('identifier'),
      );
      expect(capturedSearchUri!.queryParametersAll['fl[]'], contains('title'));
      expect(
        capturedSearchUri!.queryParametersAll.containsKey('facet[]'),
        isFalse,
      );
      expect(capturedSearchUri!.queryParametersAll['sort[]'], <String>[
        'downloads desc',
      ]);
      expect(capturedSearchUri!.queryParameters['rows'], '5');
      expect(capturedSearchUri!.queryParameters['output'], 'json');
      expect(metadataUris.map((uri) => uri.path), <String>[
        '/metadata/aether_session',
        '/metadata/no_audio_item',
      ]);
      expect(
        await provider.resolveStream(tracks.first),
        Uri.parse(
          'https://archive.org/download/aether_session/aether-session-vbr.mp3',
        ),
      );
    },
  );

  test('parses search facets', () {
    final page = parseInternetArchiveSearchPage(_searchResultsJson);

    expect(page.results.map((result) => result.identifier), <String>[
      'aether_session',
      'no_audio_item',
    ]);
    expect(page.facetsFor('collection').map((facet) => facet.value), <String>[
      'opensource_audio',
    ]);
    expect(page.facetsFor('subject').single.count, 7);
  });

  test('parses empty search results', () {
    expect(
      parseInternetArchiveSearchResults('{"response":{"docs":[]}}'),
      isEmpty,
    );
  });
}

const _searchResultsJson = '''
{
  "response": {
    "docs": [
      {
        "identifier": "aether_session",
        "title": "Aether Public Session"
      },
      {
        "identifier": "no_audio_item",
        "title": "Metadata Only"
      }
    ],
    "facets": {
      "collection": {
        "opensource_audio": 42
      },
      "subject": {
        "ambient": 7
      },
      "creator": {
        "Open Artist": 3
      },
      "year": {
        "2021": 2
      }
    }
  }
}
''';

const _itemMetadataJson = '''
{
  "metadata": {
    "identifier": "aether_session",
    "title": "Aether Public Session",
    "creator": ["Open Artist"],
    "subject": ["ambient", "public domain"],
    "collection": ["opensource_audio"],
    "date": "2021",
    "licenseurl": "https://creativecommons.org/publicdomain/zero/1.0/"
  },
  "files": [
    {
      "name": "aether-session_files.xml",
      "format": "Metadata"
    },
    {
      "name": "aether-session.flac",
      "format": "Flac",
      "length": "123.5",
      "source": "original"
    },
    {
      "name": "aether-session-vbr.mp3",
      "format": "VBR MP3",
      "length": "123.5",
      "source": "derivative"
    }
  ]
}
''';

const _noAudioMetadataJson = '''
{
  "metadata": {
    "identifier": "no_audio_item",
    "title": "Metadata Only"
  },
  "files": [
    {
      "name": "no_audio_item_meta.xml",
      "format": "Metadata"
    }
  ]
}
''';
