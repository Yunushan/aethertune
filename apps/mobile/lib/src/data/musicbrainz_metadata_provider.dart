import 'dart:convert';
import 'dart:io';

typedef MusicBrainzResponseLoader = Future<String> Function(
  Uri uri,
  Map<String, String> headers,
);

typedef MusicBrainzClock = DateTime Function();
typedef MusicBrainzDelay = Future<void> Function(Duration duration);

/// Serializes requests so this app respects MusicBrainz's one request per
/// second limit even when a user performs several explicit lookups quickly.
final class MusicBrainzRequestLimiter {
  MusicBrainzRequestLimiter({
    MusicBrainzClock? clock,
    MusicBrainzDelay? delay,
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  final MusicBrainzClock _clock;
  final MusicBrainzDelay _delay;
  DateTime? _lastRequestAt;
  Future<void> _tail = Future<void>.value();

  Future<T> schedule<T>(Future<T> Function() operation) {
    final scheduled = _tail.then((_) async {
      final previous = _lastRequestAt;
      if (previous != null) {
        final elapsed = _clock().toUtc().difference(previous);
        final remaining = const Duration(seconds: 1) - elapsed;
        if (remaining > Duration.zero) {
          await _delay(remaining);
        }
      }
      _lastRequestAt = _clock().toUtc();
      return operation();
    });
    _tail = scheduled.then<void>((_) {}, onError: (_, __) {});
    return scheduled;
  }
}

/// Explicit, read-only metadata lookup through the public MusicBrainz API.
///
/// Callers must show the disclosure and obtain a user action before invoking
/// [search]. This adapter intentionally does not identify audio or upload files.
final class MusicBrainzMetadataProvider {
  MusicBrainzMetadataProvider({
    MusicBrainzResponseLoader? loader,
    MusicBrainzRequestLimiter? limiter,
  }) : _loader = loader ?? _loadMusicBrainzResponse,
       _limiter = limiter ?? _sharedLimiter;

  static final Uri searchEndpoint = Uri.https(
    'musicbrainz.org',
    '/ws/2/recording',
  );
  static const userAgent =
      'AetherTune/0.1 (https://github.com/Yunushan/aethertune)';
  static final MusicBrainzRequestLimiter _sharedLimiter =
      MusicBrainzRequestLimiter();

  final MusicBrainzResponseLoader _loader;
  final MusicBrainzRequestLimiter _limiter;

  Future<List<MusicBrainzMetadataCandidate>> search({
    required String title,
    required String artist,
    required String album,
    int limit = 10,
  }) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
    }
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      return Future<List<MusicBrainzMetadataCandidate>>.value(
        const <MusicBrainzMetadataCandidate>[],
      );
    }
    final boundedLimit = limit.clamp(1, 25);
    final query = _recordingQuery(
      title: normalizedTitle,
      artist: artist,
      album: album,
    );
    final uri = searchEndpoint.replace(
      queryParameters: <String, String>{
        'query': query,
        'fmt': 'json',
        'limit': boundedLimit.toString(),
      },
    );
    return _limiter.schedule(() async {
      final response = await _loader(uri, <String, String>{
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.userAgentHeader: userAgent,
      });
      return parseMusicBrainzRecordingSearchResponse(
        response,
        limit: boundedLimit,
      );
    });
  }
}

final class MusicBrainzMetadataCandidate {
  const MusicBrainzMetadataCandidate({
    required this.recordingId,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.duration,
    required this.score,
  });

  final String recordingId;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final Duration duration;
  final int score;
}

List<MusicBrainzMetadataCandidate> parseMusicBrainzRecordingSearchResponse(
  String jsonText, {
  required int limit,
}) {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'Limit must be positive.');
  }
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('MusicBrainz response must be an object.');
  }
  final recordings = decoded['recordings'];
  if (recordings is! List<dynamic>) {
    return const <MusicBrainzMetadataCandidate>[];
  }

  final seenIds = <String>{};
  final candidates = <MusicBrainzMetadataCandidate>[];
  for (final rawRecording in recordings) {
    if (rawRecording is! Map<dynamic, dynamic> || candidates.length == limit) {
      continue;
    }
    final recording = rawRecording.cast<String, Object?>();
    final recordingId = _stringValue(recording['id']);
    final title = _stringValue(recording['title']);
    if (!_isMbid(recordingId) || title.isEmpty || !seenIds.add(recordingId)) {
      continue;
    }
    final artist = _artistCredit(recording['artist-credit']);
    final album = _firstReleaseTitle(recording['releases']);
    candidates.add(
      MusicBrainzMetadataCandidate(
        recordingId: recordingId,
        title: title,
        artist: artist.isEmpty ? 'Unknown Artist' : artist,
        album: album.isEmpty ? 'Unknown Album' : album,
        genre: _firstGenre(recording['genres']),
        duration: Duration(
          milliseconds: (recording['length'] as num?)?.toInt() ?? 0,
        ),
        score: (recording['score'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return List<MusicBrainzMetadataCandidate>.unmodifiable(candidates);
}

String _recordingQuery({
  required String title,
  required String artist,
  required String album,
}) {
  final terms = <String>['recording:"${_escapeQueryValue(title)}"'];
  if (_hasMeaningfulMetadata(artist, 'Unknown Artist')) {
    terms.add('artist:"${_escapeQueryValue(artist.trim())}"');
  }
  if (_hasMeaningfulMetadata(album, 'Unknown Album')) {
    terms.add('release:"${_escapeQueryValue(album.trim())}"');
  }
  return terms.join(' AND ');
}

String _escapeQueryValue(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

bool _hasMeaningfulMetadata(String value, String unknownValue) {
  final normalized = value.trim();
  return normalized.isNotEmpty &&
      normalized.toLowerCase() != unknownValue.toLowerCase();
}

bool _isMbid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);

String _artistCredit(Object? value) {
  if (value is! List<dynamic>) {
    return '';
  }
  return value
      .whereType<Map<dynamic, dynamic>>()
      .map((credit) {
        final item = credit.cast<String, Object?>();
        return _stringValue(item['name']).isNotEmpty
            ? _stringValue(item['name'])
            : item['artist'] is Map<dynamic, dynamic>
            ? _stringValue((item['artist'] as Map<dynamic, dynamic>)['name'])
            : '';
      })
      .where((name) => name.isNotEmpty)
      .join(', ');
}

String _firstReleaseTitle(Object? value) {
  if (value is! List<dynamic>) {
    return '';
  }
  for (final release in value.whereType<Map<dynamic, dynamic>>()) {
    final title = _stringValue(release['title']);
    if (title.isNotEmpty) {
      return title;
    }
  }
  return '';
}

String _firstGenre(Object? value) {
  if (value is! List<dynamic>) {
    return '';
  }
  for (final genre in value.whereType<Map<dynamic, dynamic>>()) {
    final name = _stringValue(genre['name']);
    if (name.isNotEmpty) {
      return name;
    }
  }
  return '';
}

Future<String> _loadMusicBrainzResponse(
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
      throw const HttpException('MusicBrainz metadata search failed.');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

String _stringValue(Object? value) => value?.toString().trim() ?? '';
