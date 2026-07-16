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
    implements MusicSourceSearchPagingProvider {
  YouTubeDataMetadataProvider({
    required String apiKey,
    Uri? searchUri,
    YouTubeDataSearchLoader? searchLoader,
  }) : _apiKey = _requireApiKey(apiKey),
       searchUri = searchUri ?? _defaultSearchUri,
       _searchLoader = searchLoader ?? _loadYouTubeDataJson;

  static final Uri _defaultSearchUri = Uri.parse(
    'https://www.googleapis.com/youtube/v3/search',
  );

  final String _apiKey;
  final Uri searchUri;
  final YouTubeDataSearchLoader _searchLoader;

  @override
  String get id => 'youtube-data-metadata';

  @override
  String get name => 'YouTube Data API';

  @override
  String get description =>
      'Official YouTube Data API video metadata search. Playback, downloads, '
      'offline media, and account access are not provided.';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
    MusicSourceCapability.metadataSearch,
    MusicSourceCapability.artwork,
  };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
    networkDomains: <String>['www.googleapis.com', 'i.ytimg.com'],
    dataSent: <String>['search query', 'configured Google Cloud API key'],
  );

  @override
  Future<List<Track>> search(String query) async {
    final page = await searchPage(query);
    return page.tracks;
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
    return MusicSourceSearchPage(
      tracks: response.tracks,
      nextCursor: response.nextPageToken,
      totalCount: response.totalResults,
    );
  }

  @override
  Future<Uri?> resolveStream(Track track) async => null;

  Uri _requestUri(String query, {String? cursor, required int limit}) {
    return searchUri.replace(
      queryParameters: <String, String>{
        'part': 'snippet',
        'type': 'video',
        'q': query,
        'maxResults': limit.toString(),
        'key': _apiKey,
        if (cursor != null && cursor.isNotEmpty) 'pageToken': cursor,
      },
    );
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

Track? _trackFromSearchItem(Map<String, Object?> json) {
  final id = json['id'] as Map<dynamic, dynamic>?;
  final videoId = _nonEmptyString(id?['videoId']);
  final snippet = json['snippet'] as Map<dynamic, dynamic>?;
  if (videoId == null || snippet == null) {
    return null;
  }
  final title = _nonEmptyString(snippet['title']) ?? 'Untitled YouTube video';
  return Track(
    id: Track.stableLocalId('youtube-data-metadata|$videoId'),
    title: title,
    artist: _nonEmptyString(snippet['channelTitle']) ?? 'YouTube',
    album: 'YouTube',
    genre: 'YouTube metadata',
    artworkUri: _thumbnailUri(snippet['thumbnails']),
    sourceId: 'youtube-data-metadata',
    externalId: videoId,
  );
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
