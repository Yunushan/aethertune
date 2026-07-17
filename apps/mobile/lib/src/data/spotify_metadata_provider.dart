import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef SpotifyAccessTokenReader = Future<String> Function();
typedef SpotifySearchLoader = Future<String> Function(Uri uri, String token);

/// Official Spotify Web API metadata search. It has no playback surface.
final class SpotifyMetadataProvider
    implements
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  SpotifyMetadataProvider({
    required SpotifyAccessTokenReader accessTokenReader,
    Uri? searchUri,
    SpotifySearchLoader? searchLoader,
    Uri? savedTracksUri,
    SpotifySearchLoader? savedTracksLoader,
  }) : _accessTokenReader = accessTokenReader,
       searchUri = searchUri ?? _defaultSearchUri,
       _searchLoader = searchLoader ?? _loadSpotifyJson,
       savedTracksUri = savedTracksUri ?? _defaultSavedTracksUri,
       _savedTracksLoader = savedTracksLoader ?? _loadSpotifyJson;

  static final Uri _defaultSearchUri =
      Uri.parse('https://api.spotify.com/v1/search');
  static final Uri _defaultSavedTracksUri =
      Uri.parse('https://api.spotify.com/v1/me/tracks');

  final SpotifyAccessTokenReader _accessTokenReader;
  final Uri searchUri;
  final SpotifySearchLoader _searchLoader;
  final Uri savedTracksUri;
  final SpotifySearchLoader _savedTracksLoader;

  @override
  String get id => 'spotify-metadata';

  @override
  String get name => 'Spotify Web API';

  @override
  String get description =>
      'Official Spotify metadata search using your authorized account. '
      'Playback, caching, and downloads are not provided.';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
    MusicSourceCapability.metadataSearch,
    MusicSourceCapability.searchSuggestions,
    MusicSourceCapability.artwork,
    MusicSourceCapability.authentication,
  };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
    networkDomains: <String>['accounts.spotify.com', 'api.spotify.com'],
    dataSent: <String>[
      'search query',
      'registered Spotify client ID',
      'OAuth authorization/access tokens',
    ],
    requiresUserCredentials: true,
  );

  @override
  Future<List<Track>> search(String query) async {
    final page = await searchPage(query);
    return page.tracks;
  }

  @override
  Future<List<MusicSourceSearchSuggestion>> suggest(
    String query, {
    int limit = 8,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <MusicSourceSearchSuggestion>[];
    }

    final page = await searchPage(normalizedQuery, limit: limit.clamp(1, 50));
    final seen = <String>{};
    final suggestions = <MusicSourceSearchSuggestion>[];
    for (final track in page.tracks) {
      final value = track.title.trim();
      if (value.isEmpty || !seen.add(value.toLowerCase())) {
        continue;
      }
      final subtitleParts = <String>[track.artist, track.album]
          .where((part) => part.trim().isNotEmpty)
          .toList(growable: false);
      suggestions.add(
        MusicSourceSearchSuggestion(
          value: value,
          kind: MusicSourceSearchSuggestionKind.track,
          subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' - '),
        ),
      );
      if (suggestions.length == limit) {
        break;
      }
    }
    return List<MusicSourceSearchSuggestion>.unmodifiable(suggestions);
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
    final boundedLimit = limit.clamp(1, 50);
    final token = await _accessTokenReader();
    final page = parseSpotifySearchPage(
      await _searchLoader(
        searchUri.replace(
          queryParameters: <String, String>{
            'q': normalizedQuery,
            'type': 'track',
            'limit': boundedLimit.toString(),
            'offset': offset.toString(),
          },
        ),
        token,
      ),
    );
    final nextOffset = page.offset + page.tracks.length;
    return MusicSourceSearchPage(
      tracks: page.tracks,
      totalCount: page.total,
      nextCursor: nextOffset < page.total ? nextOffset.toString() : null,
    );
  }

  /// Reads the user's official Spotify library as catalog metadata only.
  /// Returned tracks intentionally do not contain a stream URL.
  Future<SpotifySavedTracksPage> loadSavedTracksPage({
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final boundedLimit = limit.clamp(1, 50);
    final token = await _accessTokenReader();
    return parseSpotifySavedTracksPage(
      await _savedTracksLoader(
        savedTracksUri.replace(
          queryParameters: <String, String>{
            'limit': boundedLimit.toString(),
            'offset': offset.toString(),
          },
        ),
        token,
      ),
    );
  }

  @override
  Future<Uri?> resolveStream(Track track) async => null;
}

final class SpotifySearchPage {
  const SpotifySearchPage({
    required this.tracks,
    required this.offset,
    required this.total,
  });

  final List<Track> tracks;
  final int offset;
  final int total;
}

final class SpotifySavedTracksPage {
  const SpotifySavedTracksPage({
    required this.tracks,
    required this.offset,
    required this.total,
    required this.hasMore,
  });

  final List<Track> tracks;
  final int offset;
  final int total;
  final bool hasMore;
}

SpotifySearchPage parseSpotifySearchPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify search response must be a map.');
  }
  final root = Map<String, Object?>.from(decoded);
  final tracksValue = root['tracks'];
  if (tracksValue is! Map) {
    throw const FormatException('Spotify search response is missing tracks.');
  }
  final tracksJson = Map<String, Object?>.from(tracksValue);
  final items = tracksJson['items'];
  return SpotifySearchPage(
    tracks: items is List
        ? items
              .whereType<Map>()
              .map((item) => _trackFromSpotifyJson(Map<String, Object?>.from(item)))
              .whereType<Track>()
              .toList(growable: false)
        : const <Track>[],
    offset: _nonNegativeInt(tracksJson['offset']) ?? 0,
    total: _nonNegativeInt(tracksJson['total']) ?? 0,
  );
}

SpotifySavedTracksPage parseSpotifySavedTracksPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify saved tracks response must be a map.');
  }
  final root = Map<String, Object?>.from(decoded);
  final items = root['items'];
  final tracks = items is List
      ? items
            .whereType<Map>()
            .map((item) {
              final savedItem = Map<String, Object?>.from(item);
              final track = savedItem['track'];
              if (track is! Map) {
                return null;
              }
              return _trackFromSpotifyJson(
                Map<String, Object?>.from(track),
                addedAt: DateTime.tryParse(
                  savedItem['added_at']?.toString() ?? '',
                )?.toUtc(),
              );
            })
            .whereType<Track>()
            .toList(growable: false)
      : const <Track>[];
  final offset = _nonNegativeInt(root['offset']) ?? 0;
  final total = _nonNegativeInt(root['total']) ?? 0;
  final hasNextPage = _nonEmpty(root['next']) != null;
  return SpotifySavedTracksPage(
    tracks: tracks,
    offset: offset,
    total: total,
    hasMore: hasNextPage || offset + tracks.length < total,
  );
}

Track? _trackFromSpotifyJson(
  Map<String, Object?> json, {
  DateTime? addedAt,
}) {
  final id = _nonEmpty(json['id']);
  final title = _nonEmpty(json['name']);
  if (id == null || title == null) {
    return null;
  }
  final artists = json['artists'];
  final artist = artists is List
      ? artists
            .whereType<Map>()
            .map((item) => _nonEmpty(item['name']))
            .whereType<String>()
            .join(', ')
      : '';
  final album = json['album'] is Map
      ? Map<String, Object?>.from(json['album'] as Map)
      : const <String, Object?>{};
  return Track(
    id: Track.stableLocalId('spotify-metadata|$id'),
    title: title,
    artist: artist.isEmpty ? 'Unknown Artist' : artist,
    album: _nonEmpty(album['name']) ?? 'Unknown Album',
    duration: Duration(milliseconds: _nonNegativeInt(json['duration_ms']) ?? 0),
    artworkUri: _spotifyArtworkUri(album['images']),
    sourceId: 'spotify-metadata',
    externalId: id,
    addedAt: addedAt,
  );
}

Uri? _spotifyArtworkUri(Object? images) {
  if (images is! List) {
    return null;
  }
  for (final image in images.whereType<Map>()) {
    final uri = Uri.tryParse(_nonEmpty(image['url']) ?? '');
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
      return uri;
    }
  }
  return null;
}

int _parseOffset(String? cursor) {
  final offset = int.tryParse(cursor?.trim() ?? '');
  if (offset == null || offset < 0) {
    return 0;
  }
  return offset;
}

String? _nonEmpty(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

int? _nonNegativeInt(Object? value) {
  final parsed = switch (value) {
    num number => number.toInt(),
    _ => int.tryParse(value?.toString() ?? ''),
  };
  return parsed == null || parsed < 0 ? null : parsed;
}

Future<String> _loadSpotifyJson(Uri uri, String token) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Spotify Web API request failed with HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}
