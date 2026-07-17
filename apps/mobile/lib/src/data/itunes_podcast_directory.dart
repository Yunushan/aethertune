import 'dart:convert';
import 'dart:io';

typedef PodcastDirectoryLoader = Future<String> Function(Uri requestUri);

/// Searches Apple's public podcast catalog for RSS feeds that AetherTune can
/// validate and subscribe to through its existing open-feed adapter.
final class ItunesPodcastDirectory {
  ItunesPodcastDirectory({PodcastDirectoryLoader? loader})
      : _loader = loader ?? _loadDirectoryResponse;

  static final Uri searchEndpoint = Uri.https(
    'itunes.apple.com',
    '/search',
  );

  final PodcastDirectoryLoader _loader;

  Future<List<PodcastDirectoryResult>> search(
    String query, {
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
    }
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <PodcastDirectoryResult>[];
    }
    final boundedLimit = limit.clamp(1, 50);
    final uri = searchEndpoint.replace(
      queryParameters: <String, String>{
        'term': normalizedQuery,
        'media': 'podcast',
        'entity': 'podcast',
        'limit': boundedLimit.toString(),
        'explicit': 'No',
      },
    );
    return parseItunesPodcastDirectoryResponse(
      await _loader(uri),
      limit: boundedLimit,
    );
  }
}

final class PodcastDirectoryResult {
  const PodcastDirectoryResult({
    required this.feedUri,
    required this.title,
    required this.author,
    required this.genre,
  });

  final Uri feedUri;
  final String title;
  final String author;
  final String genre;
}

List<PodcastDirectoryResult> parseItunesPodcastDirectoryResponse(
  String jsonText, {
  required int limit,
}) {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
  }
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('Podcast directory response must be an object.');
  }
  final rawResults = decoded['results'];
  if (rawResults is! List<dynamic>) {
    return const <PodcastDirectoryResult>[];
  }

  final seenFeedUrls = <String>{};
  final results = <PodcastDirectoryResult>[];
  for (final rawResult in rawResults) {
    if (rawResult is! Map<dynamic, dynamic> || results.length == limit) {
      continue;
    }
    final item = rawResult.cast<String, Object?>();
    final feedUri = Uri.tryParse(_stringValue(item['feedUrl']));
    final title = _stringValue(item['collectionName']);
    if (feedUri == null ||
        !feedUri.hasScheme ||
        feedUri.host.isEmpty ||
        (feedUri.scheme != 'http' && feedUri.scheme != 'https') ||
        title.isEmpty ||
        !seenFeedUrls.add(feedUri.toString())) {
      continue;
    }
    results.add(
      PodcastDirectoryResult(
        feedUri: feedUri,
        title: title,
        author: _stringValue(item['artistName']),
        genre: _stringValue(item['primaryGenreName']),
      ),
    );
  }
  return List<PodcastDirectoryResult>.unmodifiable(results);
}

Future<String> _loadDirectoryResponse(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const HttpException('Podcast directory request failed.');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

String _stringValue(Object? value) => value?.toString().trim() ?? '';
