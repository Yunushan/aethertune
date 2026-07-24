import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef AudiusResponseLoader = Future<String> Function(Uri uri);

/// Read-only public Audius adapter for search and stream resolution.
///
/// Gated and unlisted tracks are excluded. The provider does not advertise
/// offline caching or downloads because public search metadata alone is not a
/// durable per-track license grant.
final class AudiusProvider
    implements
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  AudiusProvider({
    Uri? searchUri,
    Uri? streamBaseUri,
    AudiusResponseLoader? loader,
  }) : searchUri = searchUri ?? _defaultSearchUri,
       streamBaseUri = streamBaseUri ?? _defaultStreamBaseUri,
       _loader = loader ?? _loadAudiusJson;

  static final Uri _defaultSearchUri = Uri.parse(
    'https://api.audius.co/v1/tracks/search',
  );
  static final Uri _defaultStreamBaseUri = Uri.parse(
    'https://api.audius.co/v1/tracks/',
  );

  final Uri searchUri;
  final Uri streamBaseUri;
  final AudiusResponseLoader _loader;

  @override
  String get id => 'audius';

  @override
  String get name => 'Audius';

  @override
  String get description =>
      'Public Audius catalog search and direct stream playback through the '
      'Open Audio Protocol.';

  @override
  Set<MusicSourceCapability> get capabilities =>
      const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.searchSuggestions,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.directPlayback,
        MusicSourceCapability.artwork,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
    networkDomains: <String>['api.audius.co'],
    dataSent: <String>['search query and pagination offset'],
  );

  @override
  Future<List<Track>> search(String query) async {
    return (await searchPage(query)).tracks;
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
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const MusicSourceSearchPage(tracks: <Track>[]);
    }
    final offset = _parseOffset(cursor);
    final requestedLimit = limit.clamp(1, 50);
    final response = _parseAudiusTracksResponse(
      await _loader(
        searchUri.replace(
          queryParameters: <String, String>{
            'query': normalizedQuery,
            'offset': offset.toString(),
            'limit': requestedLimit.toString(),
          },
        ),
      ),
    );
    return MusicSourceSearchPage(
      tracks: response.tracks,
      nextCursor: response.resultCount == requestedLimit
          ? (offset + response.resultCount).toString()
          : null,
    );
  }

  @override
  Future<List<MusicSourceSearchSuggestion>> suggest(
    String query, {
    int limit = 8,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final page = await searchPage(query, limit: limit.clamp(1, 10));
    final seen = <String>{};
    final suggestions = <MusicSourceSearchSuggestion>[];
    for (final track in page.tracks) {
      final value = track.title.trim();
      if (value.isEmpty || !seen.add(value.toLowerCase())) {
        continue;
      }
      suggestions.add(
        MusicSourceSearchSuggestion(
          value: value,
          kind: MusicSourceSearchSuggestionKind.track,
          subtitle: track.artist == 'Unknown Artist' ? null : track.artist,
        ),
      );
      if (suggestions.length == limit) {
        break;
      }
    }
    return List<MusicSourceSearchSuggestion>.unmodifiable(suggestions);
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    if (track.sourceId != id) {
      return null;
    }
    final externalId = track.externalId?.trim() ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(externalId)) {
      return null;
    }
    final basePath = streamBaseUri.path.endsWith('/')
        ? streamBaseUri.path
        : '${streamBaseUri.path}/';
    return streamBaseUri.replace(
      path: '$basePath${Uri.encodeComponent(externalId)}/stream',
    );
  }
}

List<Track> parseAudiusTracksResponse(String jsonText) {
  return _parseAudiusTracksResponse(jsonText).tracks;
}

final class _AudiusTracksResponse {
  const _AudiusTracksResponse({
    required this.tracks,
    required this.resultCount,
  });

  final List<Track> tracks;
  final int resultCount;
}

_AudiusTracksResponse _parseAudiusTracksResponse(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Audius response must be an object.');
  }
  final data = decoded.cast<String, Object?>()['data'];
  if (data is! List<dynamic>) {
    throw const FormatException('Audius response is missing track data.');
  }

  final tracks = <Track>[];
  final seen = <String>{};
  for (final raw in data.whereType<Map<dynamic, dynamic>>()) {
    final value = raw.cast<String, Object?>();
    final externalId = _stringValue(value['id']);
    final title = _stringValue(value['title']);
    if (!_isPublicTrack(value) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(externalId) ||
        title.isEmpty ||
        !seen.add(externalId)) {
      continue;
    }
    final user = value['user'];
    final userData = user is Map<dynamic, dynamic>
        ? user.cast<String, Object?>()
        : const <String, Object?>{};
    final artist = _firstNonEmpty(<String>[
      _stringValue(userData['name']),
      _stringValue(userData['handle']),
    ]);
    final artwork = _artworkUri(value['artwork']);
    final durationSeconds = _integerValue(value['duration']) ?? 0;
    tracks.add(
      Track(
        id: 'audius:$externalId',
        title: title,
        artist: artist.isEmpty ? 'Unknown Artist' : artist,
        album: 'Single',
        genre: _stringValue(value['genre']).isEmpty
            ? 'Unknown Genre'
            : _stringValue(value['genre']),
        duration: Duration(seconds: durationSeconds < 0 ? 0 : durationSeconds),
        artworkUri: artwork,
        artworkSourceUri: artwork,
        sourceId: 'audius',
        externalId: externalId,
      ),
    );
  }
  return _AudiusTracksResponse(
    tracks: List<Track>.unmodifiable(tracks),
    resultCount: data.length,
  );
}

bool _isPublicTrack(Map<String, Object?> value) {
  return value['is_stream_gated'] != true && value['is_unlisted'] != true;
}

Uri? _artworkUri(Object? value) {
  if (value is! Map<dynamic, dynamic>) {
    return null;
  }
  final artwork = value.cast<String, Object?>();
  for (final key in <String>['480x480', '1000x1000', '150x150']) {
    final uri = _safeHttpsUri(_stringValue(artwork[key]));
    if (uri != null) {
      return uri;
    }
  }
  for (final item in artwork.values) {
    final uri = _safeHttpsUri(_stringValue(item));
    if (uri != null) {
      return uri;
    }
  }
  return null;
}

int _parseOffset(String? cursor) {
  final normalized = cursor?.trim();
  if (normalized == null || normalized.isEmpty) {
    return 0;
  }
  final value = int.tryParse(normalized);
  if (value == null || value < 0) {
    throw ArgumentError.value(
      cursor,
      'cursor',
      'Must be a non-negative offset.',
    );
  }
  return value;
}

String _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _stringValue(Object? value) => value?.toString().trim() ?? '';

int? _integerValue(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(_stringValue(value));
}

Uri? _safeHttpsUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Future<String> _loadAudiusJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const HttpException('Audius request failed.');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
