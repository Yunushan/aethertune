import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/radio_browser_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';

void main() {
  test('parses radio browser station JSON into playable tracks', () {
    final stations = parseRadioBrowserStations(_singleStationJson);

    expect(stations, hasLength(1));
    expect(stations.single.name, 'Aether Radio');
    expect(
      stations.single.streamUri,
      Uri.parse('https://stream.example.test/aac'),
    );
    expect(stations.single.tags, <String>['jazz', 'ambient', 'open']);
    expect(stations.single.isOnline, isTrue);

    final track = stations.single.toTrack(sourceId: 'radio-browser');

    expect(track.title, 'Aether Radio');
    expect(track.artist, 'US / english / AAC / 128kbps');
    expect(track.album, 'Internet Radio');
    expect(track.genre, 'jazz, ambient, open');
    expect(track.isPlayable, isTrue);
    expect(track.streamUrl, 'https://stream.example.test/aac');
    expect(track.externalId, 'station-1');
  });

  test(
    'search builds an official station search URI and resolves streams',
    () async {
      Uri? capturedUri;
      Uri? capturedClickUri;
      final provider = RadioBrowserProvider(
        baseUri: Uri.parse('https://de1.api.radio-browser.info'),
        searchLoader: (uri) async {
          capturedUri = uri;
          return _sampleStationsJson;
        },
        clickLoader: (uri) async {
          capturedClickUri = uri;
          return '{"ok":true}';
        },
        limit: 12,
      );

      expect(
        provider.capabilities,
        containsAll(const <MusicSourceCapability>[
          MusicSourceCapability.metadataSearch,
          MusicSourceCapability.radioDirectory,
          MusicSourceCapability.streamResolution,
          MusicSourceCapability.directPlayback,
        ]),
      );
      expect(provider.disclosure.networkDomains, <String>[
        'de1.api.radio-browser.info',
      ]);
      expect(provider.disclosure.dataSent, <String>[
        'station search query',
        'station click UUID',
      ]);

      final tracks = await provider.search('aether');

      expect(tracks, hasLength(1));
      expect(capturedUri!.path, '/json/stations/search');
      expect(capturedUri!.queryParameters['name'], 'aether');
      expect(capturedUri!.queryParameters['hidebroken'], 'true');
      expect(capturedUri!.queryParameters['limit'], '12');
      expect(capturedUri!.queryParameters['order'], 'clickcount');
      expect(capturedUri!.queryParameters['reverse'], 'true');
      expect(
        await provider.resolveStream(tracks.single),
        Uri.parse('https://stream.example.test/aac'),
      );

      await provider.recordStationClick(tracks.single);

      expect(capturedClickUri!.path, '/json/url/station-1');
    },
  );

  test('parses and selects radio browser mirrors', () {
    final mirrors = parseRadioBrowserMirrors('''
[
  {"name":"de1.api.radio-browser.info"},
  {"url":"http://legacy.radio-browser.example"},
  "https://nl1.api.radio-browser.info/json/servers",
  {"host":"bad scheme"},
  42
]
''');

    expect(
      mirrors.map((uri) => uri.toString()),
      <String>[
        'https://de1.api.radio-browser.info',
        'http://legacy.radio-browser.example',
        'https://nl1.api.radio-browser.info',
      ],
    );
    expect(
      selectRadioBrowserMirror(
        mirrors,
        fallback: Uri.parse('https://fallback.example.test'),
      ),
      Uri.parse('https://de1.api.radio-browser.info'),
    );
    expect(
      selectRadioBrowserMirror(
        <Uri>[Uri.parse('http://legacy.radio-browser.example')],
        fallback: Uri.parse('https://fallback.example.test'),
      ),
      Uri.parse('http://legacy.radio-browser.example'),
    );
  });

  test('discovers a radio browser mirror before search and click', () async {
    Uri? capturedMirrorUri;
    Uri? capturedSearchUri;
    Uri? capturedClickUri;
    final provider = RadioBrowserProvider(
      mirrorDirectoryUri: Uri.parse('https://mirrors.example.test/json/servers'),
      mirrorLoader: (uri) async {
        capturedMirrorUri = uri;
        return '[{"name":"nl1.api.radio-browser.info"}]';
      },
      searchLoader: (uri) async {
        capturedSearchUri = uri;
        return _sampleStationsJson;
      },
      clickLoader: (uri) async {
        capturedClickUri = uri;
        return '{"ok":true}';
      },
    );

    expect(provider.disclosure.networkDomains, <String>[
      'mirrors.example.test',
      'de1.api.radio-browser.info',
    ]);
    expect(
      provider.disclosure.dataSent,
      <String>[
        'mirror discovery request',
        'station search query',
        'station click UUID',
      ],
    );

    final tracks = await provider.search('aether');
    await provider.recordStationClick(tracks.single);

    expect(capturedMirrorUri!.host, 'mirrors.example.test');
    expect(capturedSearchUri!.host, 'nl1.api.radio-browser.info');
    expect(capturedSearchUri!.path, '/json/stations/search');
    expect(capturedClickUri!.host, 'nl1.api.radio-browser.info');
    expect(capturedClickUri!.path, '/json/url/station-1');
    expect(provider.baseUri, Uri.parse('https://nl1.api.radio-browser.info'));
    expect(provider.disclosure.networkDomains, <String>[
      'mirrors.example.test',
      'nl1.api.radio-browser.info',
    ]);
  });

  test('falls back to the bundled radio browser mirror on discovery failure', () async {
    Uri? capturedSearchUri;
    final provider = RadioBrowserProvider(
      mirrorLoader: (_) async => throw const FormatException('offline'),
      searchLoader: (uri) async {
        capturedSearchUri = uri;
        return _sampleStationsJson;
      },
    );

    final tracks = await provider.search('aether');

    expect(tracks, hasLength(1));
    expect(capturedSearchUri!.host, 'de1.api.radio-browser.info');
  });

  test('searchStations applies advanced filters to URI and results', () async {
    Uri? capturedUri;
    final provider = RadioBrowserProvider(
      baseUri: Uri.parse('https://de1.api.radio-browser.info'),
      searchLoader: (uri) async {
        capturedUri = uri;
        return _filteredStationsJson;
      },
    );

    final tracks = await provider.searchStations(
      'aether',
      filters: const RadioBrowserSearchFilters(
        countryCode: 'us',
        language: 'english',
        tag: 'ambient',
        codec: 'aac',
        minBitrateKbps: 64,
        maxBitrateKbps: 192,
      ),
    );

    expect(tracks.map((track) => track.title), <String>['Aether Radio']);
    expect(capturedUri!.queryParameters['name'], 'aether');
    expect(capturedUri!.queryParameters['countrycode'], 'US');
    expect(capturedUri!.queryParameters['language'], 'english');
    expect(capturedUri!.queryParameters['tag'], 'ambient');
    expect(capturedUri!.queryParameters['codec'], 'AAC');
    expect(capturedUri!.queryParameters['bitrateMin'], '64');
    expect(capturedUri!.queryParameters['bitrateMax'], '192');
  });

  test('ignores click accounting for non-radio tracks', () async {
    var clicked = false;
    final provider = RadioBrowserProvider(
      clickLoader: (_) async {
        clicked = true;
        return '{"ok":true}';
      },
    );

    await provider.recordStationClick(
      parseRadioBrowserStations(_singleStationJson)
          .single
          .toTrack(sourceId: 'another-provider'),
    );

    expect(clicked, isFalse);
  });

  test('skips stations without a usable stream URL', () {
    final stations = parseRadioBrowserStations('''
[
  {"stationuuid":"missing-url","name":"Missing URL"},
  {"stationuuid":"bad-url","name":"Bad URL","url_resolved":"not a url"},
  {"stationuuid":"ok","name":"OK","url":"https://stream.example.test/mp3"}
]
''');

    expect(stations.map((station) => station.stationUuid), <String>['ok']);
  });
}

const _sampleStationsJson = '''
[
  {
    "stationuuid": "station-1",
    "name": "Aether Radio",
    "url": "http://playlist.example.test/aether.pls",
    "url_resolved": "https://stream.example.test/aac",
    "homepage": "https://station.example.test",
    "favicon": "https://station.example.test/icon.png",
    "tags": "jazz, ambient, open",
    "countrycode": "US",
    "language": "english",
    "codec": "AAC",
    "bitrate": 128,
    "lastcheckok": 1
  },
  {
    "stationuuid": "video-stream",
    "name": "Not matched by query",
    "url_resolved": "https://stream.example.test/other",
    "tags": "talk"
  }
]
''';

const _singleStationJson = '''
[
  {
    "stationuuid": "station-1",
    "name": "Aether Radio",
    "url": "http://playlist.example.test/aether.pls",
    "url_resolved": "https://stream.example.test/aac",
    "homepage": "https://station.example.test",
    "favicon": "https://station.example.test/icon.png",
    "tags": "jazz, ambient, open",
    "countrycode": "US",
    "language": "english",
    "codec": "AAC",
    "bitrate": 128,
    "lastcheckok": 1
  }
]
''';

const _filteredStationsJson = '''
[
  {
    "stationuuid": "station-1",
    "name": "Aether Radio",
    "url_resolved": "https://stream.example.test/aac",
    "tags": "jazz, ambient, open",
    "countrycode": "US",
    "language": "english",
    "codec": "AAC",
    "bitrate": 128,
    "lastcheckok": 1
  },
  {
    "stationuuid": "station-low",
    "name": "Aether Low Bitrate",
    "url_resolved": "https://stream.example.test/low-aac",
    "tags": "ambient",
    "countrycode": "US",
    "language": "english",
    "codec": "AAC",
    "bitrate": 32,
    "lastcheckok": 1
  },
  {
    "stationuuid": "station-talk",
    "name": "Aether Talk",
    "url_resolved": "https://stream.example.test/talk",
    "tags": "talk",
    "countrycode": "GB",
    "language": "english",
    "codec": "MP3",
    "bitrate": 128,
    "lastcheckok": 1
  }
]
''';
