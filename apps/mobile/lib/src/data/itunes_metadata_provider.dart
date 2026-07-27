import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef ItunesSearchResponseLoader = Future<String> Function(
  Uri uri,
  Map<String, String> headers,
);

typedef ItunesClock = DateTime Function();
typedef ItunesDelay = Future<void> Function(Duration duration);

/// Serializes explicit requests below Apple's documented public Search API
/// guidance of roughly 20 requests per minute.
final class ItunesRequestLimiter {
  ItunesRequestLimiter({
    ItunesClock? clock,
    ItunesDelay? delay,
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  static const minimumInterval = Duration(seconds: 3);

  final ItunesClock _clock;
  final ItunesDelay _delay;
  DateTime? _lastRequestAt;
  Future<void> _tail = Future<void>.value();

  Future<T> schedule<T>(Future<T> Function() operation) {
    final scheduled = _tail.then((_) async {
      final previous = _lastRequestAt;
      if (previous != null) {
        final elapsed = _clock().toUtc().difference(previous);
        final remaining = minimumInterval - elapsed;
        if (remaining > Duration.zero) {
          await _delay(remaining);
        }
      }
      _lastRequestAt = _clock().toUtc();
      return operation();
    });
    _tail = scheduled.then<void>((_) {}, onError: (_, _) {});
    return scheduled;
  }
}

/// One queue for every explicit iTunes Search API request made by the app.
final itunesRequestLimiter = ItunesRequestLimiter();

/// Public iTunes Store song metadata search.
///
/// This provider exposes catalog fields only. It intentionally omits Apple
/// preview URLs and promotional artwork because AetherTune does not render the
/// required store promotion treatment for that content. It never resolves
/// playback, caches media, or downloads.
final class ItunesMetadataProvider
    implements
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  ItunesMetadataProvider({
    Uri? searchUri,
    String country = 'us',
    ItunesSearchResponseLoader? loader,
    ItunesRequestLimiter? limiter,
  }) : searchUri = searchUri ?? _defaultSearchUri,
       country = _normalizeCountry(country),
       _loader = loader ?? _loadItunesSearchResponse,
       _limiter = limiter ?? itunesRequestLimiter;

  static final Uri _defaultSearchUri = Uri.https(
    'itunes.apple.com',
    '/search',
  );
  static const userAgent =
      'AetherTune/0.1 (https://github.com/Yunushan/aethertune)';

  final Uri searchUri;
  final String country;
  final ItunesSearchResponseLoader _loader;
  final ItunesRequestLimiter _limiter;

  @override
  String get id => 'itunes-metadata';

  @override
  String get name => 'iTunes Store metadata';

  @override
  String get description =>
      'Public iTunes Store song metadata search for the selected storefront. '
      'It omits previews and artwork, and never provides playback, caching, '
      'or downloads.';

  @override
  Set<MusicSourceCapability> get capabilities =>
      const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.searchSuggestions,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
    networkDomains: <String>['itunes.apple.com'],
    dataSent: <String>[
      'submitted search query or bounded type-ahead query',
      'selected two-letter iTunes Store country',
      'AetherTune versioned User-Agent',
    ],
  );

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
      throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
    }
    if (cursor?.trim().isNotEmpty == true) {
      return const MusicSourceSearchPage(tracks: <Track>[]);
    }
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const MusicSourceSearchPage(tracks: <Track>[]);
    }
    final boundedLimit = limit.clamp(1, 50);
    final uri = searchUri.replace(
      queryParameters: <String, String>{
        'term': normalizedQuery,
        'country': country,
        'media': 'music',
        'entity': 'song',
        'explicit': 'No',
        'limit': boundedLimit.toString(),
      },
    );
    final tracks = await _limiter.schedule(() async {
      final response = await _loader(uri, <String, String>{
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.userAgentHeader: userAgent,
      });
      return parseItunesSongSearchResponse(response, limit: boundedLimit);
    });
    return MusicSourceSearchPage(
      tracks: tracks,
      totalCount: tracks.length,
    );
  }

  @override
  Future<List<MusicSourceSearchSuggestion>> suggest(
    String query, {
    int limit = 8,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
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
          subtitle: '${track.artist} - ${track.album}',
        ),
      );
      if (suggestions.length == limit) {
        break;
      }
    }
    return List<MusicSourceSearchSuggestion>.unmodifiable(suggestions);
  }

  @override
  Future<Uri?> resolveStream(Track track) async => null;
}

List<Track> parseItunesSongSearchResponse(
  String jsonText, {
  required int limit,
}) {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
  }
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('iTunes Search response must be an object.');
  }
  final results = decoded['results'];
  if (results is! List<dynamic>) {
    return const <Track>[];
  }

  final tracks = <Track>[];
  final seen = <String>{};
  for (final raw in results) {
    if (raw is! Map<dynamic, dynamic> || tracks.length == limit) {
      continue;
    }
    final result = raw.cast<String, Object?>();
    if (_value(result['kind']).toLowerCase() != 'song') {
      continue;
    }
    final trackId = _numericIdentifier(result['trackId']);
    final title = _value(result['trackName']);
    if (trackId == null || title.isEmpty || !seen.add(trackId)) {
      continue;
    }
    tracks.add(
      Track(
        id: 'itunes:$trackId',
        externalId: trackId,
        sourceId: 'itunes-metadata',
        title: title,
        artist: _fallback(result['artistName'], 'Unknown Artist'),
        album: _fallback(result['collectionName'], 'Unknown Album'),
        genre: _fallback(result['primaryGenreName'], 'Unknown Genre'),
        duration: Duration(
          milliseconds: _nonNegativeInt(result['trackTimeMillis']) ?? 0,
        ),
        year: _releaseYear(result['releaseDate']),
        trackNumber: _positiveInt(result['trackNumber']),
      ),
    );
  }
  return List<Track>.unmodifiable(tracks);
}

String _normalizeCountry(String value) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z]{2}$').hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'country',
      'Must be an ISO 3166-1 alpha-2 country code.',
    );
  }
  return normalized;
}

String _value(Object? value) => value?.toString().trim() ?? '';

String _fallback(Object? value, String fallback) {
  final normalized = _value(value);
  return normalized.isEmpty ? fallback : normalized;
}

String? _numericIdentifier(Object? value) {
  final normalized = _value(value);
  return RegExp(r'^\d+$').hasMatch(normalized) ? normalized : null;
}

int? _nonNegativeInt(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse(_value(value));
  return number == null || number < 0 ? null : number;
}

int? _positiveInt(Object? value) {
  final number = _nonNegativeInt(value);
  return number == null || number == 0 ? null : number;
}

int? _releaseYear(Object? value) {
  final match = RegExp(r'^(\d{4})').firstMatch(_value(value));
  final year = match == null ? null : int.tryParse(match.group(1)!);
  return year == null || year < 1000 || year > 9999 ? null : year;
}

Future<String> _loadItunesSearchResponse(
  Uri uri,
  Map<String, String> headers,
) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const HttpException('iTunes metadata search failed.');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
