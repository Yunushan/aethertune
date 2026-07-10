import 'dart:convert';
import 'dart:io';

import '../domain/music_catalog_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/track.dart';
import 'provider_error.dart';

typedef SubsonicRequestLoader = Future<String> Function(Uri requestUri);

class SubsonicProvider implements MusicCatalogProvider {
  SubsonicProvider({
    required this.baseUri,
    required this.username,
    required this.password,
    String? id,
    String? name,
    SubsonicRequestLoader? requestLoader,
    this.limit = 20,
    this.apiVersion = '1.16.1',
    this.clientName = 'AetherTune',
  })  : id = id ?? 'subsonic-${Track.stableLocalId(baseUri.toString())}',
        name = name ?? 'Navidrome / Subsonic',
        _requestLoader = requestLoader ?? _loadSubsonicJson;

  static const defaultCapabilities = <MusicSourceCapability>{
    MusicSourceCapability.metadataSearch,
    MusicSourceCapability.streamResolution,
    MusicSourceCapability.libraryBrowse,
    MusicSourceCapability.playlists,
    MusicSourceCapability.directPlayback,
    MusicSourceCapability.offlineCache,
    MusicSourceCapability.downloads,
    MusicSourceCapability.authentication,
  };

  final Uri baseUri;
  final String username;
  final String password;
  final int limit;
  final String apiVersion;
  final String clientName;
  final SubsonicRequestLoader _requestLoader;

  @override
  final String id;

  @override
  final String name;

  @override
  String get description =>
      'Subsonic REST adapter for user-owned Navidrome/Subsonic music servers.';

  @override
  Set<MusicSourceCapability> get capabilities => defaultCapabilities;

  @override
  ProviderPrivacyDisclosure get disclosure => ProviderPrivacyDisclosure(
        networkDomains: baseUri.host.isEmpty ? const <String>[] : <String>[
          baseUri.host,
        ],
        dataSent: const <String>[
          'username credential',
          'encoded password credential',
          'song search query',
          'artist, album, and playlist browse identifiers',
          'song stream identifier',
          'cover art identifier',
        ],
        requiresUserCredentials: true,
        cachesMetadata: true,
        cachesMedia: true,
        supportsDownloads: true,
      );

  @override
  Future<List<Track>> search(String query) {
    return searchSongs(query);
  }

  Future<List<Track>> searchSongs(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <Track>[];
    }

    return _guardRequest(() async {
      final songs = parseSubsonicSearchResponse(
        await _requestLoader(_searchUri(normalizedQuery)),
      );
      return songs
          .take(limit)
          .map((song) => song.toTrack(sourceId: id))
          .toList(growable: false);
    });
  }

  Future<void> testConnection() async {
    await _guardRequest(() async {
      _subsonicResponse(
        await _requestLoader(
          _requestUri('/rest/ping.view', const <String, String>{}),
        ),
      );
    });
  }

  @override
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  ) {
    return _guardRequest(() async {
      switch (kind) {
        case MusicCatalogCollectionKind.artist:
          return parseSubsonicArtistsResponse(
            await _requestLoader(
              _requestUri(
                '/rest/getArtists.view',
                const <String, String>{},
              ),
            ),
          );
        case MusicCatalogCollectionKind.album:
          return parseSubsonicAlbumListResponse(
            await _requestLoader(
              _requestUri(
                '/rest/getAlbumList2.view',
                const <String, String>{
                  'type': 'alphabeticalByName',
                  'size': '500',
                  'offset': '0',
                },
              ),
            ),
          );
        case MusicCatalogCollectionKind.playlist:
          return parseSubsonicPlaylistsResponse(
            await _requestLoader(
              _requestUri(
                '/rest/getPlaylists.view',
                const <String, String>{},
              ),
            ),
          );
      }
    });
  }

  @override
  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  ) {
    return _guardRequest(() async {
      switch (collection.kind) {
        case MusicCatalogCollectionKind.artist:
          final albums = parseSubsonicArtistAlbumsResponse(
            await _requestLoader(
              _requestUri(
                '/rest/getArtist.view',
                <String, String>{'id': collection.id},
              ),
            ),
          );
          return MusicCatalogDetail(
            collection: collection,
            collections: albums,
          );
        case MusicCatalogCollectionKind.album:
          final tracks = parseSubsonicAlbumTracksResponse(
            await _requestLoader(
              _requestUri(
                '/rest/getAlbum.view',
                <String, String>{'id': collection.id},
              ),
            ),
            sourceId: id,
          );
          return MusicCatalogDetail(
            collection: collection,
            tracks: tracks,
          );
        case MusicCatalogCollectionKind.playlist:
          final tracks = parseSubsonicPlaylistTracksResponse(
            await _requestLoader(
              _requestUri(
                '/rest/getPlaylist.view',
                <String, String>{'id': collection.id},
              ),
            ),
            sourceId: id,
          );
          return MusicCatalogDetail(
            collection: collection,
            tracks: tracks,
          );
      }
    });
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    if (track.sourceId != id) {
      return null;
    }

    final streamUrl = track.streamUrl;
    if (streamUrl != null && streamUrl.trim().isNotEmpty) {
      return Uri.tryParse(streamUrl);
    }

    final songId = track.externalId;
    if (songId == null || songId.trim().isEmpty) {
      return null;
    }

    return streamUriFor(songId);
  }

  Uri streamUriFor(String songId) {
    return _requestUri(
      '/rest/stream.view',
      <String, String>{'id': songId},
    );
  }

  Uri? coverArtUriFor(String coverArtId) {
    if (coverArtId.trim().isEmpty) {
      return null;
    }

    return _requestUri(
      '/rest/getCoverArt.view',
      <String, String>{'id': coverArtId},
    );
  }

  Uri _searchUri(String query) {
    return _requestUri(
      '/rest/search3.view',
      <String, String>{
        'query': query,
        'artistCount': '0',
        'albumCount': '0',
        'songCount': limit.toString(),
      },
    );
  }

  Uri _requestUri(String endpointPath, Map<String, String> parameters) {
    return baseUri.replace(
      path: _joinUriPath(baseUri.path, endpointPath),
      queryParameters: <String, String>{
        ..._authenticationParameters,
        ...parameters,
      },
    );
  }

  Map<String, String> get _authenticationParameters {
    return <String, String>{
      'u': username,
      'p': 'enc:${_hexEncode(utf8.encode(password))}',
      'v': apiVersion,
      'c': clientName,
      'f': 'json',
    };
  }

  Future<T> _guardRequest<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on Object catch (error) {
      throw ProviderRequestException(
        safeProviderErrorMessage(
          error,
          providerName: name,
          secrets: <String>[password],
        ),
      );
    }
  }
}

final class SubsonicSong {
  const SubsonicSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.duration,
    required this.coverArt,
    required this.suffix,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final Duration duration;
  final String coverArt;
  final String suffix;

  Track toTrack({
    required String sourceId,
    Uri? streamUri,
    Uri? artworkUri,
  }) {
    return Track(
      id: Track.stableLocalId('$sourceId|$id'),
      title: title.isEmpty ? id : title,
      artist: artist.isEmpty ? 'Unknown Artist' : artist,
      album: album.isEmpty ? 'Unknown Album' : album,
      genre: genre.isEmpty ? 'Self-hosted Music' : genre,
      duration: duration,
      artworkUri: artworkUri,
      streamUrl: streamUri?.toString(),
      sourceId: sourceId,
      externalId: id,
    );
  }
}

List<SubsonicSong> parseSubsonicSearchResponse(String jsonText) {
  final response = _subsonicResponse(jsonText);
  final searchResult = response['searchResult3'];
  if (searchResult is! Map<dynamic, dynamic>) {
    return const <SubsonicSong>[];
  }

  return _jsonList(searchResult['song'])
      .whereType<Map<dynamic, dynamic>>()
      .map((song) => _songFromJson(song.cast<String, Object?>()))
      .whereType<SubsonicSong>()
      .toList(growable: false);
}

List<MusicCatalogCollection> parseSubsonicArtistsResponse(String jsonText) {
  final response = _subsonicResponse(jsonText);
  final artists = response['artists'];
  if (artists is! Map<dynamic, dynamic>) {
    return const <MusicCatalogCollection>[];
  }
  return _jsonList(artists['index'])
      .whereType<Map<dynamic, dynamic>>()
      .expand((index) => _jsonList(index['artist']))
      .whereType<Map<dynamic, dynamic>>()
      .map((artist) => _subsonicCollection(
            artist.cast<String, Object?>(),
            MusicCatalogCollectionKind.artist,
          ))
      .whereType<MusicCatalogCollection>()
      .toList(growable: false);
}

List<MusicCatalogCollection> parseSubsonicAlbumListResponse(String jsonText) {
  final response = _subsonicResponse(jsonText);
  final list = response['albumList2'];
  if (list is! Map<dynamic, dynamic>) {
    return const <MusicCatalogCollection>[];
  }
  return _subsonicCollections(
    list['album'],
    MusicCatalogCollectionKind.album,
  );
}

List<MusicCatalogCollection> parseSubsonicPlaylistsResponse(String jsonText) {
  final response = _subsonicResponse(jsonText);
  final playlists = response['playlists'];
  if (playlists is! Map<dynamic, dynamic>) {
    return const <MusicCatalogCollection>[];
  }
  return _subsonicCollections(
    playlists['playlist'],
    MusicCatalogCollectionKind.playlist,
  );
}

List<MusicCatalogCollection> parseSubsonicArtistAlbumsResponse(
  String jsonText,
) {
  final response = _subsonicResponse(jsonText);
  final artist = response['artist'];
  if (artist is! Map<dynamic, dynamic>) {
    return const <MusicCatalogCollection>[];
  }
  return _subsonicCollections(
    artist['album'],
    MusicCatalogCollectionKind.album,
  );
}

List<Track> parseSubsonicAlbumTracksResponse(
  String jsonText, {
  required String sourceId,
}) {
  final response = _subsonicResponse(jsonText);
  final album = response['album'];
  if (album is! Map<dynamic, dynamic>) {
    return const <Track>[];
  }
  return _subsonicTracks(album['song'], sourceId: sourceId);
}

List<Track> parseSubsonicPlaylistTracksResponse(
  String jsonText, {
  required String sourceId,
}) {
  final response = _subsonicResponse(jsonText);
  final playlist = response['playlist'];
  if (playlist is! Map<dynamic, dynamic>) {
    return const <Track>[];
  }
  return _subsonicTracks(playlist['entry'], sourceId: sourceId);
}

List<MusicCatalogCollection> _subsonicCollections(
  Object? value,
  MusicCatalogCollectionKind kind,
) {
  return _jsonList(value)
      .whereType<Map<dynamic, dynamic>>()
      .map((item) => _subsonicCollection(item.cast<String, Object?>(), kind))
      .whereType<MusicCatalogCollection>()
      .toList(growable: false);
}

MusicCatalogCollection? _subsonicCollection(
  Map<String, Object?> json,
  MusicCatalogCollectionKind kind,
) {
  final id = _stringValue(json['id']);
  if (id.isEmpty) {
    return null;
  }
  final title = _stringValue(json['name']);
  final artist = _stringValue(json['artist']);
  final owner = _stringValue(json['owner']);
  final year = _intValue(json['year']);
  final itemCount = _intValue(
    kind == MusicCatalogCollectionKind.artist
        ? json['albumCount']
        : json['songCount'],
  );
  final subtitleParts = <String>[
    if (kind == MusicCatalogCollectionKind.album && artist.isNotEmpty) artist,
    if (kind == MusicCatalogCollectionKind.album && year > 0) year.toString(),
    if (kind == MusicCatalogCollectionKind.playlist && owner.isNotEmpty) owner,
    if (itemCount > 0)
      kind == MusicCatalogCollectionKind.artist
          ? '$itemCount album(s)'
          : '$itemCount track(s)',
  ];
  return MusicCatalogCollection(
    id: id,
    title: title.isEmpty ? id : title,
    kind: kind,
    subtitle: subtitleParts.join(' · '),
    itemCount: itemCount,
  );
}

List<Track> _subsonicTracks(Object? value, {required String sourceId}) {
  return _jsonList(value)
      .whereType<Map<dynamic, dynamic>>()
      .map((song) => _songFromJson(song.cast<String, Object?>()))
      .whereType<SubsonicSong>()
      .map((song) => song.toTrack(sourceId: sourceId))
      .toList(growable: false);
}

Map<String, Object?> _subsonicResponse(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Subsonic response must be a JSON object.');
  }

  final response = decoded['subsonic-response'];
  if (response is! Map<dynamic, dynamic>) {
    throw const FormatException('Subsonic response wrapper is missing.');
  }

  final json = response.cast<String, Object?>();
  final status = _stringValue(json['status']).toLowerCase();
  if (status == 'failed') {
    final error = json['error'];
    final message = error is Map<dynamic, dynamic>
        ? _stringValue(error['message'])
        : 'Unknown Subsonic error.';
    throw FormatException(
      message.isEmpty ? 'Subsonic request failed.' : message,
    );
  }
  if (status.isNotEmpty && status != 'ok') {
    throw FormatException('Unknown Subsonic status: $status.');
  }

  return json;
}

SubsonicSong? _songFromJson(Map<String, Object?> json) {
  final id = _stringValue(json['id']);
  if (id.isEmpty) {
    return null;
  }

  return SubsonicSong(
    id: id,
    title: _stringValue(json['title']),
    artist: _stringValue(json['artist']),
    album: _stringValue(json['album']),
    genre: _stringValue(json['genre']),
    duration: Duration(seconds: _intValue(json['duration'])),
    coverArt: _stringValue(json['coverArt']),
    suffix: _stringValue(json['suffix']),
  );
}

Future<String> _loadSubsonicJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderRequestException(
        'Subsonic request failed with HTTP ${response.statusCode}.',
      );
    }

    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}

List<Object?> _jsonList(Object? value) {
  if (value is List<dynamic>) {
    return value.cast<Object?>();
  }
  if (value == null) {
    return const <Object?>[];
  }

  return <Object?>[value];
}

String _hexEncode(List<int> bytes) {
  return bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

String _joinUriPath(String basePath, String childPath) {
  final normalizedBase = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  return '$normalizedBase$childPath';
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
