import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef JamendoResponseLoader = Future<String> Function(Uri uri);

/// Official Jamendo read API adapter using a client ID supplied by the user.
///
/// Stream URLs are returned only for playback. The adapter deliberately does
/// not declare offline caching or downloads: Jamendo grants download rights per
/// track, while the common offline policy is provider-wide.
final class JamendoProvider
    implements
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  JamendoProvider({
    required String clientId,
    Uri? tracksUri,
    Uri? streamUri,
    JamendoResponseLoader? loader,
  }) : _clientId = _requireClientId(clientId),
       tracksUri = tracksUri ?? _defaultTracksUri,
       streamUri = streamUri ?? _defaultStreamUri,
       _loader = loader ?? _loadJamendoJson;

  static final Uri _defaultTracksUri = Uri.parse(
    'https://api.jamendo.com/v3.0/tracks/',
  );
  static final Uri _defaultStreamUri = Uri.parse(
    'https://api.jamendo.com/v3.0/tracks/file/',
  );

  final String _clientId;
  final Uri tracksUri;
  final Uri streamUri;
  final JamendoResponseLoader _loader;

  @override
  String get id => 'jamendo';

  @override
  String get name => 'Jamendo';

  @override
  String get description =>
      'Official Jamendo music search and direct stream playback using your '
      'Jamendo developer client ID.';

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
    networkDomains: <String>[
      'api.jamendo.com',
      'usercontent.jamendo.com',
      '*.storage.jamendo.com',
    ],
    dataSent: <String>[
      'search query and pagination offset',
      'user-configured Jamendo developer client ID',
    ],
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
    final tracks = parseJamendoTracksResponse(
      await _loader(
        _tracksRequestUri(
          query: normalizedQuery,
          offset: offset,
          limit: requestedLimit,
        ),
      ),
    );
    return MusicSourceSearchPage(
      tracks: tracks,
      nextCursor: tracks.length == requestedLimit
          ? (offset + tracks.length).toString()
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
          subtitle: track.artist.trim().isEmpty ? null : track.artist,
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
    final direct = _safeHttpsUri(track.streamUrl);
    if (direct != null) {
      return direct;
    }
    final trackId = track.externalId?.trim() ?? '';
    if (!RegExp(r'^\d+$').hasMatch(trackId)) {
      return null;
    }
    return streamUri.replace(
      queryParameters: <String, String>{
        'client_id': _clientId,
        'id': trackId,
        'action': 'stream',
        'audioformat': 'mp32',
      },
    );
  }

  Uri _tracksRequestUri({
    required String query,
    required int offset,
    required int limit,
  }) {
    return tracksUri.replace(
      queryParameters: <String, String>{
        'client_id': _clientId,
        'format': 'json',
        'search': query,
        'offset': offset.toString(),
        'limit': limit.toString(),
        'type': 'single albumtrack',
        'audioformat': 'mp32',
        'imagesize': '300',
      },
    );
  }
}

List<Track> parseJamendoTracksResponse(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Jamendo response must be an object.');
  }
  final response = decoded.cast<String, Object?>();
  final headers = response['headers'];
  if (headers is! Map<dynamic, dynamic>) {
    throw const FormatException('Jamendo response is missing headers.');
  }
  final headerMap = headers.cast<String, Object?>();
  final status = _stringValue(headerMap['status']).toLowerCase();
  final code = _integerValue(headerMap['code']);
  if (status != 'success' || (code != null && code != 0)) {
    final message = _stringValue(headerMap['error_message']);
    throw FormatException(
      message.isEmpty ? 'Jamendo request was not successful.' : message,
    );
  }
  final results = response['results'];
  if (results is! List<dynamic>) {
    throw const FormatException('Jamendo response is missing results.');
  }

  final tracks = <Track>[];
  final seen = <String>{};
  for (final raw in results.whereType<Map<dynamic, dynamic>>()) {
    final value = raw.cast<String, Object?>();
    final externalId = _stringValue(value['id']);
    final title = _stringValue(value['name']);
    if (!RegExp(r'^\d+$').hasMatch(externalId) ||
        title.isEmpty ||
        !seen.add(externalId)) {
      continue;
    }
    final durationSeconds = _integerValue(value['duration']) ?? 0;
    final artwork =
        _safeHttpsUri(_stringValue(value['image'])) ??
        _safeHttpsUri(_stringValue(value['album_image']));
    tracks.add(
      Track(
        id: 'jamendo:$externalId',
        title: title,
        artist: _stringValue(value['artist_name']).isEmpty
            ? 'Unknown Artist'
            : _stringValue(value['artist_name']),
        album: _stringValue(value['album_name']).isEmpty
            ? 'Single'
            : _stringValue(value['album_name']),
        duration: Duration(seconds: durationSeconds < 0 ? 0 : durationSeconds),
        artworkUri: artwork,
        artworkSourceUri: artwork,
        streamUrl: _safeHttpsUri(_stringValue(value['audio']))?.toString(),
        sourceId: 'jamendo',
        externalId: externalId,
      ),
    );
  }
  return List<Track>.unmodifiable(tracks);
}

int _parseOffset(String? cursor) {
  final normalized = cursor?.trim();
  if (normalized == null || normalized.isEmpty) {
    return 0;
  }
  final value = int.tryParse(normalized);
  if (value == null || value < 0) {
    throw ArgumentError.value(cursor, 'cursor', 'Must be a non-negative offset.');
  }
  return value;
}

String _requireClientId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > 256) {
    throw ArgumentError.value(value, 'clientId', 'Must be 1-256 characters.');
  }
  if (normalized.contains(RegExp(r'[\r\n]'))) {
    throw ArgumentError.value(value, 'clientId', 'Must not contain line breaks.');
  }
  return normalized;
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

Future<String> _loadJamendoJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const HttpException('Jamendo request failed.');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
