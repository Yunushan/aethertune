import 'dart:convert';
import 'dart:io';

import '../domain/lyrics_provider.dart';
import '../domain/music_source_provider.dart';

typedef LrcLibResponseLoader = Future<String> Function(
  Uri uri,
  Map<String, String> headers,
);

final class LrcLibLyricsProvider implements LyricsProvider {
  LrcLibLyricsProvider({
    Uri? baseUri,
    LrcLibResponseLoader? responseLoader,
  })  : baseUri = baseUri ?? Uri.parse('https://lrclib.net'),
        _responseLoader = responseLoader ?? _loadLrcLibResponse;

  static const userAgent =
      'AetherTune/0.1.0 (+https://github.com/Yunushan/aethertune)';

  final Uri baseUri;
  final LrcLibResponseLoader _responseLoader;

  @override
  String get id => 'lrclib';

  @override
  String get name => 'LRCLIB';

  @override
  String get description =>
      'Open LRCLIB search adapter for plain and synchronized lyrics.';

  @override
  ProviderPrivacyDisclosure get disclosure => ProviderPrivacyDisclosure(
        networkDomains: baseUri.host.isEmpty
            ? const <String>[]
            : <String>[baseUri.host],
        dataSent: const <String>[
          'lyrics search terms derived from track title, artist, and album',
        ],
        cachesMetadata: true,
      );

  @override
  Future<List<LyricsSearchResult>> search(LyricsSearchQuery query) async {
    if (!query.hasSearchTerms) {
      throw ArgumentError.value(
        query.keywords,
        'query',
        'Lyrics search requires keywords or a track title.',
      );
    }

    final results = parseLrcLibSearchResults(
      await _responseLoader(
        _searchUri(query),
        const <String, String>{
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.userAgentHeader: userAgent,
        },
      ),
      providerId: id,
      providerName: name,
      baseUri: baseUri,
    );

    return rankLrcLibSearchResults(results, query);
  }

  Uri _searchUri(LyricsSearchQuery query) {
    final keywords = query.keywords.trim();
    final parameters = <String, String>{};
    if (keywords.isNotEmpty) {
      parameters['q'] = keywords;
    } else {
      parameters['track_name'] = query.trackName.trim();
      final artist = _knownMetadata(query.artistName, 'Unknown Artist');
      final album = _knownMetadata(query.albumName, 'Unknown Album');
      if (artist.isNotEmpty) {
        parameters['artist_name'] = artist;
      }
      if (album.isNotEmpty) {
        parameters['album_name'] = album;
      }
    }

    return baseUri.replace(
      path: _joinUriPath(baseUri.path, '/api/search'),
      queryParameters: parameters,
    );
  }
}

List<LyricsSearchResult> parseLrcLibSearchResults(
  String responseBody, {
  required String providerId,
  required String providerName,
  required Uri baseUri,
}) {
  final decoded = jsonDecode(responseBody);
  if (decoded is! List) {
    throw const FormatException('LRCLIB search response must be a JSON list.');
  }

  final results = <LyricsSearchResult>[];
  final seenIds = <String>{};
  for (final item in decoded) {
    if (item is! Map) {
      continue;
    }
    final record = Map<String, Object?>.from(item);
    final id = _jsonId(record['id']);
    if (id.isEmpty || !seenIds.add(id)) {
      continue;
    }

    results.add(
      LyricsSearchResult(
        providerId: providerId,
        providerName: providerName,
        externalId: id,
        trackName: _jsonString(record['trackName'], fallback: 'Untitled'),
        artistName: _jsonString(
          record['artistName'],
          fallback: 'Unknown Artist',
        ),
        albumName: _jsonString(
          record['albumName'],
          fallback: 'Unknown Album',
        ),
        duration: _jsonDuration(record['duration']),
        instrumental: record['instrumental'] as bool? ?? false,
        plainLyrics: _jsonString(record['plainLyrics']),
        syncedLyrics: _jsonString(record['syncedLyrics']),
        sourceUri: baseUri.replace(
          path: _joinUriPath(baseUri.path, '/api/get/$id'),
          queryParameters: const <String, String>{},
        ),
      ),
    );
  }

  return List<LyricsSearchResult>.unmodifiable(results);
}

List<LyricsSearchResult> rankLrcLibSearchResults(
  List<LyricsSearchResult> results,
  LyricsSearchQuery query,
) {
  final ranked = List<LyricsSearchResult>.from(results);
  ranked.sort((left, right) {
    final byScore = _matchScore(right, query).compareTo(
      _matchScore(left, query),
    );
    if (byScore != 0) {
      return byScore;
    }

    final byTitle = left.trackName.toLowerCase().compareTo(
      right.trackName.toLowerCase(),
    );
    if (byTitle != 0) {
      return byTitle;
    }
    return left.externalId.compareTo(right.externalId);
  });
  return List<LyricsSearchResult>.unmodifiable(ranked);
}

int _matchScore(LyricsSearchResult result, LyricsSearchQuery query) {
  var score = 0;
  score += _fieldScore(result.trackName, query.trackName, exact: 100, partial: 30);
  score += _fieldScore(result.artistName, query.artistName, exact: 60, partial: 20);
  score += _fieldScore(result.albumName, query.albumName, exact: 20, partial: 8);

  if (query.duration > Duration.zero && result.duration > Duration.zero) {
    final difference =
        (query.duration.inSeconds - result.duration.inSeconds).abs();
    if (difference <= 2) {
      score += 40;
    } else if (difference <= 5) {
      score += 10;
    }
  }
  if (result.hasSyncedLyrics) {
    score += 5;
  } else if (result.hasPlainLyrics) {
    score += 2;
  }
  if (result.instrumental && !result.isSelectable) {
    score -= 5;
  }
  return score;
}

int _fieldScore(
  String actual,
  String expected, {
  required int exact,
  required int partial,
}) {
  final left = _normalizeMatchText(actual);
  final right = _normalizeMatchText(expected);
  if (left.isEmpty || right.isEmpty || right.startsWith('unknown ')) {
    return 0;
  }
  if (left == right) {
    return exact;
  }
  if (left.contains(right) || right.contains(left)) {
    return partial;
  }
  return 0;
}

String _normalizeMatchText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _knownMetadata(String value, String unknownValue) {
  final normalized = value.trim();
  return normalized.toLowerCase() == unknownValue.toLowerCase()
      ? ''
      : normalized;
}

String _jsonId(Object? value) {
  if (value is num) {
    return value.toInt().toString();
  }
  return value is String ? value.trim() : '';
}

String _jsonString(Object? value, {String fallback = ''}) {
  final normalized = value is String ? value.trim() : '';
  return normalized.isEmpty ? fallback : normalized;
}

Duration _jsonDuration(Object? value) {
  if (value is! num || !value.isFinite || value <= 0) {
    return Duration.zero;
  }
  return Duration(milliseconds: (value.toDouble() * 1000).round());
}

String _joinUriPath(String basePath, String childPath) {
  final left = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  final right = childPath.startsWith('/') ? childPath : '/$childPath';
  return '$left$right';
}

Future<String> _loadLrcLibResponse(
  Uri uri,
  Map<String, String> headers,
) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'LRCLIB request failed with HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
