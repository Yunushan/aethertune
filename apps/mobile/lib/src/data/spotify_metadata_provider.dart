import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef SpotifyAccessTokenReader = Future<String> Function();
typedef SpotifySearchLoader = Future<String> Function(Uri uri, String token);

enum SpotifyTopTracksTimeRange { shortTerm, mediumTerm, longTerm }

extension on SpotifyTopTracksTimeRange {
  String get apiValue => switch (this) {
    SpotifyTopTracksTimeRange.shortTerm => 'short_term',
    SpotifyTopTracksTimeRange.mediumTerm => 'medium_term',
    SpotifyTopTracksTimeRange.longTerm => 'long_term',
  };
}

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
    Uri? savedEpisodesUri,
    SpotifySearchLoader? savedEpisodesLoader,
    Uri? savedAlbumsUri,
    SpotifySearchLoader? savedAlbumsLoader,
    Uri? recentlyPlayedUri,
    SpotifySearchLoader? recentlyPlayedLoader,
    Uri? topTracksUri,
    SpotifySearchLoader? topTracksLoader,
    Uri? topArtistsUri,
    SpotifySearchLoader? topArtistsLoader,
    Uri? followedArtistsUri,
    SpotifySearchLoader? followedArtistsLoader,
    Uri? newReleasesUri,
    SpotifySearchLoader? newReleasesLoader,
    Uri? albumsUri,
    SpotifySearchLoader? albumTracksLoader,
    Uri? playlistsUri,
    SpotifySearchLoader? playlistsLoader,
    Uri? playlistBaseUri,
    SpotifySearchLoader? playlistItemsLoader,
  }) : _accessTokenReader = accessTokenReader,
       searchUri = searchUri ?? _defaultSearchUri,
       _searchLoader = searchLoader ?? _loadSpotifyJson,
       savedTracksUri = savedTracksUri ?? _defaultSavedTracksUri,
       _savedTracksLoader = savedTracksLoader ?? _loadSpotifyJson,
       savedEpisodesUri = savedEpisodesUri ?? _defaultSavedEpisodesUri,
       _savedEpisodesLoader = savedEpisodesLoader ?? _loadSpotifyJson,
       savedAlbumsUri = savedAlbumsUri ?? _defaultSavedAlbumsUri,
       _savedAlbumsLoader = savedAlbumsLoader ?? _loadSpotifyJson,
       recentlyPlayedUri = recentlyPlayedUri ?? _defaultRecentlyPlayedUri,
       _recentlyPlayedLoader = recentlyPlayedLoader ?? _loadSpotifyJson,
       topTracksUri = topTracksUri ?? _defaultTopTracksUri,
       _topTracksLoader = topTracksLoader ?? _loadSpotifyJson,
       topArtistsUri = topArtistsUri ?? _defaultTopArtistsUri,
       _topArtistsLoader = topArtistsLoader ?? _loadSpotifyJson,
       followedArtistsUri = followedArtistsUri ?? _defaultFollowedArtistsUri,
       _followedArtistsLoader = followedArtistsLoader ?? _loadSpotifyJson,
       newReleasesUri = newReleasesUri ?? _defaultNewReleasesUri,
       _newReleasesLoader = newReleasesLoader ?? _loadSpotifyJson,
       albumsUri = albumsUri ?? _defaultAlbumsUri,
       _albumTracksLoader = albumTracksLoader ?? _loadSpotifyJson,
       playlistsUri = playlistsUri ?? _defaultPlaylistsUri,
       _playlistsLoader = playlistsLoader ?? _loadSpotifyJson,
       playlistBaseUri = playlistBaseUri ?? _defaultPlaylistBaseUri,
       _playlistItemsLoader = playlistItemsLoader ?? _loadSpotifyJson;

  static final Uri _defaultSearchUri =
      Uri.parse('https://api.spotify.com/v1/search');
  static final Uri _defaultSavedTracksUri =
      Uri.parse('https://api.spotify.com/v1/me/tracks');
  static final Uri _defaultSavedEpisodesUri =
      Uri.parse('https://api.spotify.com/v1/me/episodes');
  static final Uri _defaultSavedAlbumsUri =
      Uri.parse('https://api.spotify.com/v1/me/albums');
  static final Uri _defaultRecentlyPlayedUri =
      Uri.parse('https://api.spotify.com/v1/me/player/recently-played');
  static final Uri _defaultTopTracksUri =
      Uri.parse('https://api.spotify.com/v1/me/top/tracks');
  static final Uri _defaultTopArtistsUri =
      Uri.parse('https://api.spotify.com/v1/me/top/artists');
  static final Uri _defaultFollowedArtistsUri =
      Uri.parse('https://api.spotify.com/v1/me/following');
  static final Uri _defaultNewReleasesUri =
      Uri.parse('https://api.spotify.com/v1/browse/new-releases');
  static final Uri _defaultAlbumsUri =
      Uri.parse('https://api.spotify.com/v1/albums');
  static final Uri _defaultPlaylistsUri =
      Uri.parse('https://api.spotify.com/v1/me/playlists');
  static final Uri _defaultPlaylistBaseUri =
      Uri.parse('https://api.spotify.com/v1/playlists');

  final SpotifyAccessTokenReader _accessTokenReader;
  final Uri searchUri;
  final SpotifySearchLoader _searchLoader;
  final Uri savedTracksUri;
  final SpotifySearchLoader _savedTracksLoader;
  final Uri savedEpisodesUri;
  final SpotifySearchLoader _savedEpisodesLoader;
  final Uri savedAlbumsUri;
  final SpotifySearchLoader _savedAlbumsLoader;
  final Uri recentlyPlayedUri;
  final SpotifySearchLoader _recentlyPlayedLoader;
  final Uri topTracksUri;
  final SpotifySearchLoader _topTracksLoader;
  final Uri topArtistsUri;
  final SpotifySearchLoader _topArtistsLoader;
  final Uri followedArtistsUri;
  final SpotifySearchLoader _followedArtistsLoader;
  final Uri newReleasesUri;
  final SpotifySearchLoader _newReleasesLoader;
  final Uri albumsUri;
  final SpotifySearchLoader _albumTracksLoader;
  final Uri playlistsUri;
  final SpotifySearchLoader _playlistsLoader;
  final Uri playlistBaseUri;
  final SpotifySearchLoader _playlistItemsLoader;

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

  /// Reads saved album metadata through the user's official Spotify library.
  Future<SpotifySavedAlbumsPage> loadSavedAlbumsPage({
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final token = await _accessTokenReader();
    return parseSpotifySavedAlbumsPage(
      await _savedAlbumsLoader(
        savedAlbumsUri.replace(
          queryParameters: <String, String>{
            'limit': limit.clamp(1, 50).toString(),
            'offset': offset.toString(),
          },
        ),
        token,
      ),
    );
  }

  /// Reads the user's official Spotify play history as catalog metadata only.
  /// Returned tracks intentionally do not contain a stream URL.
  Future<SpotifyRecentlyPlayedPage> loadRecentlyPlayedPage({
    String? before,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalizedBefore = _nonEmpty(before);
    final token = await _accessTokenReader();
    return parseSpotifyRecentlyPlayedPage(
      await _recentlyPlayedLoader(
        recentlyPlayedUri.replace(
          queryParameters: <String, String>{
            'limit': limit.clamp(1, 50).toString(),
            if (normalizedBefore != null) 'before': normalizedBefore,
          },
        ),
        token,
      ),
    );
  }

  /// Reads the user's official Spotify top-track metadata without playback.
  Future<SpotifySavedTracksPage> loadTopTracksPage({
    int offset = 0,
    int limit = 20,
    SpotifyTopTracksTimeRange timeRange = SpotifyTopTracksTimeRange.mediumTerm,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final token = await _accessTokenReader();
    return parseSpotifyTopTracksPage(
      await _topTracksLoader(
        topTracksUri.replace(
          queryParameters: <String, String>{
            'time_range': timeRange.apiValue,
            'limit': limit.clamp(1, 50).toString(),
            'offset': offset.toString(),
          },
        ),
        token,
      ),
    );
  }

  Future<List<SpotifyTopArtist>> loadTopArtists({
    SpotifyTopTracksTimeRange timeRange = SpotifyTopTracksTimeRange.mediumTerm,
    int limit = 50,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final token = await _accessTokenReader();
    return parseSpotifyTopArtists(
      await _topArtistsLoader(
        topArtistsUri.replace(
          queryParameters: <String, String>{
            'time_range': timeRange.apiValue,
            'limit': limit.clamp(1, 50).toString(),
          },
        ),
        token,
      ),
    );
  }

  /// Reads followed Spotify artist metadata without changing remote follows.
  Future<SpotifyFollowedArtistsPage> loadFollowedArtistsPage({
    String? after,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalizedAfter = after == null ? null : _nonEmpty(after);
    if (after != null && normalizedAfter == null) {
      throw ArgumentError.value(after, 'after', 'Must not be empty.');
    }
    final token = await _accessTokenReader();
    return parseSpotifyFollowedArtistsPage(
      await _followedArtistsLoader(
        followedArtistsUri.replace(
          queryParameters: <String, String>{
            'type': 'artist',
            'limit': limit.clamp(1, 50).toString(),
            if (normalizedAfter != null) 'after': normalizedAfter,
          },
        ),
        token,
      ),
    );
  }

  /// Reads saved Spotify episode metadata without exposing Spotify playback.
  Future<SpotifySavedTracksPage> loadSavedEpisodesPage({
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final token = await _accessTokenReader();
    return parseSpotifySavedEpisodesPage(
      await _savedEpisodesLoader(
        savedEpisodesUri.replace(
          queryParameters: <String, String>{
            'limit': limit.clamp(1, 50).toString(),
            'offset': offset.toString(),
          },
        ),
        token,
      ),
    );
  }

  /// Reads official Spotify new-release album metadata without playback.
  Future<SpotifySavedAlbumsPage> loadNewReleasesPage({
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final token = await _accessTokenReader();
    return parseSpotifyNewReleasesPage(
      await _newReleasesLoader(
        newReleasesUri.replace(
          queryParameters: <String, String>{
            'limit': limit.clamp(1, 50).toString(),
            'offset': offset.toString(),
          },
        ),
        token,
      ),
    );
  }

  /// Reads the catalog metadata for tracks in a saved Spotify album.
  Future<SpotifyAlbumTracksPage> loadAlbumTracksPage(
    SpotifySavedAlbum album, {
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final albumId = _nonEmpty(album.id);
    if (albumId == null) {
      throw ArgumentError.value(album.id, 'album.id', 'Must not be empty.');
    }
    final token = await _accessTokenReader();
    final path = '${albumsUri.path}/${Uri.encodeComponent(albumId)}/tracks';
    return parseSpotifyAlbumTracksPage(
      await _albumTracksLoader(
        albumsUri.replace(
          path: path,
          queryParameters: <String, String>{
            'limit': limit.clamp(1, 50).toString(),
            'offset': offset.toString(),
          },
        ),
        token,
      ),
      album,
    );
  }

  /// Reads user playlist metadata after explicit read-only authorization.
  Future<SpotifySavedPlaylistsPage> loadSavedPlaylistsPage({
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final token = await _accessTokenReader();
    return parseSpotifySavedPlaylistsPage(
      await _playlistsLoader(
        playlistsUri.replace(
          queryParameters: <String, String>{
            'limit': limit.clamp(1, 50).toString(),
            'offset': offset.toString(),
          },
        ),
        token,
      ),
    );
  }

  /// Reads track metadata from an authorized Spotify playlist without playing it.
  Future<SpotifyPlaylistTracksPage> loadPlaylistTracksPage(
    SpotifySavedPlaylist playlist, {
    int offset = 0,
    int limit = 20,
  }) async {
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'Must not be negative.');
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final playlistId = _nonEmpty(playlist.id);
    if (playlistId == null) {
      throw ArgumentError.value(
        playlist.id,
        'playlist.id',
        'Must not be empty.',
      );
    }
    final token = await _accessTokenReader();
    final path =
        '${playlistBaseUri.path}/${Uri.encodeComponent(playlistId)}/items';
    return parseSpotifyPlaylistTracksPage(
      await _playlistItemsLoader(
        playlistBaseUri.replace(
          path: path,
          queryParameters: <String, String>{
            'limit': limit.clamp(1, 50).toString(),
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

final class SpotifySavedAlbum {
  const SpotifySavedAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.totalTracks,
    required this.addedAt,
    this.artworkUri,
  });

  final String id;
  final String title;
  final String artist;
  final int totalTracks;
  final DateTime addedAt;
  final Uri? artworkUri;
}

final class SpotifySavedAlbumsPage {
  const SpotifySavedAlbumsPage({
    required this.albums,
    required this.offset,
    required this.total,
    required this.hasMore,
  });

  final List<SpotifySavedAlbum> albums;
  final int offset;
  final int total;
  final bool hasMore;
}

final class SpotifyTopArtist {
  const SpotifyTopArtist({required this.id, required this.name, this.artworkUri});

  final String id;
  final String name;
  final Uri? artworkUri;
}

final class SpotifyFollowedArtistsPage {
  const SpotifyFollowedArtistsPage({
    required this.artists,
    required this.total,
    required this.hasMore,
    this.nextAfter,
  });

  final List<SpotifyTopArtist> artists;
  final int total;
  final bool hasMore;
  final String? nextAfter;
}

final class SpotifyRecentlyPlayedItem {
  const SpotifyRecentlyPlayedItem({
    required this.track,
    required this.playedAt,
  });

  final Track track;
  final DateTime playedAt;
}

final class SpotifyRecentlyPlayedPage {
  const SpotifyRecentlyPlayedPage({
    required this.items,
    this.nextBefore,
  });

  final List<SpotifyRecentlyPlayedItem> items;
  final String? nextBefore;

  bool get hasMore => nextBefore != null;
}

final class SpotifyAlbumTracksPage {
  const SpotifyAlbumTracksPage({
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

final class SpotifySavedPlaylist {
  const SpotifySavedPlaylist({
    required this.id,
    required this.title,
    required this.ownerName,
    required this.totalTracks,
    this.description,
    this.artworkUri,
  });

  final String id;
  final String title;
  final String ownerName;
  final int totalTracks;
  final String? description;
  final Uri? artworkUri;
}

final class SpotifySavedPlaylistsPage {
  const SpotifySavedPlaylistsPage({
    required this.playlists,
    required this.offset,
    required this.total,
    required this.hasMore,
  });

  final List<SpotifySavedPlaylist> playlists;
  final int offset;
  final int total;
  final bool hasMore;
}

final class SpotifyPlaylistTracksPage {
  const SpotifyPlaylistTracksPage({
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

SpotifySavedAlbumsPage parseSpotifySavedAlbumsPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify saved albums response must be a map.');
  }
  final root = Map<String, Object?>.from(decoded);
  final items = root['items'];
  final albums = items is List
      ? items
            .whereType<Map>()
            .map((item) => _savedAlbumFromSpotifyJson(
                  Map<String, Object?>.from(item),
                ))
            .whereType<SpotifySavedAlbum>()
            .toList(growable: false)
      : const <SpotifySavedAlbum>[];
  final offset = _nonNegativeInt(root['offset']) ?? 0;
  final total = _nonNegativeInt(root['total']) ?? 0;
  return SpotifySavedAlbumsPage(
    albums: albums,
    offset: offset,
    total: total,
    hasMore: _nonEmpty(root['next']) != null || offset + albums.length < total,
  );
}

SpotifySavedAlbumsPage parseSpotifyNewReleasesPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify new releases response must be a map.');
  }
  final albumsValue = Map<String, Object?>.from(decoded)['albums'];
  if (albumsValue is! Map) {
    throw const FormatException('Spotify new releases response is missing albums.');
  }
  final albumsJson = Map<String, Object?>.from(albumsValue);
  final items = albumsJson['items'];
  final albums = items is List
      ? items
            .whereType<Map>()
            .map((item) => _catalogAlbumFromSpotifyJson(
                  Map<String, Object?>.from(item),
                ))
            .whereType<SpotifySavedAlbum>()
            .toList(growable: false)
      : const <SpotifySavedAlbum>[];
  final offset = _nonNegativeInt(albumsJson['offset']) ?? 0;
  final total = _nonNegativeInt(albumsJson['total']) ?? 0;
  return SpotifySavedAlbumsPage(
    albums: albums,
    offset: offset,
    total: total,
    hasMore: _nonEmpty(albumsJson['next']) != null ||
        offset + albums.length < total,
  );
}

List<SpotifyTopArtist> parseSpotifyTopArtists(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify top artists response must be a map.');
  }
  return _spotifyArtistsFromJsonItems(Map<String, Object?>.from(decoded)['items']);
}

SpotifySavedTracksPage parseSpotifySavedEpisodesPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify saved episodes response must be a map.');
  }
  final root = Map<String, Object?>.from(decoded);
  final items = root['items'];
  final tracks = items is List
      ? items
            .whereType<Map>()
            .map((item) {
              final savedItem = Map<String, Object?>.from(item);
              final episode = savedItem['episode'];
              if (episode is! Map) {
                return null;
              }
              return _episodeTrackFromSpotifyJson(
                Map<String, Object?>.from(episode),
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
  return SpotifySavedTracksPage(
    tracks: tracks,
    offset: offset,
    total: total,
    hasMore: _nonEmpty(root['next']) != null || offset + tracks.length < total,
  );
}

SpotifyFollowedArtistsPage parseSpotifyFollowedArtistsPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify followed artists response must be a map.');
  }
  final artistsValue = Map<String, Object?>.from(decoded)['artists'];
  if (artistsValue is! Map) {
    throw const FormatException(
      'Spotify followed artists response is missing artists.',
    );
  }
  final artistsJson = Map<String, Object?>.from(artistsValue);
  final cursorsValue = artistsJson['cursors'];
  final cursors = cursorsValue is Map
      ? Map<String, Object?>.from(cursorsValue)
      : const <String, Object?>{};
  final nextAfter = _nonEmpty(cursors['after']);
  final artists = _spotifyArtistsFromJsonItems(artistsJson['items']);
  return SpotifyFollowedArtistsPage(
    artists: artists,
    total: _nonNegativeInt(artistsJson['total']) ?? 0,
    hasMore: _nonEmpty(artistsJson['next']) != null && nextAfter != null,
    nextAfter: nextAfter,
  );
}

List<SpotifyTopArtist> _spotifyArtistsFromJsonItems(Object? items) {
  if (items is! List) {
    return const <SpotifyTopArtist>[];
  }
  return items
      .whereType<Map>()
      .map((item) {
        final artist = Map<String, Object?>.from(item);
        final id = _nonEmpty(artist['id']);
        final name = _nonEmpty(artist['name']);
        return id == null || name == null
            ? null
            : SpotifyTopArtist(
                id: id,
                name: name,
                artworkUri: _spotifyArtworkUri(artist['images']),
              );
      })
      .whereType<SpotifyTopArtist>()
      .toList(growable: false);
}

SpotifySavedTracksPage parseSpotifyTopTracksPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify top tracks response must be a map.');
  }
  final root = Map<String, Object?>.from(decoded);
  final items = root['items'];
  final tracks = items is List
      ? items
            .whereType<Map>()
            .map((item) => _trackFromSpotifyJson(Map<String, Object?>.from(item)))
            .whereType<Track>()
            .toList(growable: false)
      : const <Track>[];
  final offset = _nonNegativeInt(root['offset']) ?? 0;
  final total = _nonNegativeInt(root['total']) ?? 0;
  return SpotifySavedTracksPage(
    tracks: tracks,
    offset: offset,
    total: total,
    hasMore: _nonEmpty(root['next']) != null || offset + tracks.length < total,
  );
}

SpotifyRecentlyPlayedPage parseSpotifyRecentlyPlayedPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException(
      'Spotify recently played response must be a map.',
    );
  }
  final root = Map<String, Object?>.from(decoded);
  final items = root['items'];
  final history = items is List
      ? items
            .whereType<Map>()
            .map((item) => _recentlyPlayedItemFromSpotifyJson(
                  Map<String, Object?>.from(item),
                ))
            .whereType<SpotifyRecentlyPlayedItem>()
            .toList(growable: false)
      : const <SpotifyRecentlyPlayedItem>[];
  final cursors = root['cursors'] is Map
      ? Map<String, Object?>.from(root['cursors'] as Map)
      : const <String, Object?>{};
  return SpotifyRecentlyPlayedPage(
    items: history,
    nextBefore: _nonEmpty(cursors['before']),
  );
}

SpotifyAlbumTracksPage parseSpotifyAlbumTracksPage(
  String jsonText,
  SpotifySavedAlbum album,
) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify album tracks response must be a map.');
  }
  final root = Map<String, Object?>.from(decoded);
  final items = root['items'];
  final tracks = items is List
      ? items
            .whereType<Map>()
            .map((item) => _trackFromSpotifyJson(
                  Map<String, Object?>.from(item),
                  albumName: album.title,
                  artworkUri: album.artworkUri,
                  addedAt: album.addedAt,
                ))
            .whereType<Track>()
            .toList(growable: false)
      : const <Track>[];
  final offset = _nonNegativeInt(root['offset']) ?? 0;
  final total = _nonNegativeInt(root['total']) ?? 0;
  return SpotifyAlbumTracksPage(
    tracks: tracks,
    offset: offset,
    total: total,
    hasMore: _nonEmpty(root['next']) != null || offset + tracks.length < total,
  );
}

SpotifySavedPlaylistsPage parseSpotifySavedPlaylistsPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify playlists response must be a map.');
  }
  final root = Map<String, Object?>.from(decoded);
  final items = root['items'];
  final playlists = items is List
      ? items
            .whereType<Map>()
            .map((item) => _savedPlaylistFromSpotifyJson(
                  Map<String, Object?>.from(item),
                ))
            .whereType<SpotifySavedPlaylist>()
            .toList(growable: false)
      : const <SpotifySavedPlaylist>[];
  final offset = _nonNegativeInt(root['offset']) ?? 0;
  final total = _nonNegativeInt(root['total']) ?? 0;
  return SpotifySavedPlaylistsPage(
    playlists: playlists,
    offset: offset,
    total: total,
    hasMore:
        _nonEmpty(root['next']) != null || offset + playlists.length < total,
  );
}

SpotifyPlaylistTracksPage parseSpotifyPlaylistTracksPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) {
    throw const FormatException('Spotify playlist items response must be a map.');
  }
  final root = Map<String, Object?>.from(decoded);
  final items = root['items'];
  final tracks = items is List
      ? items
            .whereType<Map>()
            .map((item) => _playlistTrackFromSpotifyJson(
                  Map<String, Object?>.from(item),
                ))
            .whereType<Track>()
            .toList(growable: false)
      : const <Track>[];
  final offset = _nonNegativeInt(root['offset']) ?? 0;
  final total = _nonNegativeInt(root['total']) ?? 0;
  return SpotifyPlaylistTracksPage(
    tracks: tracks,
    offset: offset,
    total: total,
    hasMore: _nonEmpty(root['next']) != null || offset + tracks.length < total,
  );
}

SpotifySavedAlbum? _savedAlbumFromSpotifyJson(Map<String, Object?> json) {
  final album = json['album'];
  if (album is! Map) {
    return null;
  }
  final albumJson = Map<String, Object?>.from(album);
  final id = _nonEmpty(albumJson['id']);
  final title = _nonEmpty(albumJson['name']);
  if (id == null || title == null) {
    return null;
  }
  return SpotifySavedAlbum(
    id: id,
    title: title,
    artist: _spotifyArtistNames(albumJson['artists']) ?? 'Unknown Artist',
    totalTracks: _nonNegativeInt(albumJson['total_tracks']) ?? 0,
    addedAt: DateTime.tryParse(json['added_at']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    artworkUri: _spotifyArtworkUri(albumJson['images']),
  );
}

SpotifySavedPlaylist? _savedPlaylistFromSpotifyJson(
  Map<String, Object?> json,
) {
  final id = _nonEmpty(json['id']);
  final title = _nonEmpty(json['name']);
  if (id == null || title == null) {
    return null;
  }
  final owner = json['owner'] is Map
      ? Map<String, Object?>.from(json['owner'] as Map)
      : const <String, Object?>{};
  final tracks = json['tracks'] is Map
      ? Map<String, Object?>.from(json['tracks'] as Map)
      : const <String, Object?>{};
  return SpotifySavedPlaylist(
    id: id,
    title: title,
    ownerName: _nonEmpty(owner['display_name']) ?? 'Spotify',
    totalTracks: _nonNegativeInt(tracks['total']) ?? 0,
    description: _nonEmpty(json['description']),
    artworkUri: _spotifyArtworkUri(json['images']),
  );
}

SpotifySavedAlbum? _catalogAlbumFromSpotifyJson(Map<String, Object?> json) {
  final id = _nonEmpty(json['id']);
  final title = _nonEmpty(json['name']);
  if (id == null || title == null) {
    return null;
  }
  return SpotifySavedAlbum(
    id: id,
    title: title,
    artist: _spotifyArtistNames(json['artists']) ?? 'Unknown Artist',
    totalTracks: _nonNegativeInt(json['total_tracks']) ?? 0,
    addedAt: DateTime.fromMillisecondsSinceEpoch(0),
    artworkUri: _spotifyArtworkUri(json['images']),
  );
}

SpotifyRecentlyPlayedItem? _recentlyPlayedItemFromSpotifyJson(
  Map<String, Object?> json,
) {
  final trackValue = json['track'];
  final playedAt = DateTime.tryParse(json['played_at']?.toString() ?? '')
      ?.toUtc();
  if (trackValue is! Map || playedAt == null) {
    return null;
  }
  final track = _trackFromSpotifyJson(
    Map<String, Object?>.from(trackValue),
    addedAt: playedAt,
  );
  return track == null
      ? null
      : SpotifyRecentlyPlayedItem(track: track, playedAt: playedAt);
}

Track? _playlistTrackFromSpotifyJson(Map<String, Object?> json) {
  final trackValue = json['item'] ?? json['track'];
  if (trackValue is! Map) {
    return null;
  }
  return _trackFromSpotifyJson(
    Map<String, Object?>.from(trackValue),
    addedAt: DateTime.tryParse(json['added_at']?.toString() ?? '')?.toUtc(),
  );
}

Track? _trackFromSpotifyJson(
  Map<String, Object?> json, {
  DateTime? addedAt,
  String? albumName,
  Uri? artworkUri,
}) {
  final id = _nonEmpty(json['id']);
  final title = _nonEmpty(json['name']);
  if (id == null || title == null) {
    return null;
  }
  final artist = _spotifyArtistNames(json['artists']) ?? '';
  final album = json['album'] is Map
      ? Map<String, Object?>.from(json['album'] as Map)
      : const <String, Object?>{};
  return Track(
    id: Track.stableLocalId('spotify-metadata|$id'),
    title: title,
    artist: artist.isEmpty ? 'Unknown Artist' : artist,
    album: albumName ?? _nonEmpty(album['name']) ?? 'Unknown Album',
    duration: Duration(milliseconds: _nonNegativeInt(json['duration_ms']) ?? 0),
    artworkUri: artworkUri ?? _spotifyArtworkUri(album['images']),
    sourceId: 'spotify-metadata',
    externalId: id,
    addedAt: addedAt,
  );
}

Track? _episodeTrackFromSpotifyJson(
  Map<String, Object?> json, {
  DateTime? addedAt,
}) {
  final id = _nonEmpty(json['id']);
  final title = _nonEmpty(json['name']);
  if (id == null || title == null) {
    return null;
  }
  final show = json['show'] is Map
      ? Map<String, Object?>.from(json['show'] as Map)
      : const <String, Object?>{};
  final showName = _nonEmpty(show['name']) ?? 'Unknown show';
  final publisher = _nonEmpty(show['publisher']) ?? 'Unknown publisher';
  return Track(
    id: Track.stableLocalId('spotify-metadata|episode|$id'),
    title: title,
    artist: publisher,
    album: showName,
    duration: Duration(milliseconds: _nonNegativeInt(json['duration_ms']) ?? 0),
    artworkUri: _spotifyArtworkUri(json['images']) ??
        _spotifyArtworkUri(show['images']),
    sourceId: 'spotify-metadata',
    externalId: 'episode:$id',
    addedAt: addedAt,
  );
}

String? _spotifyArtistNames(Object? artists) {
  if (artists is! List) {
    return null;
  }
  final names = artists
      .whereType<Map>()
      .map((item) => _nonEmpty(item['name']))
      .whereType<String>()
      .toList(growable: false);
  return names.isEmpty ? null : names.join(', ');
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
