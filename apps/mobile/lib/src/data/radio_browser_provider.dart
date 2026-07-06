import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef RadioBrowserSearchLoader = Future<String> Function(Uri searchUri);

class RadioBrowserProvider implements MusicSourceProvider {
  RadioBrowserProvider({
    Uri? baseUri,
    RadioBrowserSearchLoader? searchLoader,
    this.limit = 20,
  })  : baseUri = baseUri ?? Uri.parse('https://de1.api.radio-browser.info'),
        _searchLoader = searchLoader ?? _loadRadioBrowserSearch;

  final Uri baseUri;
  final int limit;
  final RadioBrowserSearchLoader _searchLoader;

  @override
  String get id => 'radio-browser';

  @override
  String get name => 'Radio Browser';

  @override
  String get description =>
      'Open internet radio directory for legal public station streams.';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.radioDirectory,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.directPlayback,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => ProviderPrivacyDisclosure(
        networkDomains: baseUri.host.isEmpty ? const <String>[] : <String>[
          baseUri.host,
        ],
        dataSent: const <String>['station search query'],
      );

  @override
  Future<List<Track>> search(String query) async {
    final normalized = query.trim();
    final stations = parseRadioBrowserStations(
      await _searchLoader(_searchUri(normalized)),
    );

    return stations
        .where((station) => station.matches(normalized))
        .map((station) => station.toTrack(sourceId: id))
        .toList(growable: false);
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    if (track.sourceId != id || track.streamUrl == null) {
      return null;
    }

    return Uri.tryParse(track.streamUrl!);
  }

  Uri _searchUri(String query) {
    return baseUri.replace(
      path: _joinUriPath(baseUri.path, '/json/stations/search'),
      queryParameters: <String, String>{
        if (query.isNotEmpty) 'name': query,
        'hidebroken': 'true',
        'limit': limit.toString(),
        'order': 'clickcount',
        'reverse': 'true',
      },
    );
  }
}

final class RadioBrowserStation {
  const RadioBrowserStation({
    required this.stationUuid,
    required this.name,
    required this.streamUri,
    required this.tags,
    required this.countryCode,
    required this.language,
    required this.codec,
    required this.bitrateKbps,
    required this.isOnline,
    this.homepageUri,
    this.artworkUri,
  });

  final String stationUuid;
  final String name;
  final Uri streamUri;
  final List<String> tags;
  final String countryCode;
  final String language;
  final String codec;
  final int bitrateKbps;
  final bool isOnline;
  final Uri? homepageUri;
  final Uri? artworkUri;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    return name.toLowerCase().contains(normalized) ||
        countryCode.toLowerCase().contains(normalized) ||
        language.toLowerCase().contains(normalized) ||
        tags.any((tag) => tag.toLowerCase().contains(normalized));
  }

  Track toTrack({required String sourceId}) {
    final details = <String>[
      if (countryCode.isNotEmpty) countryCode,
      if (language.isNotEmpty) language,
      if (codec.isNotEmpty) codec,
      if (bitrateKbps > 0) '${bitrateKbps}kbps',
    ];

    return Track(
      id: Track.stableLocalId('$sourceId|$stationUuid|$streamUri'),
      title: name,
      artist: details.isEmpty ? 'Radio Browser' : details.join(' / '),
      album: 'Internet Radio',
      genre: tags.isEmpty ? 'Internet Radio' : tags.take(3).join(', '),
      artworkUri: artworkUri,
      streamUrl: streamUri.toString(),
      sourceId: sourceId,
    );
  }
}

List<RadioBrowserStation> parseRadioBrowserStations(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! List<dynamic>) {
    throw const FormatException('Radio Browser station response must be a list.');
  }

  return decoded
      .whereType<Map<dynamic, dynamic>>()
      .map((json) => _stationFromJson(json.cast<String, Object?>()))
      .whereType<RadioBrowserStation>()
      .toList(growable: false);
}

RadioBrowserStation? _stationFromJson(Map<String, Object?> json) {
  final name = _stringValue(json['name']);
  final stationUuid = _stringValue(json['stationuuid']);
  final streamUri = _firstUri(
    _stringValue(json['url_resolved']),
    _stringValue(json['url']),
  );
  if (name.isEmpty || stationUuid.isEmpty || streamUri == null) {
    return null;
  }

  return RadioBrowserStation(
    stationUuid: stationUuid,
    name: name,
    streamUri: streamUri,
    tags: _splitTags(_stringValue(json['tags'])),
    countryCode: _stringValue(json['countrycode']),
    language: _stringValue(json['language']),
    codec: _stringValue(json['codec']),
    bitrateKbps: _intValue(json['bitrate']),
    isOnline: _boolValue(json['lastcheckok']),
    homepageUri: _uriValue(json['homepage']),
    artworkUri: _uriValue(json['favicon']),
  );
}

Future<String> _loadRadioBrowserSearch(Uri searchUri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(searchUri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Radio Browser search failed with HTTP ${response.statusCode}.',
        uri: searchUri,
      );
    }

    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}

Uri? _firstUri(String primary, String fallback) {
  return _uriValue(primary) ?? _uriValue(fallback);
}

Uri? _uriValue(Object? value) {
  final string = _stringValue(value);
  if (string.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(string);
  if (uri == null || !uri.hasScheme) {
    return null;
  }

  return uri;
}

String _stringValue(Object? value) {
  if (value == null) {
    return '';
  }

  return value.toString().trim();
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }

  return int.tryParse(_stringValue(value)) ?? 0;
}

bool _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }

  final string = _stringValue(value).toLowerCase();
  return string == '1' || string == 'true';
}

List<String> _splitTags(String value) {
  return value
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

String _joinUriPath(String basePath, String childPath) {
  final normalizedBase = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  return '$normalizedBase$childPath';
}
