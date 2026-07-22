import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/music_catalog_discovery_provider.dart';
import '../domain/music_catalog_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/track.dart';
import 'provider_binary_loader.dart';
import 'provider_error.dart';

typedef JellyfinRequestLoader = Future<String> Function(Uri requestUri);
typedef JellyfinMutationLoader = Future<void> Function(
  Uri requestUri,
  String method,
  Map<String, Object?>? jsonBody,
);

class JellyfinProvider
    implements
        MusicCatalogDiscoveryPagingProvider,
        MusicCatalogPagingProvider,
        MusicCatalogRadioProvider,
        MusicPlaylistMutationProvider,
        MusicTrackFavoriteMutationProvider,
        MusicAlbumFavoriteMutationProvider,
        MusicArtistFavoriteMutationProvider,
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  JellyfinProvider({
    required this.baseUri,
    required this.userId,
    required this.apiKey,
    String? id,
    String? name,
    JellyfinRequestLoader? requestLoader,
    JellyfinMutationLoader? mutationLoader,
    ProviderBinaryRequestLoader? artworkLoader,
    this.limit = 20,
  })  : id = id ?? 'jellyfin-${Track.stableLocalId(baseUri.toString())}',
        name = name ?? 'Jellyfin',
        _requestLoader = requestLoader ?? _loadJellyfinJson,
        _mutationLoader = mutationLoader ?? _loadJellyfinMutation,
        _artworkLoader = artworkLoader ?? loadProviderImageBytes;

  static const defaultCapabilities = <MusicSourceCapability>{
    MusicSourceCapability.metadataSearch,
    MusicSourceCapability.searchSuggestions,
    MusicSourceCapability.streamResolution,
    MusicSourceCapability.libraryBrowse,
    MusicSourceCapability.playlists,
    MusicSourceCapability.playlistMutation,
    MusicSourceCapability.favoriteMutation,
    MusicSourceCapability.albumFavoriteMutation,
    MusicSourceCapability.artistFavoriteMutation,
    MusicSourceCapability.artwork,
    MusicSourceCapability.directPlayback,
    MusicSourceCapability.offlineCache,
    MusicSourceCapability.downloads,
    MusicSourceCapability.recommendations,
    MusicSourceCapability.authentication,
  };

  final Uri baseUri;
  final String userId;
  final String apiKey;
  final int limit;
  final JellyfinRequestLoader _requestLoader;
  final JellyfinMutationLoader _mutationLoader;
  final ProviderBinaryRequestLoader _artworkLoader;

  @override
  final String id;

  @override
  final String name;

  @override
  String get description =>
      'Jellyfin adapter for user-owned music libraries and streams.';

  @override
  Set<MusicSourceCapability> get capabilities => defaultCapabilities;

  @override
  ProviderPrivacyDisclosure get disclosure => ProviderPrivacyDisclosure(
        networkDomains: baseUri.host.isEmpty ? const <String>[] : <String>[
          baseUri.host,
        ],
        dataSent: const <String>[
          'API key credential',
          'Jellyfin user identifier',
          'audio search query',
          'audio search suggestion query',
          'artist, album, and playlist browse identifiers',
          'Home discovery list selection and result limit',
          'radio seed item identifier and result limit',
          'playlist names, membership, and track order changes',
          'favorite track changes',
          'favorite album changes',
          'favorite artist changes',
          'audio item stream identifier',
          'cover art item identifier',
        ],
        requiresUserCredentials: true,
        cachesMetadata: true,
        cachesMedia: true,
        supportsDownloads: true,
      );

  @override
  Future<List<Track>> search(String query) {
    return searchAudio(query);
  }

  Future<List<Track>> searchAudio(String query) async {
    final page = await searchPage(query, limit: limit);
    return page.tracks;
  }

  @override
  Future<List<MusicSourceSearchSuggestion>> suggest(
    String query, {
    int limit = 8,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <MusicSourceSearchSuggestion>[];
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
    }
    return _guardRequest(() async {
      return parseJellyfinSearchHintsResponse(
        await _requestLoader(
          _searchHintsUri(normalizedQuery, limit: limit.clamp(1, 50)),
        ),
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
    final offset = _jellyfinSearchOffset(cursor);
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const MusicSourceSearchPage(tracks: <Track>[]);
    }
    final boundedLimit = limit.clamp(1, 500);
    return _guardRequest(() async {
      return parseJellyfinSearchPageResponse(
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
      parseJellyfinItemsResponse(
        await _requestLoader(
          _requestUri(
            '/Users/$userId/Items',
            const <String, String>{
              'Recursive': 'true',
              'IncludeItemTypes': 'Audio',
              'Limit': '1',
            },
          ),
        ),
      );
    });
  }

  @override
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  ) {
    return _guardRequest(() async {
      final uri = switch (kind) {
        MusicCatalogCollectionKind.artist => _requestUri(
            '/Artists',
            <String, String>{
              'UserId': userId,
              'IncludeItemTypes': 'Audio',
              'SortBy': 'SortName',
              'SortOrder': 'Ascending',
              'Fields': 'Genres,RecursiveItemCount',
              'EnableImages': 'true',
              'EnableImageTypes': 'Primary',
              'ImageTypeLimit': '1',
              'EnableUserData': 'true',
              'Limit': '500',
            },
          ),
        MusicCatalogCollectionKind.album => _itemsUri(
            itemType: 'MusicAlbum',
          ),
        MusicCatalogCollectionKind.playlist => _itemsUri(
            itemType: 'Playlist',
          ),
      };
      return parseJellyfinCollectionsResponse(
        await _requestLoader(uri),
        kind,
      );
    });
  }

  @override
  Set<MusicCatalogCollectionKind> get pagedCollectionKinds =>
      const <MusicCatalogCollectionKind>{
        MusicCatalogCollectionKind.artist,
        MusicCatalogCollectionKind.album,
        MusicCatalogCollectionKind.playlist,
      };

  @override
  Future<MusicCatalogCollectionPage> browseCollectionsPage(
    MusicCatalogCollectionKind kind, {
    int offset = 0,
    int limit = 100,
  }) {
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
      final pageParameters = <String, String>{
        'StartIndex': offset.toString(),
        'Limit': boundedLimit.toString(),
        'EnableTotalRecordCount': 'true',
      };
      final uri = switch (kind) {
        MusicCatalogCollectionKind.artist => _requestUri(
            '/Artists',
            <String, String>{
              'UserId': userId,
              'IncludeItemTypes': 'Audio',
              'SortBy': 'SortName',
              'SortOrder': 'Ascending',
              'Fields': 'Genres,RecursiveItemCount',
              'EnableImages': 'true',
              'EnableImageTypes': 'Primary',
              'ImageTypeLimit': '1',
              ...pageParameters,
            },
          ),
        MusicCatalogCollectionKind.album => _itemsUri(
            itemType: 'MusicAlbum',
            extra: pageParameters,
          ),
        MusicCatalogCollectionKind.playlist => _itemsUri(
            itemType: 'Playlist',
            extra: pageParameters,
          ),
      };
      return parseJellyfinCollectionPageResponse(
        await _requestLoader(uri),
        kind,
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
      const <MusicCatalogDiscoveryKind>{
        MusicCatalogDiscoveryKind.frequentlyPlayed,
        MusicCatalogDiscoveryKind.recentlyPlayed,
        MusicCatalogDiscoveryKind.random,
        MusicCatalogDiscoveryKind.favorites,
      };

  @override
  Future<List<MusicCatalogCollection>> browseDiscoveryCollections(
    MusicCatalogDiscoveryKind kind, {
    int limit = 6,
  }) async {
    if (!discoveryKinds.contains(kind)) {
      return Future<List<MusicCatalogCollection>>.error(
        UnsupportedError('Jellyfin discovery kind is not supported.'),
      );
    }
    if (pagedDiscoveryKinds.contains(kind)) {
      return (await browseDiscoveryCollectionsPage(kind, limit: limit))
          .collections;
    }
    final boundedLimit = limit.clamp(1, 50);
    return _guardRequest(() async => parseJellyfinLatestCollectionsResponse(
        await _requestLoader(
          _requestUri(
            '/Items/Latest',
            <String, String>{
              'userId': userId,
              'includeItemTypes': 'MusicAlbum',
              'fields': 'Genres,RecursiveItemCount,ChildCount',
              'enableImages': 'true',
              'enableImageTypes': 'Primary',
              'imageTypeLimit': '1',
              'limit': boundedLimit.toString(),
              'groupItems': 'false',
            },
          ),
        ),
      ));
  }

  @override
  Future<MusicCatalogCollectionPage> browseDiscoveryCollectionsPage(
    MusicCatalogDiscoveryKind kind, {
    int offset = 0,
    int limit = 6,
  }) {
    if (!pagedDiscoveryKinds.contains(kind)) {
      return Future<MusicCatalogCollectionPage>.error(
        UnsupportedError('Jellyfin discovery kind is not pageable.'),
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
    final boundedLimit = limit.clamp(1, 50);
    return _guardRequest(() async => parseJellyfinCollectionPageResponse(
          await _requestLoader(
            _itemsUri(
              itemType: 'MusicAlbum',
              extra: <String, String>{
                'StartIndex': offset.toString(),
                'Limit': boundedLimit.toString(),
                'EnableTotalRecordCount': 'true',
                'SortBy': switch (kind) {
                  MusicCatalogDiscoveryKind.frequentlyPlayed => 'PlayCount',
                  MusicCatalogDiscoveryKind.recentlyPlayed => 'DatePlayed',
                  MusicCatalogDiscoveryKind.random => 'Random',
                  MusicCatalogDiscoveryKind.favorites => 'SortName',
                  MusicCatalogDiscoveryKind.recentlyAdded => 'DateCreated',
                },
                'SortOrder': 'Descending',
                if (kind == MusicCatalogDiscoveryKind.frequentlyPlayed ||
                    kind == MusicCatalogDiscoveryKind.recentlyPlayed)
                  'IsPlayed': 'true',
                if (kind == MusicCatalogDiscoveryKind.favorites)
                  'IsFavorite': 'true',
              },
            ),
          ),
          MusicCatalogCollectionKind.album,
          requestOffset: offset,
          requestLimit: boundedLimit,
        ));
  }

  @override
  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  ) {
    return _guardRequest(() async {
      switch (collection.kind) {
        case MusicCatalogCollectionKind.artist:
          final albums = parseJellyfinCollectionsResponse(
            await _requestLoader(
              _itemsUri(
                itemType: 'MusicAlbum',
                extra: <String, String>{'ArtistIds': collection.id},
              ),
            ),
            MusicCatalogCollectionKind.album,
          );
          return MusicCatalogDetail(
            collection: collection,
            collections: albums,
          );
        case MusicCatalogCollectionKind.album:
          final tracks = parseJellyfinItemsResponse(
            await _requestLoader(
              _itemsUri(
                itemType: 'Audio',
                extra: <String, String>{'ParentId': collection.id},
              ),
            ),
          ).map((item) => item.toTrack(sourceId: id)).toList(growable: false);
          return MusicCatalogDetail(
            collection: collection,
            tracks: tracks,
          );
        case MusicCatalogCollectionKind.playlist:
          final tracks = parseJellyfinItemsResponse(
            await _requestLoader(
              _requestUri(
                '/Playlists/${collection.id}/Items',
                <String, String>{
                  'UserId': userId,
                  'Fields': 'Genres,MediaSources',
                  'EnableImages': 'true',
                  'EnableImageTypes': 'Primary',
                  'ImageTypeLimit': '1',
                  'Limit': '500',
                },
              ),
            ),
          ).map((item) => item.toTrack(sourceId: id)).toList(growable: false);
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
        UnsupportedError('Jellyfin radio seed kind is not supported.'),
      );
    }
    if (limit <= 0) {
      return Future<List<Track>>.error(
        ArgumentError.value(limit, 'limit', 'Limit must be positive.'),
      );
    }
    final boundedLimit = limit.clamp(1, 500);
    final endpoint = switch (seed.kind) {
      MusicCatalogRadioSeedKind.track => '/Songs/$normalizedId/InstantMix',
      MusicCatalogRadioSeedKind.artist => '/Artists/$normalizedId/InstantMix',
      MusicCatalogRadioSeedKind.album => '/Albums/$normalizedId/InstantMix',
    };
    return _guardRequest(() async {
      return parseJellyfinItemsResponse(
        await _requestLoader(
          _requestUri(
            endpoint,
            <String, String>{
              'userId': userId,
              'limit': boundedLimit.toString(),
              'fields': 'Genres',
              'enableImages': 'true',
              'enableImageTypes': 'Primary',
              'imageTypeLimit': '1',
            },
          ),
        ),
      ).map((item) => item.toTrack(sourceId: id)).toList(growable: false);
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
        _artworkUri(
          normalizedId,
          version: version,
          maxWidth: maxWidth,
        ),
        <String, String>{'X-Emby-Token': apiKey},
      ),
    );
  }

  @override
  Future<void> createPlaylist(
    String name, {
    List<String> trackIds = const <String>[],
  }) {
    final normalizedName = _requiredPlaylistName(name);
    final normalizedTrackIds = _playlistTrackIds(trackIds);
    return _guardRequest(
      () => _mutationLoader(
        _requestUri('/Playlists'),
        'POST',
        <String, Object?>{
          'Name': normalizedName,
          'Ids': normalizedTrackIds,
          'UserId': userId,
          'MediaType': 'Audio',
        },
      ),
    );
  }

  @override
  Future<void> renamePlaylist(String playlistId, String name) {
    final normalizedPlaylistId = _requiredPlaylistId(playlistId);
    final normalizedName = _requiredPlaylistName(name);
    return _guardRequest(
      () => _mutationLoader(
        _requestUri('/Playlists/$normalizedPlaylistId'),
        'POST',
        <String, Object?>{'Name': normalizedName},
      ),
    );
  }

  @override
  Future<void> deletePlaylist(String playlistId) {
    final normalizedPlaylistId = _requiredPlaylistId(playlistId);
    return _guardRequest(
      () => _mutationLoader(
        _requestUri('/Items/$normalizedPlaylistId'),
        'DELETE',
        null,
      ),
    );
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
    await _guardRequest(
      () => _mutationLoader(
        _requestUri(
          '/Playlists/$normalizedPlaylistId/Items',
          <String, String>{
            'ids': normalizedTrackIds.join(','),
            'userId': userId,
          },
        ),
        'POST',
        null,
      ),
    );
  }

  @override
  Future<void> replacePlaylistTracks(
    String playlistId,
    List<String> trackIds,
  ) {
    final normalizedPlaylistId = _requiredPlaylistId(playlistId);
    final normalizedTrackIds = _playlistTrackIds(trackIds);
    return _guardRequest(
      () => _mutationLoader(
        _requestUri('/Playlists/$normalizedPlaylistId'),
        'POST',
        <String, Object?>{'Ids': normalizedTrackIds},
      ),
    );
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

    final itemId = track.externalId;
    if (itemId == null || itemId.trim().isEmpty) {
      return null;
    }

    return streamUriFor(itemId);
  }

  Uri streamUriFor(String itemId) {
    return _requestUri(
      '/Audio/$itemId/stream',
      <String, String>{
        'static': 'true',
        'UserId': userId,
      },
    );
  }

  Uri _searchUri(
    String query, {
    required int offset,
    required int limit,
  }) {
    return _requestUri(
      '/Users/$userId/Items',
      <String, String>{
        'Recursive': 'true',
        'IncludeItemTypes': 'Audio',
        'SearchTerm': query,
        'Fields': 'Genres,MediaSources',
        'EnableImages': 'true',
        'EnableImageTypes': 'Primary',
        'ImageTypeLimit': '1',
        'StartIndex': offset.toString(),
        'Limit': limit.toString(),
        'EnableTotalRecordCount': 'true',
        'EnableUserData': 'true',
      },
    );
  }

  Uri _searchHintsUri(String query, {required int limit}) {
    return _requestUri(
      '/Search/Hints',
      <String, String>{
        'SearchTerm': query,
        'UserId': userId,
        'IncludeItemTypes': 'Audio,MusicAlbum,MusicArtist',
        'Limit': limit.toString(),
      },
    );
  }

  @override
  Future<void> setTrackFavorite(
    String trackId, {
    required bool isFavorite,
  }) {
    final normalizedTrackId = _requiredPlaylistId(trackId);
    return _guardRequest(
      () => _mutationLoader(
        _requestUri('/Users/$userId/FavoriteItems/$normalizedTrackId'),
        isFavorite ? 'POST' : 'DELETE',
        null,
      ),
    );
  }

  @override
  Future<void> setAlbumFavorite(
    String albumId, {
    required bool isFavorite,
  }) {
    final normalizedAlbumId = _requiredPlaylistId(albumId);
    return _guardRequest(
      () => _mutationLoader(
        _requestUri('/Users/$userId/FavoriteItems/$normalizedAlbumId'),
        isFavorite ? 'POST' : 'DELETE',
        null,
      ),
    );
  }

  @override
  Future<void> setArtistFavorite(String artistId, {required bool isFavorite}) {
    final normalizedArtistId = _requiredPlaylistId(artistId);
    return _guardRequest(
      () => _mutationLoader(
        _requestUri('/Users/$userId/FavoriteItems/$normalizedArtistId'),
        isFavorite ? 'POST' : 'DELETE',
        null,
      ),
    );
  }

  Uri _itemsUri({
    required String itemType,
    Map<String, String> extra = const <String, String>{},
  }) {
    return _requestUri(
      '/Users/$userId/Items',
      <String, String>{
        'Recursive': 'true',
        'IncludeItemTypes': itemType,
        'SortBy': itemType == 'Audio'
            ? 'ParentIndexNumber,IndexNumber,SortName'
            : 'SortName',
        'SortOrder': 'Ascending',
        'Fields': 'Genres,RecursiveItemCount,ChildCount',
        'EnableImages': 'true',
        'EnableImageTypes': 'Primary',
        'ImageTypeLimit': '1',
        'EnableUserData': 'true',
        'Limit': '500',
        ...extra,
      },
    );
  }

  Uri _artworkUri(
    String artworkId, {
    required String? version,
    required int maxWidth,
  }) {
    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final normalizedVersion = version?.trim() ?? '';
    return baseUri.replace(
      pathSegments: <String>[
        ...baseSegments,
        'Items',
        artworkId,
        'Images',
        'Primary',
      ],
      queryParameters: <String, String>{
        'maxWidth': maxWidth.clamp(32, 2048).toString(),
        'quality': '90',
        if (normalizedVersion.isNotEmpty) 'tag': normalizedVersion,
      },
    );
  }

  Uri _requestUri(
    String endpointPath, [
    Map<String, String> parameters = const <String, String>{},
  ]) {
    return baseUri.replace(
      path: _joinUriPath(baseUri.path, endpointPath),
      queryParameters: <String, String>{
        'api_key': apiKey,
        ...parameters,
      },
    );
  }

  Future<T> _guardRequest<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on Object catch (error) {
      throw ProviderRequestException(
        safeProviderErrorMessage(
          error,
          providerName: name,
          secrets: <String>[apiKey],
        ),
      );
    }
  }
}

final class JellyfinAudioItem {
  const JellyfinAudioItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.duration,
    required this.primaryImageTag,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final Duration duration;
  final String primaryImageTag;
  final bool isFavorite;

  bool get hasPrimaryImage => primaryImageTag.isNotEmpty;

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
      providerArtworkId: hasPrimaryImage ? id : null,
      providerArtworkVersion:
          hasPrimaryImage ? primaryImageTag : null,
      streamUrl: streamUri?.toString(),
      sourceId: sourceId,
      externalId: id,
      isFavorite: isFavorite,
    );
  }
}

List<JellyfinAudioItem> parseJellyfinItemsResponse(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Jellyfin response must be a JSON object.');
  }

  return _jsonList(decoded['Items'])
      .whereType<Map<dynamic, dynamic>>()
      .map((item) => _audioItemFromJson(item.cast<String, Object?>()))
      .whereType<JellyfinAudioItem>()
      .toList(growable: false);
}

MusicSourceSearchPage parseJellyfinSearchPageResponse(
  String jsonText, {
  required String sourceId,
  required int requestOffset,
  required int requestLimit,
}) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Jellyfin response must be a JSON object.');
  }

  final rawItems = _jsonList(decoded['Items']);
  final tracks = rawItems
      .whereType<Map<dynamic, dynamic>>()
      .map((item) => _audioItemFromJson(item.cast<String, Object?>()))
      .whereType<JellyfinAudioItem>()
      .map((item) => item.toTrack(sourceId: sourceId))
      .toList(growable: false);
  final reportedStart = _optionalNonNegativeInt(decoded['StartIndex']);
  final startIndex = reportedStart == null || reportedStart < requestOffset
      ? requestOffset
      : reportedStart;
  final totalCount = _optionalNonNegativeInt(decoded['TotalRecordCount']);
  final nextOffset = startIndex + rawItems.length;
  final hasMore = rawItems.isNotEmpty &&
      (totalCount == null
          ? rawItems.length >= requestLimit
          : nextOffset < totalCount);
  return MusicSourceSearchPage(
    tracks: List<Track>.unmodifiable(tracks),
    nextCursor: hasMore ? nextOffset.toString() : null,
    totalCount: totalCount,
  );
}

List<MusicSourceSearchSuggestion> parseJellyfinSearchHintsResponse(
  String jsonText,
) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Jellyfin response must be a JSON object.');
  }
  final values = <String, MusicSourceSearchSuggestion>{};
  for (final rawHint in _jsonList(decoded['SearchHints'])) {
    if (rawHint is! Map<dynamic, dynamic>) {
      continue;
    }
    final hint = rawHint.cast<String, Object?>();
    final value = (hint['Name'] as String? ?? '').trim();
    if (value.isEmpty) {
      continue;
    }
    final type = hint['Type'] as String? ?? '';
    final kind = switch (type) {
      'MusicArtist' => MusicSourceSearchSuggestionKind.artist,
      'MusicAlbum' => MusicSourceSearchSuggestionKind.album,
      _ => MusicSourceSearchSuggestionKind.track,
    };
    final artists = _jsonList(hint['Artists'])
        .whereType<String>()
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .join(', ');
    final album = (hint['Album'] as String? ?? '').trim();
    final subtitle = switch (kind) {
      MusicSourceSearchSuggestionKind.track => artists.isNotEmpty
          ? artists
          : album.isEmpty
          ? null
          : album,
      MusicSourceSearchSuggestionKind.album => artists.isEmpty
          ? null
          : artists,
      MusicSourceSearchSuggestionKind.artist => null,
    };
    values.putIfAbsent(
      value.toLowerCase(),
      () => MusicSourceSearchSuggestion(
        value: value,
        kind: kind,
        subtitle: subtitle,
      ),
    );
  }
  return List<MusicSourceSearchSuggestion>.unmodifiable(values.values);
}

List<MusicCatalogCollection> parseJellyfinCollectionsResponse(
  String jsonText,
  MusicCatalogCollectionKind kind,
) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Jellyfin response must be a JSON object.');
  }

  return _jsonList(decoded['Items'])
      .whereType<Map<dynamic, dynamic>>()
      .map((item) => item.cast<String, Object?>())
      .map((item) => _jellyfinCollection(item, kind))
      .whereType<MusicCatalogCollection>()
      .toList(growable: false);
}

MusicCatalogCollectionPage parseJellyfinCollectionPageResponse(
  String jsonText,
  MusicCatalogCollectionKind kind, {
  required int requestOffset,
  required int requestLimit,
}) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Jellyfin response must be a JSON object.');
  }

  final rawItems = _jsonList(decoded['Items']);
  final collections = rawItems
      .whereType<Map<dynamic, dynamic>>()
      .map((item) => item.cast<String, Object?>())
      .map((item) => _jellyfinCollection(item, kind))
      .whereType<MusicCatalogCollection>()
      .toList(growable: false);
  final reportedStart = _optionalNonNegativeInt(decoded['StartIndex']);
  final startIndex = reportedStart == null || reportedStart < requestOffset
      ? requestOffset
      : reportedStart;
  final totalCount = _optionalNonNegativeInt(decoded['TotalRecordCount']);
  final nextOffset = startIndex + rawItems.length;
  final hasMore = rawItems.isNotEmpty &&
      (totalCount == null
          ? rawItems.length >= requestLimit
          : nextOffset < totalCount);
  return MusicCatalogCollectionPage(
    collections: List<MusicCatalogCollection>.unmodifiable(collections),
    nextOffset: nextOffset,
    hasMore: hasMore,
    totalCount: totalCount,
  );
}

List<MusicCatalogCollection> parseJellyfinLatestCollectionsResponse(
  String jsonText,
) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! List<dynamic>) {
    throw const FormatException(
      'Jellyfin latest media response must be a JSON array.',
    );
  }

  return decoded
      .whereType<Map<dynamic, dynamic>>()
      .map((item) => item.cast<String, Object?>())
      .map(
        (item) => _jellyfinCollection(
          item,
          MusicCatalogCollectionKind.album,
        ),
      )
      .whereType<MusicCatalogCollection>()
      .toList(growable: false);
}

MusicCatalogCollection? _jellyfinCollection(
  Map<String, Object?> json,
  MusicCatalogCollectionKind kind,
) {
  final id = _stringValue(json['Id']);
  if (id.isEmpty) {
    return null;
  }
  final title = _stringValue(json['Name']);
  final artist = _artistName(json);
  final year = _intValue(json['ProductionYear']);
  final itemCount = _intValue(
    json['RecursiveItemCount'] ?? json['ChildCount'],
  );
  final primaryImageTag = _primaryImageTag(json);
  final subtitleParts = <String>[
    if (kind == MusicCatalogCollectionKind.album && artist.isNotEmpty) artist,
    if (kind == MusicCatalogCollectionKind.album && year > 0) year.toString(),
    if (itemCount > 0)
      kind == MusicCatalogCollectionKind.artist
          ? '$itemCount track(s)'
          : '$itemCount item(s)',
  ];
  return MusicCatalogCollection(
    id: id,
    title: title.isEmpty ? id : title,
    kind: kind,
    subtitle: subtitleParts.join(' · '),
    itemCount: itemCount,
    isFavorite: _jellyfinIsFavorite(json),
    artworkId: primaryImageTag.isEmpty ? null : id,
    artworkVersion: primaryImageTag.isEmpty ? null : primaryImageTag,
  );
}

JellyfinAudioItem? _audioItemFromJson(Map<String, Object?> json) {
  final id = _stringValue(json['Id']);
  if (id.isEmpty) {
    return null;
  }

  return JellyfinAudioItem(
    id: id,
    title: _stringValue(json['Name']),
    artist: _artistName(json),
    album: _stringValue(json['Album']),
    genre: _firstString(json['Genres']),
    duration: _durationFromTicks(json['RunTimeTicks']),
    primaryImageTag: _primaryImageTag(json),
    isFavorite: _jellyfinIsFavorite(json),
  );
}

bool _jellyfinIsFavorite(Map<String, Object?> json) {
  final userData = json['UserData'];
  return userData is Map<dynamic, dynamic> && userData['IsFavorite'] == true;
}

Future<String> _loadJellyfinJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderRequestException(
        'Jellyfin request failed with HTTP ${response.statusCode}.',
      );
    }

    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}

Future<void> _loadJellyfinMutation(
  Uri uri,
  String method,
  Map<String, Object?>? jsonBody,
) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    if (jsonBody != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(jsonBody)));
    }
    final response = await request.close();
    final statusCode = response.statusCode;
    await response.drain<void>();
    if (statusCode < 200 || statusCode >= 300) {
      throw ProviderRequestException(
        'Jellyfin request failed with HTTP $statusCode.',
      );
    }
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

String _artistName(Map<String, Object?> json) {
  final artists = _stringList(json['Artists']);
  if (artists.isNotEmpty) {
    return artists.join(', ');
  }

  final artistItems = _jsonList(json['ArtistItems'])
      .whereType<Map<dynamic, dynamic>>()
      .map((item) => _stringValue(item['Name']))
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
  if (artistItems.isNotEmpty) {
    return artistItems.join(', ');
  }

  return _stringValue(json['AlbumArtist']);
}

String _primaryImageTag(Map<String, Object?> json) {
  final imageTags = json['ImageTags'];
  if (imageTags is Map<dynamic, dynamic>) {
    return _stringValue(imageTags['Primary']);
  }

  return '';
}

Duration _durationFromTicks(Object? value) {
  final ticks = _intValue(value);
  if (ticks <= 0) {
    return Duration.zero;
  }

  return Duration(milliseconds: (ticks / 10000).round());
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

List<String> _stringList(Object? value) {
  return _jsonList(value)
      .map(_stringValue)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _firstString(Object? value) {
  final values = _stringList(value);
  return values.isEmpty ? '' : values.first;
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

int? _optionalNonNegativeInt(Object? value) {
  if (value == null) {
    return null;
  }
  final parsed = _intValue(value);
  return parsed < 0 ? null : parsed;
}

int _jellyfinSearchOffset(String? cursor) {
  if (cursor == null) {
    return 0;
  }
  final offset = int.tryParse(cursor);
  if (offset == null || offset < 0) {
    throw ArgumentError.value(cursor, 'cursor', 'Invalid search cursor.');
  }
  return offset;
}
