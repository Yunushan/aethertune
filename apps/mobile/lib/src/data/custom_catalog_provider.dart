import 'dart:convert';
import 'dart:io';

import '../domain/custom_catalog_definition.dart';
import '../domain/music_source_provider.dart';
import '../domain/track.dart';
import 'provider_error.dart';

const maxCustomCatalogBytes = 2 * 1024 * 1024;
const maxCustomCatalogTracks = 500;

typedef CustomCatalogJsonLoader = Future<String> Function(Uri catalogUri);

/// Reads an explicitly configured, declarative JSON catalog.
///
/// Expected document shape:
/// `{ "version": 1, "tracks": [{ "id": "...", "title": "...",
/// "streamUrl": "https://declared-host/..." }] }`.
final class CustomCatalogProvider
    implements
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  CustomCatalogProvider(
    this.definition, {
    CustomCatalogJsonLoader? catalogLoader,
  }) : _catalogLoader = catalogLoader ?? loadCustomCatalogJson;

  final CustomCatalogDefinition definition;
  final CustomCatalogJsonLoader _catalogLoader;

  @override
  String get id => definition.providerId;

  @override
  String get name => definition.name;

  @override
  String get description => definition.description.isEmpty
      ? 'User-added JSON music catalog at ${definition.catalogUri.host}.'
      : definition.description;

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.searchSuggestions,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.directPlayback,
        MusicSourceCapability.artwork,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => ProviderPrivacyDisclosure(
        networkDomains: definition.declaredNetworkDomains,
        dataSent: const <String>[
          'catalog document request',
        ],
        cachesMetadata: false,
      );

  @override
  Future<List<Track>> search(String query) => _matchingTracks(query);

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
    final tracks = await _matchingTracks(normalizedQuery);
    final requestedOffset = _parseCatalogOffset(cursor);
    final start = requestedOffset > tracks.length
        ? tracks.length
        : requestedOffset;
    final boundedLimit = limit > 50 ? 50 : limit;
    final requestedEnd = start + boundedLimit;
    final end = requestedEnd > tracks.length ? tracks.length : requestedEnd;
    return MusicSourceSearchPage(
      tracks: List<Track>.unmodifiable(tracks.sublist(start, end)),
      totalCount: tracks.length,
      nextCursor: end < tracks.length ? end.toString() : null,
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
      suggestions.add(
        MusicSourceSearchSuggestion(
          value: value,
          kind: MusicSourceSearchSuggestionKind.track,
          subtitle: '${track.artist} - ${track.album}',
        ),
      );
      if (suggestions.length == limit) {
        break;
      }
    }
    return List<MusicSourceSearchSuggestion>.unmodifiable(suggestions);
  }

  Future<List<Track>> _matchingTracks(String query) async {
    final document = await _catalogLoader(definition.catalogUri);
    final tracks = parseCustomCatalogTracks(document, definition);
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return tracks;
    }
    return tracks.where((track) {
      return track.title.toLowerCase().contains(normalizedQuery) ||
          track.artist.toLowerCase().contains(normalizedQuery) ||
          track.album.toLowerCase().contains(normalizedQuery) ||
          track.genre.toLowerCase().contains(normalizedQuery);
    }).toList(growable: false);
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    if (track.sourceId != id || track.streamUrl == null) {
      return null;
    }
    final uri = Uri.tryParse(track.streamUrl!);
    return uri != null && definition.allowsRemoteUri(uri) ? uri : null;
  }
}

int _parseCatalogOffset(String? cursor) {
  final offset = int.tryParse(cursor?.trim() ?? '');
  return offset == null || offset < 0 ? 0 : offset;
}

List<Track> parseCustomCatalogTracks(
  String document,
  CustomCatalogDefinition definition,
) {
  final decoded = jsonDecode(document);
  if (decoded is! Map) {
    throw const ProviderRequestException('Catalog response must be an object.');
  }
  final root = Map<String, Object?>.from(decoded);
  if (root['version'] != 1 || root['tracks'] is! List) {
    throw const ProviderRequestException(
      'Catalog must contain version 1 and a tracks array.',
    );
  }
  final rawTracks = root['tracks'] as List;
  if (rawTracks.length > maxCustomCatalogTracks) {
    throw const ProviderRequestException('Catalog exceeds 500 tracks.');
  }
  final trackIds = <String>{};
  final tracks = <Track>[];
  for (final rawTrack in rawTracks) {
    if (rawTrack is! Map) {
      throw const ProviderRequestException('Catalog contains an invalid track.');
    }
    final track = _parseCustomCatalogTrack(
      Map<String, Object?>.from(rawTrack),
      definition,
    );
    if (!trackIds.add(track.id)) {
      throw const ProviderRequestException('Catalog contains duplicate track IDs.');
    }
    tracks.add(track);
  }
  return List<Track>.unmodifiable(tracks);
}

Track _parseCustomCatalogTrack(
  Map<String, Object?> json,
  CustomCatalogDefinition definition,
) {
  final externalId = _requiredText(json, 'id', maximum: 120);
  final title = _requiredText(json, 'title', maximum: 240);
  final streamUrl = _optionalRemoteUrl(json['streamUrl'], definition);
  final artworkUri = _optionalRemoteUrl(json['artworkUrl'], definition);
  final durationMs = json['durationMs'];
  if (durationMs != null &&
      (durationMs is! int || durationMs < 0 || durationMs > 24 * 60 * 60 * 1000)) {
    throw const ProviderRequestException('Catalog track duration is invalid.');
  }
  return Track(
    id: '${definition.providerId}:$externalId',
    title: title,
    artist: _optionalText(json, 'artist', fallback: 'Unknown Artist'),
    album: _optionalText(json, 'album', fallback: 'Unknown Album'),
    genre: _optionalText(json, 'genre', fallback: 'Unknown Genre'),
    duration: Duration(milliseconds: durationMs as int? ?? 0),
    streamUrl: streamUrl?.toString(),
    artworkUri: artworkUri,
    sourceId: definition.providerId,
    externalId: externalId,
  );
}

String _requiredText(Map<String, Object?> json, String key, {required int maximum}) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.trim().length > maximum) {
    throw ProviderRequestException('Catalog track $key is invalid.');
  }
  return value.trim();
}

String _optionalText(
  Map<String, Object?> json,
  String key, {
  required String fallback,
}) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    return fallback;
  }
  if (value.trim().length > 240) {
    throw ProviderRequestException('Catalog track $key is too long.');
  }
  return value.trim();
}

Uri? _optionalRemoteUrl(Object? value, CustomCatalogDefinition definition) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw const ProviderRequestException('Catalog media URL is invalid.');
  }
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !definition.allowsRemoteUri(uri)) {
    throw const ProviderRequestException(
      'Catalog media URL is outside the declared network domains.',
    );
  }
  return uri;
}

Future<String> loadCustomCatalogJson(Uri catalogUri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(catalogUri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderRequestException(
        'Catalog request failed with HTTP ${response.statusCode}.',
      );
    }
    final contentType = response.headers.contentType?.mimeType.toLowerCase() ?? '';
    if (contentType != 'application/json' && !contentType.endsWith('+json')) {
      throw const ProviderRequestException('Catalog response did not contain JSON.');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxCustomCatalogBytes) {
        throw const ProviderRequestException('Catalog response exceeded 2 MiB.');
      }
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) {
      throw const ProviderRequestException('Catalog response was empty.');
    }
    return utf8.decode(bytes);
  } finally {
    client.close(force: true);
  }
}
