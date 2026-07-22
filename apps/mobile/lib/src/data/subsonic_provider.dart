import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/music_catalog_discovery_provider.dart';
import '../domain/music_catalog_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/track.dart';
import 'provider_binary_loader.dart';
import 'provider_error.dart';

typedef SubsonicRequestLoader = Future<String> Function(Uri requestUri);
typedef SubsonicSaltGenerator = String Function();

class SubsonicProvider
    implements
        MusicCatalogDiscoveryProvider,
        MusicCatalogDiscoveryPagingProvider,
        MusicCatalogPagingProvider,
        MusicCatalogRadioProvider,
        MusicPlaylistMutationProvider,
        MusicTrackFavoriteMutationProvider,
        MusicAlbumFavoriteMutationProvider,
        MusicSourceSearchSuggestionProvider,
        MusicSourceSearchPagingProvider {
  SubsonicProvider({
    required this.baseUri,
    required this.username,
    required this.password,
    String? id,
    String? name,
    SubsonicRequestLoader? requestLoader,
    ProviderBinaryRequestLoader? artworkLoader,
    SubsonicSaltGenerator? saltGenerator,
    this.limit = 20,
    this.apiVersion = '1.16.1',
    this.clientName = 'AetherTune',
  })  : id = id ?? 'subsonic-${Track.stableLocalId(baseUri.toString())}',
        name = name ?? 'Navidrome / Subsonic',
        _requestLoader = requestLoader ?? _loadSubsonicJson,
        _artworkLoader = artworkLoader ?? loadProviderImageBytes,
        _saltGenerator = saltGenerator ?? _randomSalt;

  static const defaultCapabilities = <MusicSourceCapability>{
    MusicSourceCapability.metadataSearch,
    MusicSourceCapability.searchSuggestions,
    MusicSourceCapability.streamResolution,
    MusicSourceCapability.libraryBrowse,
    MusicSourceCapability.playlists,
    MusicSourceCapability.playlistMutation,
    MusicSourceCapability.favoriteMutation,
    MusicSourceCapability.albumFavoriteMutation,
    MusicSourceCapability.artwork,
    MusicSourceCapability.directPlayback,
    MusicSourceCapability.offlineCache,
    MusicSourceCapability.downloads,
    MusicSourceCapability.recommendations,
    MusicSourceCapability.authentication,
  };

  final Uri baseUri;
  final String username;
  final String password;
  final int limit;
  final String apiVersion;
  final String clientName;
  final SubsonicRequestLoader _requestLoader;
  final ProviderBinaryRequestLoader _artworkLoader;
  final SubsonicSaltGenerator _saltGenerator;

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
          'salted authentication token',
          'song search query',
          'audio search suggestion query',
          'artist, album, and playlist browse identifiers',
          'Home discovery list selection and result limit',
          'radio seed item identifier and result limit',
          'playlist names, membership, and track order changes',
          'favorite track changes',
          'favorite album changes',
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
    final page = await searchPage(query, limit: limit);
    return page.tracks;
  }

  @override
  Future<List<MusicSourceSearchSuggestion>> suggest(
    String query, {
    int limit = 8,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
    }
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <MusicSourceSearchSuggestion>[];
    }
    final boundedLimit = limit.clamp(1, 20);
    return _guardRequest(() async {
      return parseSubsonicSearchSuggestionsResponse(
        await _requestLoader(
          _suggestionsUri(normalizedQuery, limit: boundedLimit),
        ),
        limit: boundedLimit,
      );
    });
  }

  @override
  Future<MusicSourceSearchPage> searchPage(
    String query, {
    String? cursor,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
    }
    final offset = _subsonicSearchOffset(cursor);
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const MusicSourceSearchPage(tracks: <Track>[]);
    }
    final boundedLimit = limit.clamp(1, 500);
    return _guardRequest(() async {
      return parseSubsonicSearchPageResponse(
        await _requestLoader(
          _searchUri(
            normalizedQuery,
            offset: offset,
            limit: boundedLimit,
          ),
        ),
        sourceId: id,
        requestOffset: offset,
        requestLimit: boundedLimit,
      );
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
  Set<MusicCatalogCollectionKind> get pagedCollectionKinds =>
      const <MusicCatalogCollectionKind>{
        MusicCatalogCollectionKind.album,
      };

  @override
  Future<MusicCatalogCollectionPage> browseCollectionsPage(
    MusicCatalogCollectionKind kind, {
    int offset = 0,
    int limit = 100,
  }) {
    if (!pagedCollectionKinds.contains(kind)) {
      return Future<MusicCatalogCollectionPage>.error(
        UnsupportedError('Subsonic catalog kind is not pageable.'),
      );
    }
    if (offset < 0) {
      return Future<MusicCatalogCollectionPage>.error(
        ArgumentError.value(offset, 'offset', 'Offset cannot be negative.'),
      );
    }
    if (limit <= 0) {
      return Future<MusicCatalogCollectionPage>.error(
        ArgumentError.value(limit, 'limit', 'Limit must be positive.'),
      );
    }
    final boundedLimit = limit.clamp(1, 500);
    return _guardRequest(() async {
      return parseSubsonicAlbumListPageResponse(
        await _requestLoader(
          _requestUri(
            '/rest/getAlbumList2.view',
            <String, String>{
              'type': 'alphabeticalByName',
              'size': boundedLimit.toString(),
              'offset': offset.toString(),
            },
          ),
        ),
        requestOffset: offset,
        requestLimit: boundedLimit,
      );
    });
  }

  @override
  List<MusicCatalogDiscoveryKind> get discoveryKinds =>
      const <MusicCatalogDiscoveryKind>[
        MusicCatalogDiscoveryKind.recentlyAdded,
        MusicCatalogDiscoveryKind.frequentlyPlayed,
        MusicCatalogDiscoveryKind.recentlyPlayed,
        MusicCatalogDiscoveryKind.favorites,
        MusicCatalogDiscoveryKind.random,
      ];

  @override
  Set<MusicCatalogDiscoveryKind> get pagedDiscoveryKinds =>
      Set<MusicCatalogDiscoveryKind>.unmodifiable(discoveryKinds);

  @override
  Future<List<MusicCatalogCollection>> browseDiscoveryCollections(
    MusicCatalogDiscoveryKind kind, {
    int limit = 6,
  }) async {
    return (await browseDiscoveryCollectionsPage(
      kind,
      limit: limit.clamp(1, 500),
    )).collections;
  }

  @override
  Future<MusicCatalogCollectionPage> browseDiscoveryCollectionsPage(
    MusicCatalogDiscoveryKind kind, {
    int offset = 0,
    int limit = 6,
  }) {
    if (!discoveryKinds.contains(kind)) {
      return Future<MusicCatalogCollectionPage>.error(
        UnsupportedError('Subsonic discovery kind is not supported.'),
      );
    }
    if (offset < 0) {
      return Future<MusicCatalogCollectionPage>.error(
        ArgumentError.value(offset, 'offset', 'Offset cannot be negative.'),
      );
    }
    if (limit <= 0) {
      return Future<MusicCatalogCollectionPage>.error(
        ArgumentError.value(limit, 'limit', 'Limit must be positive.'),
      );
    }
    final listType = switch (kind) {
      MusicCatalogDiscoveryKind.recentlyAdded => 'newest',
      MusicCatalogDiscoveryKind.frequentlyPlayed => 'frequent',
      MusicCatalogDiscoveryKind.recentlyPlayed => 'recent',
      MusicCatalogDiscoveryKind.favorites => 'starred',
      MusicCatalogDiscoveryKind.random => 'random',
    };
    final boundedLimit = limit.clamp(1, 500);
    return _guardRequest(() async {
      return parseSubsonicAlbumListPageResponse(
        await _requestLoader(
          _requestUri(
            '/rest/getAlbumList2.view',
            <String, String>{
              'type': listType,
              'size': boundedLimit.toString(),
              'offset': offset.toString(),
            },
          ),
        ),
        requestOffset: offset,
        requestLimit: boundedLimit,
      );
    });
  }

  @override
  Future<Uint8List?> loadArtwork(
    String artworkId, {
    String? version,
    int maxWidth = 512,
  }) {
    final normalizedId = artworkId.trim();
    if (normalizedId.isEmpty) {
      return Future<Uint8List?>.value(null);
    }
    return _guardRequest(
      () => _artworkLoader(
        _requestUri(
          '/rest/getCoverArt.view',
          <String, String>{
            'id': normalizedId,
            'size': maxWidth.clamp(32, 2048).toString(),
          },
        ),
        const <String, String>{},
      ),
    );
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
  Set<MusicCatalogRadioSeedKind> get radioSeedKinds =>
      MusicCatalogRadioSeedKind.values.toSet();

  @override
  Future<List<Track>> loadRadio(
    MusicCatalogRadioSeed seed, {
    int limit = 50,
  }) {
    final normalizedId = seed.id.trim();
    if (normalizedId.isEmpty) {
      return Future<List<Track>>.error(
        ArgumentError.value(seed.id, 'seed.id', 'Seed ID cannot be empty.'),
      );
    }
    if (!radioSeedKinds.contains(seed.kind)) {
      return Future<List<Track>>.error(
        UnsupportedError('Subsonic radio seed kind is not supported.'),
      );
    }
    if (limit <= 0) {
      return Future<List<Track>>.error(
        ArgumentError.value(limit, 'limit', 'Limit must be positive.'),
      );
    }
    final boundedLimit = limit.clamp(1, 500);
    final id3Response = seed.kind == MusicCatalogRadioSeedKind.artist;
    return _guardRequest(() async {
      return parseSubsonicSimilarSongsResponse(
        await _requestLoader(
          _requestUri(
            id3Response
                ? '/rest/getSimilarSongs2.view'
                : '/rest/getSimilarSongs.view',
            <String, Object?>{
              'id': normalizedId,
              'count': boundedLimit.toString(),
            },
          ),
        ),
        sourceId: id,
        id3Response: id3Response,
      );
    });
  }

  @override
  Future<void> createPlaylist(
    String name, {
    List<String> trackIds = const <String>[],
  }) {
    final normalizedName = _requiredPlaylistName(name);
    final normalizedTrackIds = _playlistTrackIds(trackIds);
    return _guardRequest(() async {
      _subsonicResponse(
        await _requestLoader(
          _requestUri(
            '/rest/createPlaylist.view',
            <String, Object?>{
              'name': normalizedName,
              if (normalizedTrackIds.isNotEmpty) 'songId': normalizedTrackIds,
            },
          ),
        ),
      );
    });
  }

  @override
  Future<void> renamePlaylist(String playlistId, String name) {
    final normalizedPlaylistId = _requiredPlaylistId(playlistId);
    final normalizedName = _requiredPlaylistName(name);
    return _guardRequest(() async {
      _subsonicResponse(
        await _requestLoader(
          _requestUri(
            '/rest/updatePlaylist.view',
            <String, Object?>{
              'playlistId': normalizedPlaylistId,
              'name': normalizedName,
            },
          ),
        ),
      );
    });
  }

  @override
  Future<void> deletePlaylist(String playlistId) {
    final normalizedPlaylistId = _requiredPlaylistId(playlistId);
    return _guardRequest(() async {
      _subsonicResponse(
        await _requestLoader(
          _requestUri(
            '/rest/deletePlaylist.view',
            <String, Object?>{'id': normalizedPlaylistId},
          ),
        ),
      );
    });
  }

  @override
  Future<void> addPlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    final normalizedPlaylistId = _requiredPlaylistId(playlistId);
    final normalizedTrackIds = _playlistTrackIds(trackIds);
    if (normalizedTrackIds.isEmpty) {
      return;
    }
    await _guardRequest(() async {
      _subsonicResponse(
        await _requestLoader(
          _requestUri(
            '/rest/updatePlaylist.view',
            <String, Object?>{
              'playlistId': normalizedPlaylistId,
              'songIdToAdd': normalizedTrackIds,
            },
          ),
        ),
      );
    });
  }

  @override
  Future<void> replacePlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) {
    final normalizedPlaylistId = _requiredPlaylistId(playlistId);
    final normalizedTrackIds = _playlistTrackIds(trackIds);
    return _guardRequest(() async {
      _subsonicResponse(
        await _requestLoader(
          _requestUri(
            '/rest/createPlaylist.view',
            <String, Object?>{
              'playlistId': normalizedPlaylistId,
              if (normalizedTrackIds.isNotEmpty) 'songId': normalizedTrackIds,
            },
          ),
        ),
      );
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

  Uri _searchUri(
    String query, {
    required int offset,
    required int limit,
  }) {
    return _requestUri(
      '/rest/search3.view',
      <String, String>{
        'query': query,
        'artistCount': '0',
        'albumCount': '0',
        'songCount': limit.toString(),
        'songOffset': offset.toString(),
      },
    );
  }

  Uri _suggestionsUri(String query, {required int limit}) {
    return _requestUri(
      '/rest/search3.view',
      <String, String>{
        'query': query,
        'artistCount': limit.toString(),
        'artistOffset': '0',
        'albumCount': limit.toString(),
        'albumOffset': '0',
        'songCount': limit.toString(),
        'songOffset': '0',
      },
    );
  }

  @override
  Future<void> setTrackFavorite(
    String trackId, {
    required bool isFavorite,
  }) {
    final normalizedTrackId = _requiredPlaylistId(trackId);
    return _guardRequest(() async {
      _subsonicResponse(
        await _requestLoader(
          _requestUri(
            isFavorite ? '/rest/star.view' : '/rest/unstar.view',
            <String, Object?>{'id': normalizedTrackId},
          ),
        ),
      );
    });
  }

  @override
  Future<void> setAlbumFavorite(
    String albumId, {
    required bool isFavorite,
  }) {
    final normalizedAlbumId = _requiredPlaylistId(albumId);
    return _guardRequest(() async {
      _subsonicResponse(
        await _requestLoader(
          _requestUri(
            isFavorite ? '/rest/star.view' : '/rest/unstar.view',
            <String, Object?>{'albumId': normalizedAlbumId},
          ),
        ),
      );
    });
  }

  Uri _requestUri(String endpointPath, Map<String, Object?> parameters) {
    return baseUri.replace(
      path: _joinUriPath(baseUri.path, endpointPath),
      queryParameters: <String, Object?>{
        ..._authenticationParameters,
        ...parameters,
      },
    );
  }

  Map<String, String> get _authenticationParameters {
    final salt = _saltGenerator().trim();
    if (salt.isEmpty) {
      throw StateError('Subsonic authentication salt cannot be empty.');
    }
    final token = md5.convert(utf8.encode('$password$salt')).toString();
    return <String, String>{
      'u': username,
      't': token,
      's': salt,
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
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final Duration duration;
  final String coverArt;
  final String suffix;
  final bool isFavorite;

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
      providerArtworkId: coverArt.isEmpty ? null : coverArt,
      streamUrl: streamUri?.toString(),
      sourceId: sourceId,
      externalId: id,
      isFavorite: isFavorite,
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

MusicSourceSearchPage parseSubsonicSearchPageResponse(
  String jsonText, {
  required String sourceId,
  required int requestOffset,
  required int requestLimit,
}) {
  final response = _subsonicResponse(jsonText);
  final searchResult = response['searchResult3'];
  final rawSongs = searchResult is Map<dynamic, dynamic>
      ? _jsonList(searchResult['song'])
      : const <Object?>[];
  final tracks = rawSongs
      .whereType<Map<dynamic, dynamic>>()
      .map((song) => _songFromJson(song.cast<String, Object?>()))
      .whereType<SubsonicSong>()
      .map((song) => song.toTrack(sourceId: sourceId))
      .toList(growable: false);
  final nextOffset = requestOffset + rawSongs.length;
  final hasMore = rawSongs.isNotEmpty && rawSongs.length >= requestLimit;
  return MusicSourceSearchPage(
    tracks: List<Track>.unmodifiable(tracks),
    nextCursor: hasMore ? nextOffset.toString() : null,
  );
}

List<MusicSourceSearchSuggestion> parseSubsonicSearchSuggestionsResponse(
  String jsonText, {
  required int limit,
}) {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
  }
  final response = _subsonicResponse(jsonText);
  final searchResult = response['searchResult3'];
  if (searchResult is! Map<dynamic, dynamic>) {
    return const <MusicSourceSearchSuggestion>[];
  }

  final suggestions = <MusicSourceSearchSuggestion>[];
  final seen = <String>{};
  void add(
    String value,
    MusicSourceSearchSuggestionKind kind, {
    String? subtitle,
  }) {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty || suggestions.length == limit) {
      return;
    }
    if (!seen.add(normalizedValue.toLowerCase())) {
      return;
    }
    final normalizedSubtitle = subtitle?.trim();
    suggestions.add(
      MusicSourceSearchSuggestion(
        value: normalizedValue,
        kind: kind,
        subtitle: normalizedSubtitle == null || normalizedSubtitle.isEmpty
            ? null
            : normalizedSubtitle,
      ),
    );
  }

  for (final rawArtist in _jsonList(searchResult['artist'])) {
    if (rawArtist is! Map<dynamic, dynamic>) {
      continue;
    }
    final artist = rawArtist.cast<String, Object?>();
    add(
      _stringValue(artist['name']),
      MusicSourceSearchSuggestionKind.artist,
    );
  }
  for (final rawAlbum in _jsonList(searchResult['album'])) {
    if (rawAlbum is! Map<dynamic, dynamic>) {
      continue;
    }
    final album = rawAlbum.cast<String, Object?>();
    add(
      _stringValue(album['name']),
      MusicSourceSearchSuggestionKind.album,
      subtitle: _stringValue(album['artist']),
    );
  }
  for (final rawSong in _jsonList(searchResult['song'])) {
    if (rawSong is! Map<dynamic, dynamic>) {
      continue;
    }
    final song = rawSong.cast<String, Object?>();
    add(
      _stringValue(song['title']),
      MusicSourceSearchSuggestionKind.track,
      subtitle: _stringValue(song['artist']),
    );
  }
  return List<MusicSourceSearchSuggestion>.unmodifiable(suggestions);
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

MusicCatalogCollectionPage parseSubsonicAlbumListPageResponse(
  String jsonText, {
  required int requestOffset,
  required int requestLimit,
}) {
  final response = _subsonicResponse(jsonText);
  final list = response['albumList2'];
  final rawAlbums = list is Map<dynamic, dynamic>
      ? _jsonList(list['album'])
      : const <Object?>[];
  final collections = _subsonicCollections(
    rawAlbums,
    MusicCatalogCollectionKind.album,
  );
  final nextOffset = requestOffset + rawAlbums.length;
  return MusicCatalogCollectionPage(
    collections: List<MusicCatalogCollection>.unmodifiable(collections),
    nextOffset: nextOffset,
    hasMore: rawAlbums.isNotEmpty && rawAlbums.length >= requestLimit,
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

List<Track> parseSubsonicSimilarSongsResponse(
  String jsonText, {
  required String sourceId,
  required bool id3Response,
}) {
  final response = _subsonicResponse(jsonText);
  final similarSongs = response[
    id3Response ? 'similarSongs2' : 'similarSongs'
  ];
  if (similarSongs is! Map<dynamic, dynamic>) {
    return const <Track>[];
  }
  return _subsonicTracks(similarSongs['song'], sourceId: sourceId);
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
  final artworkId = _stringValue(json['coverArt']);
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
    isFavorite: _subsonicIsFavorite(json['starred']),
    artworkId: artworkId.isEmpty ? null : artworkId,
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
    isFavorite: _subsonicIsFavorite(json['starred']),
  );
}

bool _subsonicIsFavorite(Object? value) {
  return switch (value) {
    bool favorite => favorite,
    null => false,
    _ => _stringValue(value).isNotEmpty,
  };
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

String _requiredPlaylistName(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(name, 'name', 'Playlist name cannot be empty.');
  }
  return normalized;
}

String _requiredPlaylistId(String playlistId) {
  final normalized = playlistId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(
      playlistId,
      'playlistId',
      'Playlist ID cannot be empty.',
    );
  }
  return normalized;
}

List<String> _playlistTrackIds(List<String> trackIds) {
  return trackIds.map((trackId) {
    final normalized = trackId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        trackIds,
        'trackIds',
        'Playlist track IDs cannot be empty.',
      );
    }
    return normalized;
  }).toList(growable: false);
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

String _randomSalt() {
  final random = Random.secure();
  return _hexEncode(
    List<int>.generate(12, (_) => random.nextInt(256), growable: false),
  );
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

int _subsonicSearchOffset(String? cursor) {
  if (cursor == null) {
    return 0;
  }
  final offset = int.tryParse(cursor);
  if (offset == null || offset < 0) {
    throw ArgumentError.value(cursor, 'cursor', 'Invalid search cursor.');
  }
  return offset;
}
