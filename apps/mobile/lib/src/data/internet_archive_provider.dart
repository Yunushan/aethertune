import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef InternetArchiveSearchLoader = Future<String> Function(Uri searchUri);
typedef InternetArchiveMetadataLoader = Future<String> Function(
  Uri metadataUri,
);

class InternetArchiveProvider implements MusicSourceProvider {
  InternetArchiveProvider({
    Uri? baseUri,
    InternetArchiveSearchLoader? searchLoader,
    InternetArchiveMetadataLoader? metadataLoader,
    this.limit = 10,
  })  : baseUri = baseUri ?? Uri.parse('https://archive.org'),
        _searchLoader = searchLoader ?? _loadInternetArchiveJson,
        _metadataLoader = metadataLoader ?? _loadInternetArchiveJson;

  final Uri baseUri;
  final int limit;
  final InternetArchiveSearchLoader _searchLoader;
  final InternetArchiveMetadataLoader _metadataLoader;

  @override
  String get id => 'internet-archive';

  @override
  String get name => 'Internet Archive';

  @override
  String get description =>
      'Open catalog adapter for public Internet Archive audio items.';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.directPlayback,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => ProviderPrivacyDisclosure(
        networkDomains: baseUri.host.isEmpty ? const <String>[] : <String>[
          baseUri.host,
        ],
        dataSent: const <String>[
          'item search query',
          'item metadata identifier',
        ],
      );

  @override
  Future<List<Track>> search(String query) async {
    final results = parseInternetArchiveSearchResults(
      await _searchLoader(_searchUri(query.trim())),
    );
    final tracks = <Track>[];

    for (final result in results.take(limit)) {
      final item = await fetchItem(result.identifier);
      final track = item.toTrack(sourceId: id, baseUri: baseUri);
      if (track != null) {
        tracks.add(track);
      }
    }

    return tracks;
  }

  Future<InternetArchiveItem> fetchItem(String identifier) {
    return _metadataLoader(_metadataUri(identifier)).then(
      parseInternetArchiveItem,
    );
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    if (track.sourceId != id) {
      return null;
    }

    final streamUrl = track.streamUrl;
    if (streamUrl != null && streamUrl.isNotEmpty) {
      return Uri.tryParse(streamUrl);
    }

    final externalId = track.externalId;
    if (externalId == null || !externalId.contains('|')) {
      return null;
    }

    final separator = externalId.indexOf('|');
    return _downloadUri(
      baseUri,
      externalId.substring(0, separator),
      externalId.substring(separator + 1),
    );
  }

  Uri _searchUri(String query) {
    final archiveQuery = query.isEmpty
        ? 'mediatype:audio'
        : 'mediatype:audio AND (${_searchTerm(query)})';

    return baseUri.replace(
      path: _joinUriPath(baseUri.path, '/advancedsearch.php'),
      queryParameters: <String, dynamic>{
        'q': archiveQuery,
        'fl[]': const <String>[
          'identifier',
          'title',
          'creator',
          'subject',
          'collection',
          'description',
          'year',
          'licenseurl',
          'downloads',
        ],
        'sort[]': const <String>['downloads desc'],
        'rows': limit.toString(),
        'page': '1',
        'output': 'json',
      },
    );
  }

  Uri _metadataUri(String identifier) {
    return baseUri.replace(
      path: _joinUriPath(
        baseUri.path,
        '/metadata/${Uri.encodeComponent(identifier)}',
      ),
      queryParameters: const <String, String>{},
    );
  }
}

final class InternetArchiveSearchResult {
  const InternetArchiveSearchResult({required this.identifier});

  final String identifier;
}

final class InternetArchiveItem {
  const InternetArchiveItem({
    required this.identifier,
    required this.title,
    required this.creator,
    required this.description,
    required this.subjects,
    required this.collections,
    required this.year,
    required this.licenseUrl,
    required this.files,
  });

  final String identifier;
  final String title;
  final String creator;
  final String description;
  final List<String> subjects;
  final List<String> collections;
  final String year;
  final String licenseUrl;
  final List<InternetArchiveFile> files;

  InternetArchiveFile? get playableAudioFile {
    final playable = files
        .where((file) => file.isPlayableAudio)
        .toList(growable: false)
      ..sort(
        (left, right) => left.playbackPriority.compareTo(
          right.playbackPriority,
        ),
      );

    return playable.isEmpty ? null : playable.first;
  }

  Track? toTrack({
    required String sourceId,
    required Uri baseUri,
  }) {
    final audioFile = playableAudioFile;
    if (audioFile == null) {
      return null;
    }

    final genre = subjects.isEmpty ? 'Internet Archive Audio' : subjects.first;
    final albumParts = <String>[
      'Internet Archive',
      if (year.isNotEmpty) year,
    ];

    return Track(
      id: Track.stableLocalId('$sourceId|$identifier|${audioFile.name}'),
      title: title.isEmpty ? audioFile.displayTitle : title,
      artist: creator.isEmpty ? 'Internet Archive' : creator,
      album: albumParts.join(' / '),
      genre: genre,
      duration: audioFile.duration,
      artworkUri: _imageUri(baseUri, identifier),
      streamUrl: _downloadUri(baseUri, identifier, audioFile.name).toString(),
      sourceId: sourceId,
      externalId: '$identifier|${audioFile.name}',
    );
  }
}

final class InternetArchiveFile {
  const InternetArchiveFile({
    required this.name,
    required this.format,
    required this.title,
    required this.source,
    required this.duration,
  });

  final String name;
  final String format;
  final String title;
  final String source;
  final Duration duration;

  String get displayTitle {
    if (title.isNotEmpty) {
      return title;
    }

    final lastSegment = name.split('/').last;
    final dot = lastSegment.lastIndexOf('.');
    return dot == -1 ? lastSegment : lastSegment.substring(0, dot);
  }

  bool get isPlayableAudio {
    final lowerName = name.toLowerCase();
    final lowerFormat = format.toLowerCase();
    return lowerName.endsWith('.mp3') ||
        lowerName.endsWith('.m4a') ||
        lowerName.endsWith('.aac') ||
        lowerName.endsWith('.ogg') ||
        lowerName.endsWith('.oga') ||
        lowerName.endsWith('.opus') ||
        lowerName.endsWith('.flac') ||
        lowerName.endsWith('.wav') ||
        lowerFormat.contains('mp3') ||
        lowerFormat.contains('mpeg audio') ||
        lowerFormat.contains('mpeg4 audio') ||
        lowerFormat.contains('aac') ||
        lowerFormat.contains('ogg') ||
        lowerFormat.contains('opus') ||
        lowerFormat.contains('flac') ||
        lowerFormat.contains('wave');
  }

  int get playbackPriority {
    final lowerName = name.toLowerCase();
    final lowerFormat = format.toLowerCase();
    if (lowerName.endsWith('.mp3') || lowerFormat.contains('mp3')) {
      return 0;
    }
    if (lowerName.endsWith('.m4a') ||
        lowerName.endsWith('.aac') ||
        lowerFormat.contains('mpeg4 audio') ||
        lowerFormat.contains('aac')) {
      return 1;
    }
    if (lowerName.endsWith('.ogg') ||
        lowerName.endsWith('.oga') ||
        lowerName.endsWith('.opus') ||
        lowerFormat.contains('ogg') ||
        lowerFormat.contains('opus')) {
      return 2;
    }
    if (lowerName.endsWith('.flac') || lowerFormat.contains('flac')) {
      return 3;
    }
    if (lowerName.endsWith('.wav') || lowerFormat.contains('wave')) {
      return 4;
    }

    return 99;
  }
}

List<InternetArchiveSearchResult> parseInternetArchiveSearchResults(
  String jsonText,
) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException(
      'Internet Archive search response must be a map.',
    );
  }

  final response = decoded['response'];
  if (response is! Map<dynamic, dynamic>) {
    return const <InternetArchiveSearchResult>[];
  }

  final docs = response['docs'];
  if (docs is! List<dynamic>) {
    return const <InternetArchiveSearchResult>[];
  }

  return docs
      .whereType<Map<dynamic, dynamic>>()
      .map((json) => _searchResultFromJson(json.cast<String, Object?>()))
      .whereType<InternetArchiveSearchResult>()
      .toList(growable: false);
}

InternetArchiveItem parseInternetArchiveItem(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException(
      'Internet Archive metadata response must be a map.',
    );
  }

  final json = decoded.cast<String, Object?>();
  final metadata = (json['metadata'] as Map<dynamic, dynamic>?)
          ?.cast<String, Object?>() ??
      const <String, Object?>{};
  final identifier = _stringValue(metadata['identifier'])
      .ifEmpty(_stringValue(json['identifier']));
  final files = (json['files'] as List<dynamic>?)
          ?.whereType<Map<dynamic, dynamic>>()
          .map((file) => _fileFromJson(file.cast<String, Object?>()))
          .toList(growable: false) ??
      const <InternetArchiveFile>[];

  if (identifier.isEmpty) {
    throw const FormatException(
      'Internet Archive metadata response is missing an identifier.',
    );
  }

  return InternetArchiveItem(
    identifier: identifier,
    title: _stringValue(metadata['title']),
    creator: _stringList(metadata['creator']).join(', '),
    description: _stringValue(metadata['description']),
    subjects: _stringList(metadata['subject']),
    collections: _stringList(metadata['collection']),
    year: _stringValue(metadata['year']).ifEmpty(_stringValue(metadata['date'])),
    licenseUrl: _stringValue(metadata['licenseurl']),
    files: files,
  );
}

InternetArchiveSearchResult? _searchResultFromJson(
  Map<String, Object?> json,
) {
  final identifier = _stringValue(json['identifier']);
  if (identifier.isEmpty) {
    return null;
  }

  return InternetArchiveSearchResult(identifier: identifier);
}

InternetArchiveFile _fileFromJson(Map<String, Object?> json) {
  return InternetArchiveFile(
    name: _stringValue(json['name']),
    format: _stringValue(json['format']),
    title: _stringValue(json['title']),
    source: _stringValue(json['source']),
    duration: _durationValue(json['length']),
  );
}

Future<String> _loadInternetArchiveJson(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, 'AetherTune/0.1');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Internet Archive request failed with HTTP ${response.statusCode}.',
        uri: uri,
      );
    }

    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}

Uri _downloadUri(Uri baseUri, String identifier, String fileName) {
  return baseUri.replace(
    path: _joinUriPath(
      baseUri.path,
      '/download/${Uri.encodeComponent(identifier)}/${_encodePath(fileName)}',
    ),
    queryParameters: const <String, String>{},
  );
}

Uri _imageUri(Uri baseUri, String identifier) {
  return baseUri.replace(
    path: _joinUriPath(
      baseUri.path,
      '/services/img/${Uri.encodeComponent(identifier)}',
    ),
    queryParameters: const <String, String>{},
  );
}

String _encodePath(String path) {
  return path.split('/').map(Uri.encodeComponent).join('/');
}

String _searchTerm(String query) {
  return query
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'[()]'), ' ')
      .trim();
}

Duration _durationValue(Object? value) {
  if (value is num) {
    return Duration(milliseconds: (value * 1000).round());
  }

  final string = _stringValue(value);
  if (string.isEmpty) {
    return Duration.zero;
  }

  final seconds = double.tryParse(string);
  if (seconds != null) {
    return Duration(milliseconds: (seconds * 1000).round());
  }

  final parts = string.split(':');
  final values = parts.map(int.tryParse).toList(growable: false);
  if (values.any((value) => value == null)) {
    return Duration.zero;
  }

  if (values.length == 2) {
    return Duration(minutes: values[0]!, seconds: values[1]!);
  }
  if (values.length == 3) {
    return Duration(
      hours: values[0]!,
      minutes: values[1]!,
      seconds: values[2]!,
    );
  }

  return Duration.zero;
}

String _stringValue(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is Iterable<Object?>) {
    return value.map(_stringValue).where((value) => value.isNotEmpty).join(', ');
  }

  return value.toString().trim();
}

List<String> _stringList(Object? value) {
  if (value == null) {
    return const <String>[];
  }
  if (value is Iterable<Object?>) {
    return value
        .map(_stringValue)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  final string = _stringValue(value);
  return string.isEmpty ? const <String>[] : <String>[string];
}

String _joinUriPath(String basePath, String childPath) {
  final normalizedBase = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  return '$normalizedBase$childPath';
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
