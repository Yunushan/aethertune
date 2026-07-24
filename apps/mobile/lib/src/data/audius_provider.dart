import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/music_catalog_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/track.dart';
import 'provider_binary_loader.dart';

typedef AudiusResponseLoader = Future<String> Function(Uri uri);
typedef AudiusBinaryLoader = Future<Uint8List> Function(
  Uri uri,
  Map<String, String> headers,
);

/// Read-only public Audius adapter for search and stream resolution.
///
/// Gated and unlisted tracks are excluded. The provider does not advertise
/// offline caching or downloads because public search metadata alone is not a
/// durable per-track license grant.
final class AudiusProvider
    implements
        MusicCatalogPagingProvider,
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  AudiusProvider({
    Uri? searchUri,
    Uri? trendingUri,
    Uri? trendingPlaylistsUri,
    Uri? playlistsBaseUri,
    Uri? streamBaseUri,
    AudiusResponseLoader? loader,
    AudiusBinaryLoader? artworkLoader,
  }) : searchUri = searchUri ?? _defaultSearchUri,
       trendingUri = trendingUri ?? _defaultTrendingUri,
       trendingPlaylistsUri =
           trendingPlaylistsUri ?? _defaultTrendingPlaylistsUri,
       playlistsBaseUri = playlistsBaseUri ?? _defaultPlaylistsBaseUri,
       streamBaseUri = streamBaseUri ?? _defaultStreamBaseUri,
       _loader = loader ?? _loadAudiusJson,
       _artworkLoader = artworkLoader ?? loadProviderImageBytes;

  static final Uri _defaultSearchUri = Uri.parse(
    'https://api.audius.co/v1/tracks/search',
  );
  static final Uri _defaultStreamBaseUri = Uri.parse(
    'https://api.audius.co/v1/tracks/',
  );
  static final Uri _defaultTrendingUri = Uri.parse(
    'https://api.audius.co/v1/tracks/trending',
  );
  static final Uri _defaultTrendingPlaylistsUri = Uri.parse(
    'https://api.audius.co/v1/playlists/trending',
  );
  static final Uri _defaultPlaylistsBaseUri = Uri.parse(
    'https://api.audius.co/v1/playlists/',
  );

  final Uri searchUri;
  final Uri trendingUri;
  final Uri trendingPlaylistsUri;
  final Uri playlistsBaseUri;
  final Uri streamBaseUri;
  final AudiusResponseLoader _loader;
  final AudiusBinaryLoader _artworkLoader;

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
        MusicSourceCapability.libraryBrowse,
        MusicSourceCapability.playlists,
        MusicSourceCapability.artwork,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
    networkDomains: <String>['api.audius.co'],
    dataSent: <String>[
      'search query and pagination offset',
      'public trending album or playlist pagination',
      'public album or playlist identifier',
      'public artwork URL',
    ],
  );

  @override
  Set<MusicCatalogCollectionKind> get pagedCollectionKinds =>
      const <MusicCatalogCollectionKind>{
        MusicCatalogCollectionKind.album,
        MusicCatalogCollectionKind.playlist,
      };

  @override
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  ) async {
    if (!pagedCollectionKinds.contains(kind)) {
      return const <MusicCatalogCollection>[];
    }
    return (await browseCollectionsPage(kind)).collections;
  }

  /// Returns a bounded public, server-ordered Audius collection page.
  ///
  /// Audius exposes albums through the playlist API with `is_album` set. This
  /// keeps album and playlist browsing on the documented public endpoint.
  @override
  Future<MusicCatalogCollectionPage> browseCollectionsPage(
    MusicCatalogCollectionKind kind, {
    int offset = 0,
    int limit = 100,
  }) async {
    if (!pagedCollectionKinds.contains(kind)) {
      throw UnsupportedError('Audius does not expose public $kind browsing.');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final requestedLimit = limit.clamp(1, 50);
    final response = _parseAudiusCollectionsResponse(
      await _loader(
        trendingPlaylistsUri.replace(
          queryParameters: <String, String>{
            'offset': offset.toString(),
            'limit': requestedLimit.toString(),
          },
        ),
      ),
      kind,
    );
    final canContinue = response.resultCount == requestedLimit;
    return MusicCatalogCollectionPage(
      collections: response.collections,
      nextOffset: canContinue ? offset + response.resultCount : offset,
      hasMore: canContinue,
    );
  }

  @override
  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  ) async {
    if (!pagedCollectionKinds.contains(collection.kind)) {
      throw UnsupportedError('Audius collection type is not supported.');
    }
    final collectionId = collection.id.trim();
    if (!_isAudiusId(collectionId)) {
      throw ArgumentError.value(collection.id, 'collection.id', 'Is invalid.');
    }
    final basePath = playlistsBaseUri.path.endsWith('/')
        ? playlistsBaseUri.path
        : '${playlistsBaseUri.path}/';
    final response = _parseAudiusTracksResponse(
      await _loader(
        playlistsBaseUri.replace(
          path: '$basePath${Uri.encodeComponent(collectionId)}/tracks',
          queryParameters: const <String, String>{'limit': '100'},
        ),
      ),
    );
    return MusicCatalogDetail(
      collection: collection,
      tracks: List<Track>.unmodifiable(
        response.tracks
            .map((track) => track.copyWith(album: collection.title))
            .toList(growable: false),
      ),
    );
  }

  @override
  Future<Uint8List?> loadArtwork(
    String artworkId, {
    String? version,
    int maxWidth = 512,
  }) async {
    final uri = _safeHttpsUri(artworkId);
    if (uri == null) {
      return null;
    }
    return _artworkLoader(uri, const <String, String>{});
  }

  @override
  Future<List<Track>> search(String query) async {
    return (await searchPage(query)).tracks;
  }

  /// Returns a bounded public trending list in Audius's server-defined order.
  Future<List<Track>> fetchTrending({int limit = 6}) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final requestedLimit = limit.clamp(1, 50);
    return parseAudiusTracksResponse(
      await _loader(
        trendingUri.replace(
          queryParameters: <String, String>{
            'limit': requestedLimit.toString(),
          },
        ),
      ),
    );
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

final class _AudiusCollectionsResponse {
  const _AudiusCollectionsResponse({
    required this.collections,
    required this.resultCount,
  });

  final List<MusicCatalogCollection> collections;
  final int resultCount;
}

_AudiusCollectionsResponse _parseAudiusCollectionsResponse(
  String jsonText,
  MusicCatalogCollectionKind requestedKind,
) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Audius response must be an object.');
  }
  final data = decoded.cast<String, Object?>()['data'];
  if (data is! List<dynamic>) {
    throw const FormatException('Audius response is missing collection data.');
  }

  final collections = <MusicCatalogCollection>[];
  final seen = <String>{};
  for (final raw in data.whereType<Map<dynamic, dynamic>>()) {
    final value = raw.cast<String, Object?>();
    final id = _stringValue(value['id']);
    final isAlbum = value['is_album'] == true;
    final kind = isAlbum
        ? MusicCatalogCollectionKind.album
        : MusicCatalogCollectionKind.playlist;
    final title = _firstNonEmpty(<String>[
      _stringValue(value['playlist_name']),
      _stringValue(value['name']),
    ]);
    if (kind != requestedKind ||
        !_isPublicCollection(value) ||
        !_isAudiusId(id) ||
        title.isEmpty ||
        !seen.add(id)) {
      continue;
    }
    final user = value['user'];
    final userData = user is Map<dynamic, dynamic>
        ? user.cast<String, Object?>()
        : const <String, Object?>{};
    final owner = _firstNonEmpty(<String>[
      _stringValue(userData['name']),
      _stringValue(userData['handle']),
    ]);
    final contents = value['playlist_contents'];
    final itemCount = contents is List<dynamic>
        ? contents.length
        : _integerValue(value['track_count']) ?? 0;
    final artwork = _artworkUri(value['artwork']);
    collections.add(
      MusicCatalogCollection(
        id: id,
        title: title,
        kind: kind,
        subtitle: owner,
        itemCount: itemCount < 0 ? 0 : itemCount,
        artworkId: artwork?.toString(),
      ),
    );
  }
  return _AudiusCollectionsResponse(
    collections: List<MusicCatalogCollection>.unmodifiable(collections),
    resultCount: data.length,
  );
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

bool _isPublicCollection(Map<String, Object?> value) {
  return value['is_private'] != true && value['is_unlisted'] != true;
}

bool _isAudiusId(String value) {
  return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);
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
