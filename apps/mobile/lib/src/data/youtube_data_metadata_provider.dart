import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef YouTubeDataSearchLoader = Future<String> Function(Uri uri);

/// A metadata-only adapter for the documented YouTube Data API search endpoint.
///
/// This intentionally does not resolve a media URI. YouTube audiovisual content
/// must not be downloaded, cached for offline playback, or played in the
/// background through this adapter.
final class YouTubeDataMetadataProvider
    implements
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  YouTubeDataMetadataProvider({
    required String apiKey,
    Uri? searchUri,
    YouTubeDataSearchLoader? searchLoader,
    Uri? videosUri,
    YouTubeDataSearchLoader? videosLoader,
    Uri? playlistItemsUri,
    YouTubeDataSearchLoader? playlistItemsLoader,
    this.enrichSearchDurations = false,
  }) : _apiKey = _requireApiKey(apiKey),
       searchUri = searchUri ?? _defaultSearchUri,
       _searchLoader = searchLoader ?? _loadYouTubeDataJson,
       videosUri = videosUri ?? _defaultVideosUri,
       _videosLoader = videosLoader ?? _loadYouTubeDataJson,
       playlistItemsUri = playlistItemsUri ?? _defaultPlaylistItemsUri,
       _playlistItemsLoader = playlistItemsLoader ?? _loadYouTubeDataJson;

  static final Uri _defaultSearchUri = Uri.parse(
    'https://www.googleapis.com/youtube/v3/search',
  );
  static final Uri _defaultVideosUri = Uri.parse(
    'https://www.googleapis.com/youtube/v3/videos',
  );
  static final Uri _defaultPlaylistItemsUri = Uri.parse(
    'https://www.googleapis.com/youtube/v3/playlistItems',
  );

  final String _apiKey;
  final Uri searchUri;
  final YouTubeDataSearchLoader _searchLoader;
  final Uri videosUri;
  final YouTubeDataSearchLoader _videosLoader;
  final Uri playlistItemsUri;
  final YouTubeDataSearchLoader _playlistItemsLoader;
  final bool enrichSearchDurations;

  @override
  String get id => 'youtube-data-metadata';

  @override
  String get name => 'YouTube Data API';

  @override
  String get description =>
      'Official YouTube Data API video metadata search, music-chart browse, '
      'and public channel discovery. Playback, downloads, offline media, and '
      'account access are not provided.';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
    MusicSourceCapability.metadataSearch,
    MusicSourceCapability.searchSuggestions,
    MusicSourceCapability.artwork,
  };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
    networkDomains: <String>['www.googleapis.com', 'i.ytimg.com'],
    dataSent: <String>[
      'search query, selected content region, or selected video IDs',
      'configured Google Cloud API key',
    ],
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

    // Type-ahead has a smaller fixed upper bound than a submitted search.
    final page = await _searchPage(
      normalizedQuery,
      limit: limit.clamp(1, 10),
      enrichDurations: false,
    );
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
  Future<MusicSourceSearchPage> searchPage(
    String query, {
    String? cursor,
    int limit = 20,
  }) async {
    return _searchPage(
      query,
      cursor: cursor,
      limit: limit,
      enrichDurations: enrichSearchDurations,
    );
  }

  Future<MusicSourceSearchPage> _searchPage(
    String query, {
    String? cursor,
    required int limit,
    required bool enrichDurations,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const MusicSourceSearchPage(tracks: <Track>[]);
    }
    final normalizedCursor = cursor?.trim();
    final response = parseYouTubeDataSearchPage(
      await _searchLoader(
        _requestUri(
          normalizedQuery,
          cursor: normalizedCursor,
          limit: limit.clamp(1, 50),
        ),
      ),
    );
    final tracks = enrichDurations
        ? await _enrichTracksWithVideoDurations(response.tracks)
        : response.tracks;
    return MusicSourceSearchPage(
      tracks: tracks,
      nextCursor: response.nextPageToken,
      totalCount: response.totalResults,
    );
  }

  /// Searches public channel metadata using the documented `type=channel`
  /// request. This is discovery only; it does not read or change a YouTube
  /// account's subscriptions.
  Future<YouTubeDataChannelPage> searchChannelsPage(
    String query, {
    String? cursor,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const YouTubeDataChannelPage(channels: <YouTubeDataChannel>[]);
    }
    final normalizedCursor = cursor?.trim();
    return parseYouTubeDataChannelPage(
      await _searchLoader(
        _requestUri(
          normalizedQuery,
          type: 'channel',
          cursor: normalizedCursor,
          limit: limit.clamp(1, 50),
        ),
      ),
    );
  }

  /// Searches public playlist metadata through the documented
  /// `search.list?type=playlist` request.
  Future<YouTubeDataPlaylistPage> searchPlaylistsPage(
    String query, {
    String? cursor,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const YouTubeDataPlaylistPage(playlists: <YouTubeDataPlaylist>[]);
    }
    final normalizedCursor = cursor?.trim();
    return parseYouTubeDataPlaylistPage(
      await _searchLoader(
        _requestUri(
          normalizedQuery,
          type: 'playlist',
          cursor: normalizedCursor,
          limit: limit.clamp(1, 50),
        ),
      ),
    );
  }

  /// Loads metadata for items in a public YouTube playlist.
  ///
  /// Private and restricted playlists remain inaccessible through this
  /// unauthenticated, read-only adapter.
  Future<YouTubeDataPlaylistItemsPage> loadPlaylistItemsPage(
    String playlistId, {
    String? cursor,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalizedPlaylistId = playlistId.trim();
    if (normalizedPlaylistId.isEmpty) {
      throw ArgumentError.value(
        playlistId,
        'playlistId',
        'Must not be empty.',
      );
    }
    final normalizedCursor = cursor?.trim();
    return parseYouTubeDataPlaylistItemsPage(
      await _playlistItemsLoader(
        playlistItemsUri.replace(
          queryParameters: <String, String>{
            'part': 'snippet',
            'playlistId': normalizedPlaylistId,
            'maxResults': limit.clamp(1, 50).toString(),
            'key': _apiKey,
            if (normalizedCursor != null && normalizedCursor.isNotEmpty)
              'pageToken': normalizedCursor,
          },
        ),
      ),
    );
  }

  /// Loads recent public video metadata for a channel with the documented
  /// channel-filtered video search. It does not expose a stream URI.
  Future<YouTubeDataChannelVideosPage> loadChannelVideosPage(
    String channelId, {
    String? cursor,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalizedChannelId = channelId.trim();
    if (normalizedChannelId.isEmpty) {
      throw ArgumentError.value(channelId, 'channelId', 'Must not be empty.');
    }
    final normalizedCursor = cursor?.trim();
    return parseYouTubeDataChannelVideosPage(
      await _searchLoader(
        searchUri.replace(
          queryParameters: <String, String>{
            'part': 'snippet',
            'type': 'video',
            'channelId': normalizedChannelId,
            'order': 'date',
            'maxResults': limit.clamp(1, 50).toString(),
            'key': _apiKey,
            if (normalizedCursor != null && normalizedCursor.isNotEmpty)
              'pageToken': normalizedCursor,
          },
        ),
      ),
    );
  }

  /// Loads the official YouTube Music-category popular chart as metadata only.
  Future<YouTubeDataPopularPage> loadPopularMusicPage({
    String regionCode = 'US',
    String? cursor,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalizedRegion = _normalizeRegionCode(regionCode);
    final response = parseYouTubeDataPopularPage(
      await _videosLoader(
        videosUri.replace(
          queryParameters: <String, String>{
            'part': 'snippet,contentDetails',
            'chart': 'mostPopular',
            'videoCategoryId': '10',
            'regionCode': normalizedRegion,
            'maxResults': limit.clamp(1, 50).toString(),
            'key': _apiKey,
            if (cursor?.trim().isNotEmpty == true) 'pageToken': cursor!.trim(),
          },
        ),
      ),
    );
    return response;
  }

  @override
  Future<Uri?> resolveStream(Track track) async => null;

  Uri _requestUri(
    String query, {
    String type = 'video',
    String? cursor,
    required int limit,
  }) {
    return searchUri.replace(
      queryParameters: <String, String>{
        'part': 'snippet',
        'type': type,
        'q': query,
        'maxResults': limit.toString(),
        'key': _apiKey,
        if (cursor != null && cursor.isNotEmpty) 'pageToken': cursor,
      },
    );
  }

  Future<List<Track>> _enrichTracksWithVideoDurations(
    List<Track> tracks,
  ) async {
    final ids = <String>{
      for (final track in tracks)
        if (track.externalId?.trim().isNotEmpty == true) track.externalId!.trim(),
    };
    if (ids.isEmpty) {
      return tracks;
    }
    try {
      final durations = parseYouTubeDataVideoDurations(
        await _videosLoader(
          videosUri.replace(
            queryParameters: <String, String>{
              'part': 'contentDetails',
              'id': ids.join(','),
              'key': _apiKey,
            },
          ),
        ),
      );
      final enrichedTracks = <Track>[];
      for (final track in tracks) {
        final externalId = track.externalId;
        final duration = externalId == null ? null : durations[externalId];
        enrichedTracks.add(
          duration == null ? track : track.copyWith(duration: duration),
        );
      }
      return List<Track>.unmodifiable(enrichedTracks);
    } on Object {
      // Detail metadata is optional; keep the successful search page intact.
      return tracks;
    }
  }
}

final class YouTubeDataSearchPage {
  const YouTubeDataSearchPage({
    required this.tracks,
    this.nextPageToken,
    this.totalResults,
  });

  final List<Track> tracks;
  final String? nextPageToken;
  final int? totalResults;
}

final class YouTubeDataPopularPage {
  const YouTubeDataPopularPage({
    required this.tracks,
    this.nextPageToken,
    this.totalResults,
  });

  final List<Track> tracks;
  final String? nextPageToken;
  final int? totalResults;
}

final class YouTubeDataChannel {
  const YouTubeDataChannel({
    required this.id,
    required this.title,
    this.description,
    this.thumbnailUri,
  });

  final String id;
  final String title;
  final String? description;
  final Uri? thumbnailUri;
}

final class YouTubeDataChannelPage {
  const YouTubeDataChannelPage({
    required this.channels,
    this.nextPageToken,
    this.totalResults,
  });

  final List<YouTubeDataChannel> channels;
  final String? nextPageToken;
  final int? totalResults;
}

final class YouTubeDataChannelVideo {
  const YouTubeDataChannelVideo({
    required this.track,
    this.publishedAt,
  });

  final Track track;
  final DateTime? publishedAt;
}

final class YouTubeDataChannelVideosPage {
  const YouTubeDataChannelVideosPage({
    required this.videos,
    this.nextPageToken,
    this.totalResults,
  });

  final List<YouTubeDataChannelVideo> videos;
  final String? nextPageToken;
  final int? totalResults;

  List<Track> get tracks =>
      List<Track>.unmodifiable(videos.map((video) => video.track));
}

final class YouTubeDataPlaylist {
  const YouTubeDataPlaylist({
    required this.id,
    required this.title,
    this.channelTitle,
    this.description,
    this.thumbnailUri,
  });

  final String id;
  final String title;
  final String? channelTitle;
  final String? description;
  final Uri? thumbnailUri;
}

final class YouTubeDataPlaylistPage {
  const YouTubeDataPlaylistPage({
    required this.playlists,
    this.nextPageToken,
    this.totalResults,
  });

  final List<YouTubeDataPlaylist> playlists;
  final String? nextPageToken;
  final int? totalResults;
}

final class YouTubeDataPlaylistItemsPage {
  const YouTubeDataPlaylistItemsPage({
    required this.tracks,
    this.nextPageToken,
    this.totalResults,
  });

  final List<Track> tracks;
  final String? nextPageToken;
  final int? totalResults;
}

YouTubeDataSearchPage parseYouTubeDataSearchPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('YouTube Data API response must be a map.');
  }
  final json = decoded.cast<String, Object?>();
  final items = json['items'];
  final tracks = items is List<dynamic>
      ? items
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => _trackFromSearchItem(item.cast<String, Object?>()))
            .whereType<Track>()
            .toList(growable: false)
      : const <Track>[];
  return YouTubeDataSearchPage(
    tracks: tracks,
    nextPageToken: _nonEmptyString(json['nextPageToken']),
    totalResults: _nonNegativeInt(
      (json['pageInfo'] as Map<dynamic, dynamic>?)?['totalResults'],
    ),
  );
}

YouTubeDataPopularPage parseYouTubeDataPopularPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('YouTube Data API response must be a map.');
  }
  final json = decoded.cast<String, Object?>();
  final items = json['items'];
  final tracks = items is List<dynamic>
      ? items
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => _trackFromVideoItem(item.cast<String, Object?>()))
            .whereType<Track>()
            .toList(growable: false)
      : const <Track>[];
  return YouTubeDataPopularPage(
    tracks: tracks,
    nextPageToken: _nonEmptyString(json['nextPageToken']),
    totalResults: _nonNegativeInt(
      (json['pageInfo'] as Map<dynamic, dynamic>?)?['totalResults'],
    ),
  );
}

Map<String, Duration> parseYouTubeDataVideoDurations(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('YouTube video details response must be a map.');
  }
  final items = decoded['items'];
  if (items is! List<dynamic>) {
    return const <String, Duration>{};
  }
  final durations = <String, Duration>{};
  for (final item in items.whereType<Map<dynamic, dynamic>>()) {
    final id = _nonEmptyString(item['id']);
    final contentDetails = item['contentDetails'] as Map<dynamic, dynamic>?;
    final duration = parseYouTubeDataDuration(contentDetails?['duration']);
    if (id != null && duration != null) {
      durations[id] = duration;
    }
  }
  return Map<String, Duration>.unmodifiable(durations);
}

YouTubeDataChannelPage parseYouTubeDataChannelPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('YouTube Data API response must be a map.');
  }
  final json = decoded.cast<String, Object?>();
  final items = json['items'];
  final channels = items is List<dynamic>
      ? items
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => _channelFromSearchItem(item.cast<String, Object?>()))
            .whereType<YouTubeDataChannel>()
            .toList(growable: false)
      : const <YouTubeDataChannel>[];
  return YouTubeDataChannelPage(
    channels: channels,
    nextPageToken: _nonEmptyString(json['nextPageToken']),
    totalResults: _nonNegativeInt(
      (json['pageInfo'] as Map<dynamic, dynamic>?)?['totalResults'],
    ),
  );
}

YouTubeDataPlaylistPage parseYouTubeDataPlaylistPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('YouTube Data API response must be a map.');
  }
  final json = decoded.cast<String, Object?>();
  final items = json['items'];
  final playlists = items is List<dynamic>
      ? items
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => _playlistFromSearchItem(item.cast<String, Object?>()))
            .whereType<YouTubeDataPlaylist>()
            .toList(growable: false)
      : const <YouTubeDataPlaylist>[];
  return YouTubeDataPlaylistPage(
    playlists: playlists,
    nextPageToken: _nonEmptyString(json['nextPageToken']),
    totalResults: _nonNegativeInt(
      (json['pageInfo'] as Map<dynamic, dynamic>?)?['totalResults'],
    ),
  );
}

YouTubeDataChannelVideosPage parseYouTubeDataChannelVideosPage(
  String jsonText,
) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('YouTube Data API response must be a map.');
  }
  final json = decoded.cast<String, Object?>();
  final items = json['items'];
  final videos = items is List<dynamic>
      ? items
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (item) => _channelVideoFromSearchItem(
                item.cast<String, Object?>(),
              ),
            )
            .whereType<YouTubeDataChannelVideo>()
            .toList(growable: false)
      : const <YouTubeDataChannelVideo>[];
  return YouTubeDataChannelVideosPage(
    videos: videos,
    nextPageToken: _nonEmptyString(json['nextPageToken']),
    totalResults: _nonNegativeInt(
      (json['pageInfo'] as Map<dynamic, dynamic>?)?['totalResults'],
    ),
  );
}

YouTubeDataPlaylistItemsPage parseYouTubeDataPlaylistItemsPage(
  String jsonText,
) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('YouTube Data API response must be a map.');
  }
  final json = decoded.cast<String, Object?>();
  final items = json['items'];
  final tracks = items is List<dynamic>
      ? items
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => _trackFromPlaylistItem(item.cast<String, Object?>()))
            .whereType<Track>()
            .toList(growable: false)
      : const <Track>[];
  return YouTubeDataPlaylistItemsPage(
    tracks: tracks,
    nextPageToken: _nonEmptyString(json['nextPageToken']),
    totalResults: _nonNegativeInt(
      (json['pageInfo'] as Map<dynamic, dynamic>?)?['totalResults'],
    ),
  );
}

Track? _trackFromSearchItem(Map<String, Object?> json) {
  final id = json['id'] as Map<dynamic, dynamic>?;
  final videoId = _nonEmptyString(id?['videoId']);
  final snippet = json['snippet'] as Map<dynamic, dynamic>?;
  if (videoId == null || snippet == null) {
    return null;
  }
  return _trackFromVideoMetadata(videoId, snippet);
}

Track? _trackFromVideoItem(Map<String, Object?> json) {
  final videoId = _nonEmptyString(json['id']);
  final snippet = json['snippet'] as Map<dynamic, dynamic>?;
  if (videoId == null || snippet == null) {
    return null;
  }
  final contentDetails = json['contentDetails'] as Map<dynamic, dynamic>?;
  return _trackFromVideoMetadata(
    videoId,
    snippet,
    duration: parseYouTubeDataDuration(contentDetails?['duration']),
  );
}

YouTubeDataChannelVideo? _channelVideoFromSearchItem(
  Map<String, Object?> json,
) {
  final track = _trackFromSearchItem(json);
  final snippet = json['snippet'] as Map<dynamic, dynamic>?;
  if (track == null || snippet == null) {
    return null;
  }
  final publishedAt = DateTime.tryParse(
    _nonEmptyString(snippet['publishedAt']) ?? '',
  )?.toUtc();
  return YouTubeDataChannelVideo(track: track, publishedAt: publishedAt);
}

YouTubeDataChannel? _channelFromSearchItem(Map<String, Object?> json) {
  final id = json['id'] as Map<dynamic, dynamic>?;
  final channelId = _nonEmptyString(id?['channelId']);
  final snippet = json['snippet'] as Map<dynamic, dynamic>?;
  final title = _nonEmptyString(snippet?['title']);
  if (channelId == null || title == null || snippet == null) {
    return null;
  }
  return YouTubeDataChannel(
    id: channelId,
    title: title,
    description: _nonEmptyString(snippet['description']),
    thumbnailUri: _thumbnailUri(snippet['thumbnails']),
  );
}

YouTubeDataPlaylist? _playlistFromSearchItem(Map<String, Object?> json) {
  final id = json['id'] as Map<dynamic, dynamic>?;
  final playlistId = _nonEmptyString(id?['playlistId']);
  final snippet = json['snippet'] as Map<dynamic, dynamic>?;
  final title = _nonEmptyString(snippet?['title']);
  if (playlistId == null || title == null || snippet == null) {
    return null;
  }
  return YouTubeDataPlaylist(
    id: playlistId,
    title: title,
    channelTitle: _nonEmptyString(snippet['channelTitle']),
    description: _nonEmptyString(snippet['description']),
    thumbnailUri: _thumbnailUri(snippet['thumbnails']),
  );
}

Track? _trackFromPlaylistItem(Map<String, Object?> json) {
  final snippet = json['snippet'] as Map<dynamic, dynamic>?;
  final resourceId = snippet?['resourceId'] as Map<dynamic, dynamic>?;
  final videoId = _nonEmptyString(resourceId?['videoId']);
  if (snippet == null || videoId == null) {
    return null;
  }
  return Track(
    id: Track.stableLocalId('youtube-data-metadata|$videoId'),
    title: _nonEmptyString(snippet['title']) ?? 'Untitled YouTube video',
    artist:
        _nonEmptyString(snippet['videoOwnerChannelTitle']) ??
        _nonEmptyString(snippet['channelTitle']) ??
        'YouTube',
    album: 'YouTube playlist',
    genre: 'YouTube metadata',
    artworkUri: _thumbnailUri(snippet['thumbnails']),
    sourceId: 'youtube-data-metadata',
    externalId: videoId,
  );
}

Track _trackFromVideoMetadata(
  String videoId,
  Map<dynamic, dynamic> snippet, {
  Duration? duration,
}) {
  final title = _nonEmptyString(snippet['title']) ?? 'Untitled YouTube video';
  return Track(
    id: Track.stableLocalId('youtube-data-metadata|$videoId'),
    title: title,
    artist: _nonEmptyString(snippet['channelTitle']) ?? 'YouTube',
    album: 'YouTube',
    genre: 'YouTube metadata',
    duration: duration ?? Duration.zero,
    artworkUri: _thumbnailUri(snippet['thumbnails']),
    sourceId: 'youtube-data-metadata',
    externalId: videoId,
  );
}

Duration? parseYouTubeDataDuration(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  final match = RegExp(
    r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
  ).firstMatch(normalized);
  if (match == null ||
      (match.group(1) == null &&
          match.group(2) == null &&
          match.group(3) == null &&
          match.group(4) == null)) {
    return null;
  }
  final days = int.tryParse(match.group(1) ?? '0');
  final hours = int.tryParse(match.group(2) ?? '0');
  final minutes = int.tryParse(match.group(3) ?? '0');
  final seconds = double.tryParse(match.group(4) ?? '0');
  if (days == null ||
      hours == null ||
      minutes == null ||
      seconds == null ||
      !seconds.isFinite) {
    return null;
  }
  final microseconds = (((days * 24 + hours) * 60 + minutes) * 60 + seconds) *
      Duration.microsecondsPerSecond;
  if (!microseconds.isFinite ||
      microseconds < 0 ||
      microseconds > const Duration(days: 366).inMicroseconds) {
    return null;
  }
  return Duration(microseconds: microseconds.round());
}

String _normalizeRegionCode(String value) {
  final normalized = value.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'regionCode',
      'Must be an ISO 3166-1 alpha-2 code.',
    );
  }
  return normalized;
}

Uri? _thumbnailUri(Object? value) {
  if (value is! Map<dynamic, dynamic>) {
    return null;
  }
  for (final name in const <String>['high', 'medium', 'default']) {
    final thumbnail = value[name] as Map<dynamic, dynamic>?;
    final uri = Uri.tryParse(_nonEmptyString(thumbnail?['url']) ?? '');
    if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
      return uri;
    }
  }
  return null;
}

String _requireApiKey(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'apiKey', 'Must not be empty.');
  }
  return normalized;
}

String? _nonEmptyString(Object? value) {
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

Future<String> _loadYouTubeDataJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'YouTube Data API request failed with HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}
