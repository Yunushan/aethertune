import 'dart:convert';
import 'dart:io';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef InternetArchiveSearchLoader = Future<String> Function(Uri searchUri);
typedef InternetArchiveMetadataLoader = Future<String> Function(
  Uri metadataUri,
);

final class InternetArchiveSearchFilters {
  const InternetArchiveSearchFilters({
    this.collection = '',
    this.subject = '',
    this.creator = '',
    this.year = '',
  });

  final String collection;
  final String subject;
  final String creator;
  final String year;

  bool get isEmpty =>
      collection.trim().isEmpty &&
      subject.trim().isEmpty &&
      creator.trim().isEmpty &&
      year.trim().isEmpty;
}

final class InternetArchiveAudioSearchPage {
  const InternetArchiveAudioSearchPage({
    required this.items,
    required this.tracks,
    required this.facets,
    required this.page,
    required this.totalResults,
    required this.hasMore,
  });

  final List<InternetArchiveItem> items;
  final List<Track> tracks;
  final List<InternetArchiveFacet> facets;
  final int page;
  final int? totalResults;
  final bool hasMore;

  List<InternetArchiveFacet> facetsFor(String field) {
    return facets
        .where((facet) => facet.field == field)
        .toList(growable: false);
  }
}

class InternetArchiveProvider
    implements
        MusicSourceSearchPagingProvider,
        MusicSourceSearchSuggestionProvider {
  InternetArchiveProvider({
    Uri? baseUri,
    InternetArchiveSearchLoader? searchLoader,
    InternetArchiveMetadataLoader? metadataLoader,
    this.limit = 10,
  })  : assert(limit > 0),
        baseUri = baseUri ?? Uri.parse('https://archive.org'),
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
        MusicSourceCapability.searchSuggestions,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.directPlayback,
        MusicSourceCapability.offlineCache,
        MusicSourceCapability.downloads,
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
        cachesMedia: true,
        supportsDownloads: true,
      );

  @override
  Future<List<Track>> search(String query) async {
    return searchAudio(query);
  }

  @override
  Future<List<MusicSourceSearchSuggestion>> suggest(
    String query, {
    int limit = 8,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return const <MusicSourceSearchSuggestion>[];
    }
    final results = parseInternetArchiveSearchPage(
      await _searchLoader(
        _searchUri(
          normalized,
          const InternetArchiveSearchFilters(),
          includeFacets: false,
          page: 1,
          rowLimit: limit.clamp(1, 50),
        ),
      ),
    );
    final seen = <String>{};
    final suggestions = <MusicSourceSearchSuggestion>[];
    for (final result in results.results) {
      final value = result.title.isEmpty ? result.identifier : result.title;
      if (value.isEmpty || !seen.add(value.toLowerCase())) {
        continue;
      }
      final details = <String>[
        if (result.creator.isNotEmpty) result.creator,
        if (result.collection.isNotEmpty) result.collection,
      ];
      suggestions.add(
        MusicSourceSearchSuggestion(
          value: value,
          kind: MusicSourceSearchSuggestionKind.album,
          subtitle: details.isEmpty ? 'Internet Archive item' : details.join(' / '),
        ),
      );
      if (suggestions.length >= limit) {
        break;
      }
    }
    return List<MusicSourceSearchSuggestion>.unmodifiable(suggestions);
  }

  Future<List<Track>> searchAudio(
    String query, {
    InternetArchiveSearchFilters filters = const InternetArchiveSearchFilters(),
  }) async {
    final page = await searchAudioPage(
      query,
      filters: filters,
      includeFacets: false,
    );

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
    final requestedPage = _archiveSearchPage(cursor);
    final page = await searchAudioPage(
      query,
      includeFacets: false,
      page: requestedPage,
      pageSize: limit.clamp(1, 50),
    );
    return MusicSourceSearchPage(
      tracks: List<Track>.unmodifiable(page.tracks),
      nextCursor: page.hasMore ? (page.page + 1).toString() : null,
      totalCount: page.totalResults,
    );
  }

  Future<InternetArchiveAudioSearchPage> searchAudioPage(
    String query, {
    InternetArchiveSearchFilters filters = const InternetArchiveSearchFilters(),
    bool? includeFacets,
    int page = 1,
    int? pageSize,
  }) async {
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'Must be at least 1.');
    }
    final effectiveLimit = pageSize ?? limit;
    if (effectiveLimit <= 0) {
      throw ArgumentError.value(
        effectiveLimit,
        'pageSize',
        'Must be positive.',
      );
    }

    final results = parseInternetArchiveSearchPage(
      await _searchLoader(
        _searchUri(
          query.trim(),
          filters,
          includeFacets: includeFacets ?? page == 1,
          page: page,
          rowLimit: effectiveLimit,
        ),
      ),
    );
    final items = <InternetArchiveItem>[];
    final tracks = <Track>[];

    for (final result in results.results.take(effectiveLimit)) {
      final item = await fetchItem(result.identifier);
      items.add(item);
      tracks.addAll(item.toTracks(sourceId: id, baseUri: baseUri));
    }

    return InternetArchiveAudioSearchPage(
      items: items,
      tracks: tracks,
      facets: results.facets,
      page: page,
      totalResults: results.totalResults,
      hasMore: _hasMoreResults(
        results,
        page: page,
        limit: effectiveLimit,
      ),
    );
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

  Uri _searchUri(
    String query,
    InternetArchiveSearchFilters filters, {
    required bool includeFacets,
    required int page,
    required int rowLimit,
  }) {
    final archiveQuery = _searchQuery(query, filters);
    final queryParameters = <String, dynamic>{
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
      'rows': rowLimit.toString(),
      'page': page.toString(),
      'output': 'json',
    };
    if (includeFacets) {
      queryParameters['facet[]'] = const <String>[
        'collection',
        'subject',
        'creator',
        'year',
      ];
    }

    return baseUri.replace(
      path: _joinUriPath(baseUri.path, '/advancedsearch.php'),
      queryParameters: queryParameters,
    );
  }

  Uri _metadataUri(String identifier) {
    return baseUri.replace(
      path: _joinUriPath(
        baseUri.path,
        '/metadata/${Uri.encodeComponent(identifier)}',
      ),
    );
  }
}

int _archiveSearchPage(String? cursor) {
  if (cursor == null) {
    return 1;
  }
  final page = int.tryParse(cursor);
  if (page == null || page < 1) {
    throw ArgumentError.value(cursor, 'cursor', 'Invalid search cursor.');
  }
  return page;
}

final class InternetArchiveSearchPage {
  const InternetArchiveSearchPage({
    required this.results,
    required this.facets,
    required this.totalResults,
  });

  final List<InternetArchiveSearchResult> results;
  final List<InternetArchiveFacet> facets;
  final int? totalResults;

  List<InternetArchiveFacet> facetsFor(String field) {
    return facets
        .where((facet) => facet.field == field)
        .toList(growable: false);
  }
}

final class InternetArchiveSearchResult {
  const InternetArchiveSearchResult({
    required this.identifier,
    this.title = '',
    this.creator = '',
    this.collection = '',
  });

  final String identifier;
  final String title;
  final String creator;
  final String collection;
}

final class InternetArchiveFacet {
  const InternetArchiveFacet({
    required this.field,
    required this.value,
    required this.count,
  });

  final String field;
  final String value;
  final int count;
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

    return _toTrack(
      audioFile: audioFile,
      sourceId: sourceId,
      baseUri: baseUri,
      includeFileTitle: false,
    );
  }

  List<Track> toTracks({
    required String sourceId,
    required Uri baseUri,
  }) {
    final playable = files
        .where((file) => file.isPlayableAudio)
        .toList(growable: false)
      ..sort(
        (left, right) => left.playbackPriority.compareTo(
          right.playbackPriority,
        ),
      );

    return playable
        .map(
          (file) => _toTrack(
            audioFile: file,
            sourceId: sourceId,
            baseUri: baseUri,
            includeFileTitle: playable.length > 1,
          ),
        )
        .toList(growable: false);
  }

  Track _toTrack({
    required InternetArchiveFile audioFile,
    required String sourceId,
    required Uri baseUri,
    required bool includeFileTitle,
  }) {
    final genre = subjects.isEmpty ? 'Internet Archive Audio' : subjects.first;
    final albumParts = <String>[
      'Internet Archive',
      if (year.isNotEmpty) year,
    ];
    final itemTitle = title.isEmpty ? audioFile.displayTitle : title;
    final trackTitle = includeFileTitle && title.isNotEmpty
        ? '$itemTitle - ${audioFile.displayTitle}'
        : itemTitle;

    return Track(
      id: Track.stableLocalId('$sourceId|$identifier|${audioFile.name}'),
      title: trackTitle,
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
  return parseInternetArchiveSearchPage(jsonText).results;
}

InternetArchiveSearchPage parseInternetArchiveSearchPage(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException(
      'Internet Archive search response must be a map.',
    );
  }

  final response = decoded['response'];
  if (response is! Map<dynamic, dynamic>) {
    return const InternetArchiveSearchPage(
      results: <InternetArchiveSearchResult>[],
      facets: <InternetArchiveFacet>[],
      totalResults: null,
    );
  }

  final docs = response['docs'];
  if (docs is! List<dynamic>) {
    return const InternetArchiveSearchPage(
      results: <InternetArchiveSearchResult>[],
      facets: <InternetArchiveFacet>[],
      totalResults: null,
    );
  }

  final results = docs
      .whereType<Map<dynamic, dynamic>>()
      .map((json) => _searchResultFromJson(json.cast<String, Object?>()))
      .whereType<InternetArchiveSearchResult>()
      .toList(growable: false);
  final facetsJson = response['facets'] ?? decoded['facets'];
  final facets = _facetsFromJson(facetsJson);

  return InternetArchiveSearchPage(
    results: results,
    facets: facets,
    totalResults: _nullableNonNegativeInt(response['numFound']),
  );
}

bool _hasMoreResults(
  InternetArchiveSearchPage results, {
  required int page,
  required int limit,
}) {
  final totalResults = results.totalResults;
  if (totalResults != null) {
    return ((page - 1) * limit) + results.results.length < totalResults;
  }

  return results.results.length >= limit;
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

  return InternetArchiveSearchResult(
    identifier: identifier,
    title: _stringValue(json['title']),
    creator: _stringList(json['creator']).join(', '),
    collection: _stringList(json['collection']).join(', '),
  );
}

List<InternetArchiveFacet> _facetsFromJson(Object? value) {
  if (value is! Map<dynamic, dynamic>) {
    return const <InternetArchiveFacet>[];
  }

  final facets = <InternetArchiveFacet>[];
  for (final entry in value.entries) {
    final field = _stringValue(entry.key);
    final counts = entry.value;
    if (field.isEmpty || counts is! Map<dynamic, dynamic>) {
      continue;
    }

    for (final countEntry in counts.entries) {
      final facetValue = _stringValue(countEntry.key);
      final count = _intValue(countEntry.value);
      if (facetValue.isEmpty || count <= 0) {
        continue;
      }

      facets.add(
        InternetArchiveFacet(
          field: field,
          value: facetValue,
          count: count,
        ),
      );
    }
  }

  return facets;
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
  );
}

Uri _imageUri(Uri baseUri, String identifier) {
  return baseUri.replace(
    path: _joinUriPath(
      baseUri.path,
      '/services/img/${Uri.encodeComponent(identifier)}',
    ),
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

String _searchQuery(String query, InternetArchiveSearchFilters filters) {
  final parts = <String>['mediatype:audio'];
  final normalizedQuery = _searchTerm(query);
  if (normalizedQuery.isNotEmpty) {
    parts.add('($normalizedQuery)');
  }

  void addField(String field, String value) {
    final normalized = _searchTerm(value);
    if (normalized.isNotEmpty) {
      parts.add('$field:($normalized)');
    }
  }

  addField('collection', filters.collection);
  addField('subject', filters.subject);
  addField('creator', filters.creator);
  addField('year', filters.year);

  return parts.join(' AND ');
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

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }

  return int.tryParse(_stringValue(value)) ?? 0;
}

int? _nullableNonNegativeInt(Object? value) {
  if (value == null) {
    return null;
  }

  final parsed = switch (value) {
    num number => number.toInt(),
    _ => int.tryParse(value.toString().trim()),
  };
  if (parsed == null || parsed < 0) {
    return null;
  }

  return parsed;
}

String _stringValue(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is Iterable) {
    return value.map(_stringValue).where((value) => value.isNotEmpty).join(', ');
  }

  return value.toString().trim();
}

List<String> _stringList(Object? value) {
  if (value == null) {
    return const <String>[];
  }
  if (value is Iterable) {
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
