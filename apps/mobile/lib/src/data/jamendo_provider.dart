import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/music_catalog_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/track.dart';
import 'provider_binary_loader.dart';

typedef JamendoResponseLoader = Future<String> Function(Uri uri);
typedef JamendoBinaryLoader = Future<Uint8List> Function(
  Uri uri,
  Map<String, String> headers,
);

enum JamendoFeaturedGenre {
  lounge('lounge', 'Lounge'),
  classical('classical', 'Classical'),
  electronic('electronic', 'Electronic'),
  jazz('jazz', 'Jazz'),
  pop('pop', 'Pop'),
  hiphop('hiphop', 'Hip-hop'),
  relaxation('relaxation', 'Relaxation'),
  rock('rock', 'Rock'),
  songwriter('songwriter', 'Songwriter'),
  world('world', 'World'),
  metal('metal', 'Metal'),
  soundtrack('soundtrack', 'Soundtrack');

  const JamendoFeaturedGenre(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// Official Jamendo read API adapter using a client ID supplied by the user.
///
/// Stream URLs are returned only for playback. The adapter deliberately does
/// not declare offline caching or downloads: Jamendo grants download rights per
/// track, while the common offline policy is provider-wide.
final class JamendoProvider
    implements
        MusicCatalogCollectionSearchProvider,
        MusicCatalogPagingProvider,
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  JamendoProvider({
    required String clientId,
    Uri? tracksUri,
    Uri? streamUri,
    Uri? artistsUri,
    Uri? albumsUri,
    Uri? playlistsUri,
    Uri? artistAlbumsUri,
    Uri? artistTracksUri,
    Uri? albumTracksUri,
    Uri? playlistTracksUri,
    JamendoResponseLoader? loader,
    JamendoBinaryLoader? artworkLoader,
  }) : _clientId = _requireClientId(clientId),
       tracksUri = tracksUri ?? _defaultTracksUri,
       streamUri = streamUri ?? _defaultStreamUri,
       artistsUri = artistsUri ?? _defaultArtistsUri,
       albumsUri = albumsUri ?? _defaultAlbumsUri,
       playlistsUri = playlistsUri ?? _defaultPlaylistsUri,
       artistAlbumsUri = artistAlbumsUri ?? _defaultArtistAlbumsUri,
       artistTracksUri = artistTracksUri ?? _defaultArtistTracksUri,
       albumTracksUri = albumTracksUri ?? _defaultAlbumTracksUri,
       playlistTracksUri = playlistTracksUri ?? _defaultPlaylistTracksUri,
       _loader = loader ?? _loadJamendoJson,
       _artworkLoader = artworkLoader ?? loadProviderImageBytes;

  static final Uri _defaultTracksUri = Uri.parse(
    'https://api.jamendo.com/v3.0/tracks/',
  );
  static final Uri _defaultStreamUri = Uri.parse(
    'https://api.jamendo.com/v3.0/tracks/file/',
  );
  static final Uri _defaultArtistsUri = Uri.parse(
    'https://api.jamendo.com/v3.0/artists/',
  );
  static final Uri _defaultAlbumsUri = Uri.parse(
    'https://api.jamendo.com/v3.0/albums/',
  );
  static final Uri _defaultPlaylistsUri = Uri.parse(
    'https://api.jamendo.com/v3.0/playlists/',
  );
  static final Uri _defaultArtistAlbumsUri = Uri.parse(
    'https://api.jamendo.com/v3.0/artists/albums/',
  );
  static final Uri _defaultArtistTracksUri = Uri.parse(
    'https://api.jamendo.com/v3.0/artists/tracks/',
  );
  static final Uri _defaultAlbumTracksUri = Uri.parse(
    'https://api.jamendo.com/v3.0/albums/tracks/',
  );
  static final Uri _defaultPlaylistTracksUri = Uri.parse(
    'https://api.jamendo.com/v3.0/playlists/tracks/',
  );

  final String _clientId;
  final Uri tracksUri;
  final Uri streamUri;
  final Uri artistsUri;
  final Uri albumsUri;
  final Uri playlistsUri;
  final Uri artistAlbumsUri;
  final Uri artistTracksUri;
  final Uri albumTracksUri;
  final Uri playlistTracksUri;
  final JamendoResponseLoader _loader;
  final JamendoBinaryLoader _artworkLoader;

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
        MusicSourceCapability.libraryBrowse,
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
      'public popularity discovery limit',
      'public artist or album browse pagination',
      'explicit public artist or album catalog search query and pagination',
      'public artist or album identifier',
      'public artwork URL',
      'user-configured Jamendo developer client ID',
    ],
  );

  @override
  Set<MusicCatalogCollectionKind> get pagedCollectionKinds =>
      const <MusicCatalogCollectionKind>{
        MusicCatalogCollectionKind.artist,
        MusicCatalogCollectionKind.album,
        MusicCatalogCollectionKind.playlist,
      };

  @override
  Set<MusicCatalogCollectionKind> get searchableCollectionKinds =>
      pagedCollectionKinds;

  @override
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  ) async {
    return (await browseCollectionsPage(kind)).collections;
  }

  @override
  Future<MusicCatalogCollectionPage> browseCollectionsPage(
    MusicCatalogCollectionKind kind, {
    int offset = 0,
    int limit = 100,
  }) {
    return _loadCollectionsPage(kind, offset: offset, limit: limit);
  }

  @override
  Future<MusicCatalogCollectionPage> searchCollectionsPage(
    MusicCatalogCollectionKind kind,
    String query, {
    int offset = 0,
    int limit = 100,
  }) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return Future<MusicCatalogCollectionPage>.value(
        const MusicCatalogCollectionPage(
          collections: <MusicCatalogCollection>[],
          nextOffset: 0,
          hasMore: false,
        ),
      );
    }
    return _loadCollectionsPage(
      kind,
      query: normalizedQuery,
      offset: offset,
      limit: limit,
    );
  }

  Future<MusicCatalogCollectionPage> _loadCollectionsPage(
    MusicCatalogCollectionKind kind, {
    String? query,
    required int offset,
    required int limit,
  }) async {
    if (!pagedCollectionKinds.contains(kind)) {
      throw UnsupportedError('Jamendo does not expose public $kind browsing.');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final requestedLimit = limit.clamp(1, 200);
    final response = _parseJamendoResponse(
      await _loader(
        _catalogRequestUri(
          kind,
          query: query,
          offset: offset,
          limit: requestedLimit,
        ),
      ),
    );
    final collections = _parseJamendoCollections(response.results, kind);
    final resultCount = response.results.length;
    final nextOffset = offset + resultCount;
    final hasMore = response.fullCount == null
        ? resultCount == requestedLimit
        : nextOffset < response.fullCount!;
    return MusicCatalogCollectionPage(
      collections: collections,
      nextOffset: nextOffset,
      hasMore: hasMore,
      totalCount: response.fullCount,
    );
  }

  @override
  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  ) async {
    if (!pagedCollectionKinds.contains(collection.kind)) {
      throw UnsupportedError('Jamendo collection type is not supported.');
    }
    final collectionId = collection.id.trim();
    if (!RegExp(r'^\d+$').hasMatch(collectionId)) {
      throw ArgumentError.value(collection.id, 'collection.id', 'Is invalid.');
    }
    final isArtist = collection.kind == MusicCatalogCollectionKind.artist;
    if (isArtist) {
      final albums = _parseJamendoNestedAlbums(
        _parseJamendoResponse(
          await _loader(
            artistAlbumsUri.replace(
              queryParameters: <String, String>{
                'client_id': _clientId,
                'format': 'json',
                'id': collectionId,
                'limit': '100',
                'imagesize': '300',
              },
            ),
          ),
        ).results,
      );
      if (albums.isNotEmpty) {
        return MusicCatalogDetail(
          collection: collection,
          collections: albums,
        );
      }
    }
    final response = _parseJamendoResponse(
      await _loader(
        (isArtist
                ? artistTracksUri
                : collection.kind == MusicCatalogCollectionKind.playlist
                ? playlistTracksUri
                : albumTracksUri)
            .replace(
          queryParameters: <String, String>{
            'client_id': _clientId,
            'format': 'json',
            'id': collectionId,
            'limit': '100',
            'imagesize': '300',
            'audioformat': 'mp32',
            if (isArtist ||
                collection.kind == MusicCatalogCollectionKind.playlist)
              'track_type': 'single albumtrack',
          },
        ),
      ),
    );
    return MusicCatalogDetail(
      collection: collection,
      tracks: _parseJamendoNestedTracks(
        response.results,
        fallbackArtist: isArtist ? collection.title : '',
        fallbackAlbum: isArtist ? '' : collection.title,
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

  /// Returns a bounded, public chart ordered by Jamendo popularity.
  ///
  /// The API documents `groupby=artist_id` for chart presentation, so a
  /// refresh does not fill the small Home shelf with one artist's catalog.
  Future<List<Track>> fetchPopular({
    int limit = 6,
    JamendoFeaturedGenre? featuredGenre,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final requestedLimit = limit.clamp(1, 50);
    return parseJamendoTracksResponse(
      await _loader(
        tracksUri.replace(
          queryParameters: <String, String>{
            'client_id': _clientId,
            'format': 'json',
            'limit': requestedLimit.toString(),
            'groupby': 'artist_id',
            if (featuredGenre == null) 'order': 'popularity_total',
            if (featuredGenre != null) 'featured': '1',
            if (featuredGenre != null) 'tags': featuredGenre.apiValue,
            if (featuredGenre != null) 'boost': 'popularity_total',
            'type': 'single albumtrack',
            'audioformat': 'mp32',
            'imagesize': '300',
          },
        ),
      ),
    );
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    if (track.sourceId != id) {
      return null;
    }
    final direct = _safeHttpsUri(track.streamUrl ?? '');
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

  Uri _catalogRequestUri(
    MusicCatalogCollectionKind kind, {
    String? query,
    required int offset,
    required int limit,
  }) {
    final isArtist = kind == MusicCatalogCollectionKind.artist;
    final isPlaylist = kind == MusicCatalogCollectionKind.playlist;
    return (isArtist ? artistsUri : isPlaylist ? playlistsUri : albumsUri).replace(
      queryParameters: <String, String>{
        'client_id': _clientId,
        'format': 'json',
        'offset': offset.toString(),
        'limit': limit.toString(),
        'fullcount': 'true',
        'order': isPlaylist ? 'creationdate_desc' : 'popularity_total',
        if (!isPlaylist) 'imagesize': '300',
        if (isArtist) 'hasimage': 'true',
        if (!isArtist && !isPlaylist) 'type': 'album single',
        'namesearch': ?query,
      },
    );
  }
}

List<Track> parseJamendoTracksResponse(String jsonText) {
  return _parseJamendoTracks(_parseJamendoResponse(jsonText).results);
}

final class _JamendoResponse {
  const _JamendoResponse({
    required this.results,
    this.fullCount,
  });

  final List<Map<String, Object?>> results;
  final int? fullCount;
}

_JamendoResponse _parseJamendoResponse(String jsonText) {
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

  return _JamendoResponse(
    results: results
        .whereType<Map<dynamic, dynamic>>()
        .map((value) => value.cast<String, Object?>())
        .toList(growable: false),
    fullCount: _integerValue(headerMap['results_fullcount']),
  );
}

List<Track> _parseJamendoTracks(Iterable<Map<String, Object?>> results) {
  final tracks = <Track>[];
  final seen = <String>{};
  for (final value in results) {
    final track = _parseJamendoTrack(value);
    if (track == null || !seen.add(track.externalId!)) {
      continue;
    }
    tracks.add(track);
  }
  return List<Track>.unmodifiable(tracks);
}

Track? _parseJamendoTrack(
  Map<String, Object?> value, {
  String fallbackArtist = '',
  String fallbackAlbum = '',
  String fallbackArtwork = '',
}) {
  final externalId = _stringValue(value['id']);
  final title = _stringValue(value['name']);
  if (!RegExp(r'^\d+$').hasMatch(externalId) || title.isEmpty) {
    return null;
  }
  final durationSeconds = _integerValue(value['duration']) ?? 0;
  final artwork =
      _safeHttpsUri(_stringValue(value['image'])) ??
      _safeHttpsUri(_stringValue(value['album_image'])) ??
      _safeHttpsUri(fallbackArtwork);
  final artist = _firstNonEmpty(<String>[
    _stringValue(value['artist_name']),
    fallbackArtist,
    'Unknown Artist',
  ]);
  final album = _firstNonEmpty(<String>[
    _stringValue(value['album_name']),
    fallbackAlbum,
    'Single',
  ]);
  return Track(
    id: 'jamendo:$externalId',
    title: title,
    artist: artist,
    album: album,
    duration: Duration(seconds: durationSeconds < 0 ? 0 : durationSeconds),
    artworkUri: artwork,
    artworkSourceUri: artwork,
    streamUrl: _safeHttpsUri(_stringValue(value['audio']))?.toString(),
    sourceId: 'jamendo',
    externalId: externalId,
  );
}

List<MusicCatalogCollection> _parseJamendoCollections(
  Iterable<Map<String, Object?>> results,
  MusicCatalogCollectionKind kind,
) {
  final collections = <MusicCatalogCollection>[];
  final seen = <String>{};
  for (final value in results) {
    final id = _stringValue(value['id']);
    final title = _stringValue(value['name']);
    if (!RegExp(r'^\d+$').hasMatch(id) || title.isEmpty || !seen.add(id)) {
      continue;
    }
    final subtitle = switch (kind) {
      MusicCatalogCollectionKind.artist => _stringValue(value['joindate'])
              .isEmpty
          ? ''
          : 'Joined ${_stringValue(value['joindate'])}',
      MusicCatalogCollectionKind.album => _joinNonEmpty(<String>[
          _stringValue(value['artist_name']),
          _stringValue(value['releasedate']),
        ]),
      MusicCatalogCollectionKind.playlist => _joinNonEmpty(<String>[
          _stringValue(value['user_name']),
          _stringValue(value['creationdate']),
        ]),
    };
    final artwork = _safeHttpsUri(_stringValue(value['image']));
    collections.add(
      MusicCatalogCollection(
        id: id,
        title: title,
        kind: kind,
        subtitle: subtitle,
        artworkId: artwork?.toString(),
      ),
    );
  }
  return List<MusicCatalogCollection>.unmodifiable(collections);
}

List<Track> _parseJamendoNestedTracks(
  Iterable<Map<String, Object?>> results, {
  required String fallbackArtist,
  required String fallbackAlbum,
}) {
  final tracks = <Track>[];
  final seen = <String>{};
  for (final parent in results) {
    final parentArtist = _firstNonEmpty(<String>[
      _stringValue(parent['artist_name']),
      fallbackArtist,
      _stringValue(parent['name']),
    ]);
    final parentAlbum = _firstNonEmpty(<String>[
      _stringValue(parent['album_name']),
      fallbackAlbum,
      _stringValue(parent['name']),
    ]);
    final parentArtwork = _stringValue(parent['image']);
    final rawTracks = parent['tracks'];
    if (rawTracks is! List<dynamic>) {
      continue;
    }
    for (final raw in rawTracks.whereType<Map<dynamic, dynamic>>()) {
      final track = _parseJamendoTrack(
        raw.cast<String, Object?>(),
        fallbackArtist: parentArtist,
        fallbackAlbum: parentAlbum,
        fallbackArtwork: parentArtwork,
      );
      if (track != null && seen.add(track.externalId!)) {
        tracks.add(track);
      }
    }
  }
  return List<Track>.unmodifiable(tracks);
}

List<MusicCatalogCollection> _parseJamendoNestedAlbums(
  Iterable<Map<String, Object?>> results,
) {
  final albums = <MusicCatalogCollection>[];
  final seen = <String>{};
  for (final artist in results) {
    final artistName = _stringValue(artist['name']);
    final rawAlbums = artist['albums'];
    if (rawAlbums is! List<dynamic>) {
      continue;
    }
    for (final raw in rawAlbums.whereType<Map<dynamic, dynamic>>()) {
      final album = raw.cast<String, Object?>();
      final id = _stringValue(album['id']);
      final title = _stringValue(album['name']);
      if (!RegExp(r'^\d+$').hasMatch(id) ||
          title.isEmpty ||
          !seen.add(id) ||
          albums.length >= 100) {
        continue;
      }
      final artwork = _safeHttpsUri(_stringValue(album['image']));
      albums.add(
        MusicCatalogCollection(
          id: id,
          title: title,
          kind: MusicCatalogCollectionKind.album,
          subtitle: _joinNonEmpty(<String>[
            artistName,
            _stringValue(album['releasedate']),
          ]),
          artworkId: artwork?.toString(),
        ),
      );
    }
  }
  return List<MusicCatalogCollection>.unmodifiable(albums);
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

String _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return '';
}

String _joinNonEmpty(Iterable<String> values) {
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(' · ');
}

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
