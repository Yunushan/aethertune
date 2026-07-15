import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef RadioBrowserSearchLoader = Future<String> Function(Uri searchUri);
typedef RadioBrowserClickLoader = Future<String> Function(Uri clickUri);
typedef RadioBrowserMirrorLoader = Future<String> Function(Uri mirrorsUri);
typedef RadioBrowserStreamValidator = Future<RadioBrowserStreamValidation>
    Function(Uri streamUri);

final Uri defaultRadioBrowserBaseUri = Uri(
  scheme: 'https',
  host: 'de1.api.radio-browser.info',
);
final Uri defaultRadioBrowserMirrorDirectoryUri = Uri(
  scheme: 'https',
  host: 'all.api.radio-browser.info',
  path: '/json/servers',
);

final class RadioBrowserSearchFilters {
  const RadioBrowserSearchFilters({
    this.countryCode = '',
    this.language = '',
    this.tag = '',
    this.codec = '',
    this.minBitrateKbps,
    this.maxBitrateKbps,
  });

  final String countryCode;
  final String language;
  final String tag;
  final String codec;
  final int? minBitrateKbps;
  final int? maxBitrateKbps;

  bool get isEmpty =>
      countryCode.trim().isEmpty &&
      language.trim().isEmpty &&
      tag.trim().isEmpty &&
      codec.trim().isEmpty &&
      minBitrateKbps == null &&
      maxBitrateKbps == null;
}

final class RadioBrowserStreamValidation {
  const RadioBrowserStreamValidation({
    required this.streamUri,
    required this.isPlayable,
    required this.reason,
    this.statusCode,
    this.contentType,
  });

  final Uri? streamUri;
  final bool isPlayable;
  final String reason;
  final int? statusCode;
  final String? contentType;
}

final class RadioBrowserStationSearchPage {
  const RadioBrowserStationSearchPage({
    required this.stations,
    required this.tracks,
    required this.nextOffset,
    required this.hasMore,
  });

  final List<RadioBrowserStation> stations;
  final List<Track> tracks;
  final int nextOffset;
  final bool hasMore;
}

class RadioBrowserProvider implements MusicSourceSearchPagingProvider {
  RadioBrowserProvider({
    Uri? baseUri,
    Uri? mirrorDirectoryUri,
    RadioBrowserMirrorLoader? mirrorLoader,
    RadioBrowserSearchLoader? searchLoader,
    RadioBrowserClickLoader? clickLoader,
    RadioBrowserStreamValidator? streamValidator,
    this.limit = 20,
  })  : _baseUri = baseUri ?? defaultRadioBrowserBaseUri,
        _mirrorDirectoryUri =
            mirrorDirectoryUri ?? defaultRadioBrowserMirrorDirectoryUri,
        _mirrorLoader = mirrorLoader ?? _loadRadioBrowserMirrors,
        _searchLoader = searchLoader ?? _loadRadioBrowserSearch,
        _clickLoader = clickLoader ?? _loadRadioBrowserClick,
        _streamValidator = streamValidator ?? _validateRadioBrowserStream,
        _discoversMirrors = baseUri == null;

  Uri _baseUri;
  final Uri _mirrorDirectoryUri;
  final int limit;
  final RadioBrowserMirrorLoader _mirrorLoader;
  final RadioBrowserSearchLoader _searchLoader;
  final RadioBrowserClickLoader _clickLoader;
  final RadioBrowserStreamValidator _streamValidator;
  final bool _discoversMirrors;
  Future<Uri>? _mirrorDiscovery;

  Uri get baseUri => _baseUri;

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
        networkDomains: <String>{
          if (_discoversMirrors && _mirrorDirectoryUri.host.isNotEmpty)
            _mirrorDirectoryUri.host,
          if (baseUri.host.isNotEmpty) baseUri.host,
        }.toList(growable: false),
        dataSent: <String>[
          if (_discoversMirrors) 'mirror discovery request',
          'station search query',
          'station click UUID',
          'station stream validation request',
        ],
      );

  @override
  Future<List<Track>> search(String query) async {
    return searchStations(query);
  }

  Future<List<Track>> searchStations(
    String query, {
    RadioBrowserSearchFilters filters = const RadioBrowserSearchFilters(),
  }) async {
    final page = await searchStationPage(query, filters: filters);
    return page.tracks;
  }

  @override
  Future<MusicSourceSearchPage> searchPage(
    String query, {
    String? cursor,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final offset = _radioSearchOffset(cursor);
    final page = await searchStationPage(
      query,
      offset: offset,
      pageSize: limit.clamp(1, 500),
    );
    return MusicSourceSearchPage(
      tracks: List<Track>.unmodifiable(page.tracks),
      nextCursor: page.hasMore ? page.nextOffset.toString() : null,
    );
  }

  Future<RadioBrowserStationSearchPage> searchStationPage(
    String query, {
    RadioBrowserSearchFilters filters = const RadioBrowserSearchFilters(),
    int offset = 0,
    int? pageSize,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'must not be negative');
    }
    final effectiveLimit = pageSize ?? limit;
    if (effectiveLimit <= 0) {
      throw ArgumentError.value(
        effectiveLimit,
        'pageSize',
        'must be positive',
      );
    }

    final normalized = query.trim();
    final baseUri = await _resolvedBaseUri();
    final response = await _searchLoader(
      _searchUri(
        baseUri,
        normalized,
        filters,
        offset,
        effectiveLimit,
      ),
    );
    final returnedStationCount = _radioBrowserResponseCount(response);
    final stations = parseRadioBrowserStations(response);

    final matchingStations = stations
        .where(
          (station) =>
              station.matches(normalized) && station.matchesFilters(filters),
        )
        .toList(growable: false);

    return RadioBrowserStationSearchPage(
      stations: matchingStations,
      tracks: matchingStations
          .map((station) => station.toTrack(sourceId: id))
          .toList(growable: false),
      nextOffset: offset + returnedStationCount,
      hasMore: returnedStationCount >= effectiveLimit,
    );
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    if (track.sourceId != id || track.streamUrl == null) {
      return null;
    }

    return Uri.tryParse(track.streamUrl!);
  }

  Future<RadioBrowserStreamValidation> validateStream(Track track) async {
    final streamUri = await resolveStream(track);
    if (track.sourceId != id) {
      return const RadioBrowserStreamValidation(
        streamUri: null,
        isPlayable: false,
        reason: 'Track is not from Radio Browser.',
      );
    }
    if (streamUri == null) {
      return const RadioBrowserStreamValidation(
        streamUri: null,
        isPlayable: false,
        reason: 'Station does not have a usable stream URL.',
      );
    }

    return _streamValidator(streamUri);
  }

  Future<void> recordStationClick(Track track) async {
    final stationUuid = track.externalId;
    if (track.sourceId != id || stationUuid == null || stationUuid.isEmpty) {
      return;
    }

    await _clickLoader(_clickUri(await _resolvedBaseUri(), stationUuid));
  }

  Future<Uri> _resolvedBaseUri() {
    if (!_discoversMirrors) {
      return Future<Uri>.value(_baseUri);
    }

    return _mirrorDiscovery ??= _discoverBaseUri();
  }

  Future<Uri> _discoverBaseUri() async {
    try {
      final mirrors = parseRadioBrowserMirrors(
        await _mirrorLoader(_mirrorDirectoryUri),
      );
      _baseUri = selectRadioBrowserMirror(mirrors, fallback: _baseUri);
    } catch (_) {
      // Keep the bundled default mirror when discovery is unavailable.
    }

    return _baseUri;
  }

  Uri _searchUri(
    Uri baseUri,
    String query,
    RadioBrowserSearchFilters filters,
    int offset,
    int pageSize,
  ) {
    final countryCode = _nonEmpty(filters.countryCode)?.toUpperCase();
    final language = _nonEmpty(filters.language);
    final tag = _nonEmpty(filters.tag);
    final codec = _nonEmpty(filters.codec)?.toUpperCase();
    final minBitrateKbps = filters.minBitrateKbps;
    final maxBitrateKbps = filters.maxBitrateKbps;

    return baseUri.replace(
      path: _joinUriPath(baseUri.path, '/json/stations/search'),
      queryParameters: <String, String>{
        if (query.isNotEmpty) 'name': query,
        if (countryCode != null) 'countrycode': countryCode,
        if (language != null) 'language': language,
        if (tag != null) 'tag': tag,
        if (codec != null) 'codec': codec,
        if (minBitrateKbps != null && minBitrateKbps > 0)
          'bitrateMin': minBitrateKbps.toString(),
        if (maxBitrateKbps != null && maxBitrateKbps > 0)
          'bitrateMax': maxBitrateKbps.toString(),
        'hidebroken': 'true',
        'limit': pageSize.toString(),
        'offset': offset.toString(),
        'order': 'clickcount',
        'reverse': 'true',
      },
    );
  }

  Uri _clickUri(Uri baseUri, String stationUuid) {
    return baseUri.replace(
      path: _joinUriPath(
        baseUri.path,
        '/json/url/${Uri.encodeComponent(stationUuid)}',
      ),
      queryParameters: const <String, String>{},
    );
  }
}

int _radioSearchOffset(String? cursor) {
  if (cursor == null) {
    return 0;
  }
  final offset = int.tryParse(cursor);
  if (offset == null || offset < 0) {
    throw ArgumentError.value(cursor, 'cursor', 'Invalid search cursor.');
  }
  return offset;
}

int _radioBrowserResponseCount(String jsonText) {
  final decoded = jsonDecode(jsonText);
  return decoded is List<dynamic> ? decoded.length : 0;
}

List<Uri> parseRadioBrowserMirrors(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! List<dynamic>) {
    throw const FormatException('Radio Browser mirror response must be a list.');
  }

  return decoded
      .map(_mirrorUriFromJson)
      .whereType<Uri>()
      .toList(growable: false);
}

Uri selectRadioBrowserMirror(
  List<Uri> mirrors, {
  required Uri fallback,
}) {
  if (mirrors.isEmpty) {
    return fallback;
  }

  return mirrors.firstWhere(
    (uri) => uri.scheme == 'https',
    orElse: () => mirrors.first,
  );
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

  bool matchesFilters(RadioBrowserSearchFilters filters) {
    final normalizedCountryCode = filters.countryCode.trim().toLowerCase();
    if (normalizedCountryCode.isNotEmpty &&
        countryCode.toLowerCase() != normalizedCountryCode) {
      return false;
    }

    final normalizedLanguage = filters.language.trim().toLowerCase();
    if (normalizedLanguage.isNotEmpty &&
        !language.toLowerCase().contains(normalizedLanguage)) {
      return false;
    }

    final normalizedTag = filters.tag.trim().toLowerCase();
    if (normalizedTag.isNotEmpty &&
        !tags.any((tag) => tag.toLowerCase().contains(normalizedTag))) {
      return false;
    }

    final normalizedCodec = filters.codec.trim().toLowerCase();
    if (normalizedCodec.isNotEmpty &&
        codec.toLowerCase() != normalizedCodec) {
      return false;
    }

    final minBitrate = filters.minBitrateKbps;
    if (minBitrate != null && bitrateKbps < minBitrate) {
      return false;
    }

    final maxBitrate = filters.maxBitrateKbps;
    if (maxBitrate != null && bitrateKbps > maxBitrate) {
      return false;
    }

    return true;
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
      externalId: stationUuid,
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

Future<String> _loadRadioBrowserClick(Uri clickUri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(clickUri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Radio Browser click failed with HTTP ${response.statusCode}.',
        uri: clickUri,
      );
    }

    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}

Future<String> _loadRadioBrowserMirrors(Uri mirrorsUri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(mirrorsUri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Radio Browser mirror discovery failed with HTTP '
        '${response.statusCode}.',
        uri: mirrorsUri,
      );
    }

    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}

Future<RadioBrowserStreamValidation> _validateRadioBrowserStream(
  Uri streamUri,
) async {
  if (streamUri.scheme != 'http' && streamUri.scheme != 'https') {
    return RadioBrowserStreamValidation(
      streamUri: streamUri,
      isPlayable: false,
      reason: 'Unsupported stream URL scheme: ${streamUri.scheme}.',
    );
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(streamUri);
    request.headers.set(HttpHeaders.acceptHeader, 'audio/*,*/*;q=0.8');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    request.headers.set('Icy-MetaData', '1');
    final response = await request.close();
    final contentType = response.headers.contentType?.mimeType ??
        response.headers.value(HttpHeaders.contentTypeHeader);
    if (response.statusCode < 200 || response.statusCode >= 400) {
      return RadioBrowserStreamValidation(
        streamUri: streamUri,
        isPlayable: false,
        statusCode: response.statusCode,
        contentType: contentType,
        reason: 'Stream returned HTTP ${response.statusCode}.',
      );
    }
    if (!_looksLikeRadioStreamContentType(contentType)) {
      return RadioBrowserStreamValidation(
        streamUri: streamUri,
        isPlayable: false,
        statusCode: response.statusCode,
        contentType: contentType,
        reason: 'Stream content type is not audio: $contentType.',
      );
    }

    return RadioBrowserStreamValidation(
      streamUri: streamUri,
      isPlayable: true,
      statusCode: response.statusCode,
      contentType: contentType,
      reason: contentType == null || contentType.trim().isEmpty
          ? 'Stream responded successfully.'
          : 'Stream responded as $contentType.',
    );
  } on Object catch (error) {
    return RadioBrowserStreamValidation(
      streamUri: streamUri,
      isPlayable: false,
      reason: 'Stream validation failed: $error',
    );
  } finally {
    client.close(force: true);
  }
}

bool _looksLikeRadioStreamContentType(String? contentType) {
  final normalized = contentType?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return true;
  }
  if (normalized.startsWith('audio/')) {
    return true;
  }

  return normalized == 'application/ogg' ||
      normalized == 'application/octet-stream' ||
      normalized == 'binary/octet-stream' ||
      normalized.contains('mpegurl') ||
      normalized.contains('shoutcast');
}

Uri? _mirrorUriFromJson(Object? value) {
  if (value is String) {
    return _mirrorUriValue(value);
  }

  if (value is Map<dynamic, dynamic>) {
    final json = value.cast<String, Object?>();
    final url = _stringValue(json['url']);
    final name = _stringValue(json['name']);
    final host = _stringValue(json['host']);
    return _mirrorUriValue(
      url.isNotEmpty
          ? url
          : name.isNotEmpty
              ? name
              : host,
    );
  }

  return null;
}

Uri? _mirrorUriValue(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized.contains(RegExp(r'\s'))) {
    return null;
  }

  final candidate = normalized.contains('://')
      ? Uri.tryParse(normalized)
      : Uri.tryParse('https://$normalized');
  if (candidate == null || candidate.host.isEmpty) {
    return null;
  }

  final scheme = candidate.scheme.isEmpty ? 'https' : candidate.scheme;
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }

  final host = candidate.hasPort
      ? '${candidate.host}:${candidate.port}'
      : candidate.host;
  return Uri.parse('$scheme://$host');
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

String? _nonEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
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
