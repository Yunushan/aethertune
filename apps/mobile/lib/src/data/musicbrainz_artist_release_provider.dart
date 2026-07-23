import 'dart:convert';
import 'dart:io';

import 'musicbrainz_metadata_provider.dart';

/// A bounded view of dated releases by locally followed artists.
///
/// This is discovery metadata only. It does not resolve media, create a user
/// account, or perform autonomous work unless an app surface explicitly
/// invokes it after the user enables that behavior.
final class MusicBrainzArtistReleaseProvider {
  MusicBrainzArtistReleaseProvider({
    MusicBrainzResponseLoader? loader,
    MusicBrainzRequestLimiter? limiter,
  }) : _loader = loader ?? _loadMusicBrainzResponse,
       _limiter = limiter ?? musicBrainzRequestLimiter;

  static final Uri artistSearchEndpoint = Uri.https(
    'musicbrainz.org',
    '/ws/2/artist',
  );
  static final Uri releaseGroupBrowseEndpoint = Uri.https(
    'musicbrainz.org',
    '/ws/2/release-group',
  );

  final MusicBrainzResponseLoader _loader;
  final MusicBrainzRequestLimiter _limiter;

  Future<MusicBrainzArtistReleaseFeed> loadFollowedArtistReleases({
    required Iterable<String> artistNames,
    int artistLimit = 4,
    int releasesPerArtist = 3,
  }) async {
    if (artistLimit <= 0) {
      throw ArgumentError.value(
        artistLimit,
        'artistLimit',
        'Must be positive.',
      );
    }
    if (releasesPerArtist <= 0) {
      throw ArgumentError.value(
        releasesPerArtist,
        'releasesPerArtist',
        'Must be positive.',
      );
    }

    final artists = _normalizedArtistNames(artistNames).take(artistLimit);
    final releases = <MusicBrainzArtistRelease>[];
    var failures = 0;
    for (final artistName in artists) {
      try {
        final artist = await _findExactArtist(artistName);
        if (artist == null) {
          continue;
        }
        releases.addAll(
          await _browseReleaseGroups(artist: artist, limit: releasesPerArtist),
        );
      } on Object {
        failures += 1;
      }
    }
    final seen = <String>{};
    final deduplicated =
        releases
            .where((release) => seen.add(release.releaseGroupId))
            .toList(growable: false)
          ..sort((left, right) {
            final date = right.firstReleaseDate.compareTo(
              left.firstReleaseDate,
            );
            return date != 0 ? date : left.title.compareTo(right.title);
          });
    return MusicBrainzArtistReleaseFeed(
      releases: deduplicated,
      attemptedArtistCount: artists.length,
      failedArtistCount: failures,
    );
  }

  Future<_MusicBrainzArtist?> _findExactArtist(String artistName) async {
    final uri = artistSearchEndpoint.replace(
      queryParameters: <String, String>{
        'query': 'artist:"${_escapeQueryValue(artistName)}"',
        'fmt': 'json',
        'limit': '5',
      },
    );
    final response = await _request(uri);
    return _parseMusicBrainzArtistSearchResponse(
      response,
      artistName: artistName,
    );
  }

  Future<List<MusicBrainzArtistRelease>> _browseReleaseGroups({
    required _MusicBrainzArtist artist,
    required int limit,
  }) async {
    final uri = releaseGroupBrowseEndpoint.replace(
      queryParameters: <String, String>{
        'artist': artist.id,
        'fmt': 'json',
        'limit': limit.clamp(1, 25).toString(),
      },
    );
    return parseMusicBrainzReleaseGroupBrowseResponse(
      await _request(uri),
      artistName: artist.name,
      limit: limit,
    );
  }

  Future<String> _request(Uri uri) {
    return _limiter.schedule(() {
      return _loader(uri, <String, String>{
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.userAgentHeader: MusicBrainzMetadataProvider.userAgent,
      });
    });
  }
}

final class MusicBrainzArtistReleaseFeed {
  MusicBrainzArtistReleaseFeed({
    required Iterable<MusicBrainzArtistRelease> releases,
    required this.attemptedArtistCount,
    required this.failedArtistCount,
  }) : releases = List<MusicBrainzArtistRelease>.unmodifiable(releases);

  final List<MusicBrainzArtistRelease> releases;
  final int attemptedArtistCount;
  final int failedArtistCount;

  bool get hasCompleteFailure =>
      attemptedArtistCount > 0 && failedArtistCount == attemptedArtistCount;
}

final class MusicBrainzArtistRelease {
  const MusicBrainzArtistRelease({
    required this.releaseGroupId,
    required this.title,
    required this.artistName,
    required this.firstReleaseDate,
    required this.primaryType,
  });

  final String releaseGroupId;
  final String title;
  final String artistName;
  final String firstReleaseDate;
  final String primaryType;

  Uri get detailsUri =>
      Uri.https('musicbrainz.org', '/release-group/$releaseGroupId');
}

_MusicBrainzArtist? _parseMusicBrainzArtistSearchResponse(
  String jsonText, {
  required String artistName,
}) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException(
      'MusicBrainz artist response must be an object.',
    );
  }
  final artists = decoded['artists'];
  if (artists is! List<dynamic>) {
    return null;
  }
  final normalizedName = artistName.trim().toLowerCase();
  for (final raw in artists.whereType<Map<dynamic, dynamic>>()) {
    final artist = raw.cast<String, Object?>();
    final id = _stringValue(artist['id']);
    final name = _stringValue(artist['name']);
    if (_isMbid(id) && name.toLowerCase() == normalizedName) {
      return _MusicBrainzArtist(id: id, name: name);
    }
  }
  return null;
}

List<MusicBrainzArtistRelease> parseMusicBrainzReleaseGroupBrowseResponse(
  String jsonText, {
  required String artistName,
  required int limit,
}) {
  if (limit <= 0) {
    throw ArgumentError.value(limit, 'limit', 'Must be positive.');
  }
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException(
      'MusicBrainz release-group response must be an object.',
    );
  }
  final releaseGroups = decoded['release-groups'];
  if (releaseGroups is! List<dynamic>) {
    return const <MusicBrainzArtistRelease>[];
  }
  final allowedTypes = <String>{'album', 'ep', 'single'};
  final releases = <MusicBrainzArtistRelease>[];
  final seen = <String>{};
  for (final raw in releaseGroups.whereType<Map<dynamic, dynamic>>()) {
    if (releases.length == limit) {
      break;
    }
    final release = raw.cast<String, Object?>();
    final id = _stringValue(release['id']);
    final title = _stringValue(release['title']);
    final firstReleaseDate = _stringValue(release['first-release-date']);
    final primaryType = _stringValue(release['primary-type']);
    if (!_isMbid(id) ||
        title.isEmpty ||
        firstReleaseDate.isEmpty ||
        !allowedTypes.contains(primaryType.toLowerCase()) ||
        !seen.add(id)) {
      continue;
    }
    releases.add(
      MusicBrainzArtistRelease(
        releaseGroupId: id,
        title: title,
        artistName: artistName,
        firstReleaseDate: firstReleaseDate,
        primaryType: primaryType,
      ),
    );
  }
  return List<MusicBrainzArtistRelease>.unmodifiable(releases);
}

final class _MusicBrainzArtist {
  const _MusicBrainzArtist({required this.id, required this.name});

  final String id;
  final String name;
}

Iterable<String> _normalizedArtistNames(Iterable<String> values) sync* {
  final seen = <String>{};
  for (final value in values) {
    final name = value.trim();
    if (name.isNotEmpty && seen.add(name.toLowerCase())) {
      yield name;
    }
  }
}

Future<String> _loadMusicBrainzResponse(
  Uri uri,
  Map<String, String> headers,
) async {
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 15));
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const HttpException('MusicBrainz release lookup failed.');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

String _escapeQueryValue(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

String _stringValue(Object? value) => value?.toString().trim() ?? '';

bool _isMbid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);
