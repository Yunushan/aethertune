import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef JellyfinRequestLoader = Future<String> Function(Uri requestUri);

class JellyfinProvider implements MusicSourceProvider {
  JellyfinProvider({
    required this.baseUri,
    required this.userId,
    required this.apiKey,
    String? id,
    String? name,
    JellyfinRequestLoader? requestLoader,
    this.limit = 20,
    this.includeAuthenticatedUrlsInSearch = false,
  })  : id = id ?? 'jellyfin-${Track.stableLocalId(baseUri.toString())}',
        name = name ?? 'Jellyfin',
        _requestLoader = requestLoader ?? _loadJellyfinJson;

  static const defaultCapabilities = <MusicSourceCapability>{
    MusicSourceCapability.metadataSearch,
    MusicSourceCapability.streamResolution,
    MusicSourceCapability.libraryBrowse,
    MusicSourceCapability.directPlayback,
    MusicSourceCapability.offlineCache,
    MusicSourceCapability.downloads,
    MusicSourceCapability.authentication,
  };

  final Uri baseUri;
  final String userId;
  final String apiKey;
  final int limit;
  final bool includeAuthenticatedUrlsInSearch;
  final JellyfinRequestLoader _requestLoader;

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
          'audio item stream identifier',
          'cover art item identifier',
        ],
        requiresUserCredentials: true,
        cachesMedia: true,
        supportsDownloads: true,
      );

  @override
  Future<List<Track>> search(String query) {
    return searchAudio(query);
  }

  Future<List<Track>> searchAudio(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <Track>[];
    }

    final items = parseJellyfinItemsResponse(
      await _requestLoader(_searchUri(normalizedQuery)),
    );

    return items
        .take(limit)
        .map(
          (item) => item.toTrack(
            sourceId: id,
            streamUri: includeAuthenticatedUrlsInSearch
                ? streamUriFor(item.id)
                : null,
            artworkUri: includeAuthenticatedUrlsInSearch
                ? primaryImageUriFor(item.id, hasImage: item.hasPrimaryImage)
                : null,
          ),
        )
        .toList(growable: false);
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

  Uri? primaryImageUriFor(String itemId, {required bool hasImage}) {
    if (!hasImage || itemId.trim().isEmpty) {
      return null;
    }

    return _requestUri('/Items/$itemId/Images/Primary');
  }

  Uri _searchUri(String query) {
    return _requestUri(
      '/Users/$userId/Items',
      <String, String>{
        'Recursive': 'true',
        'IncludeItemTypes': 'Audio',
        'SearchTerm': query,
        'Fields': 'Genres,ImageTags,MediaSources',
        'Limit': limit.toString(),
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
}

final class JellyfinAudioItem {
  const JellyfinAudioItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.duration,
    required this.hasPrimaryImage,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final Duration duration;
  final bool hasPrimaryImage;

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
    hasPrimaryImage: _hasPrimaryImage(json),
  );
}

Future<String> _loadJellyfinJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Jellyfin request failed with HTTP ${response.statusCode}.',
        uri: uri,
      );
    }

    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
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

bool _hasPrimaryImage(Map<String, Object?> json) {
  final imageTags = json['ImageTags'];
  if (imageTags is Map<dynamic, dynamic>) {
    return _stringValue(imageTags['Primary']).isNotEmpty;
  }

  return false;
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
