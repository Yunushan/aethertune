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
  });

  test(
    'search builds an official station search URI and resolves streams',
    () async {
      Uri? capturedUri;
      final provider = RadioBrowserProvider(
        baseUri: Uri.parse('https://de1.api.radio-browser.info'),
        searchLoader: (uri) async {
          capturedUri = uri;
          return _sampleStationsJson;
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
      expect(provider.disclosure.dataSent, <String>['station search query']);

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
    },
  );

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
