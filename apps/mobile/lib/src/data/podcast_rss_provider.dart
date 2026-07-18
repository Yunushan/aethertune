import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';
import '../domain/track_chapter.dart';

typedef PodcastFeedLoader = Future<String> Function(Uri feedUri);
typedef PodcastChapterLoader = Future<String> Function(Uri chapterUri);
typedef ExternalPodcastChapterUriApproval = bool Function(Uri chapterUri);

/// Privacy-bounded, process-local cache for explicitly approved third-party
/// Podcasting 2.0 chapter documents. It never persists document URLs or text.
final class PodcastExternalChapterDocumentCache {
  PodcastExternalChapterDocumentCache({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const maxDocuments = 32;
  static const maxDocumentCharacters = 64 * 1024;
  static const maxAge = Duration(hours: 6);

  final DateTime Function() _clock;
  final Map<Uri, _CachedPodcastChapterDocument> _documents =
      <Uri, _CachedPodcastChapterDocument>{};

  String? read(Uri uri) {
    final key = uri.removeFragment();
    final cached = _documents.remove(key);
    if (cached == null || _clock().difference(cached.cachedAt) >= maxAge) {
      return null;
    }
    _documents[key] = cached;
    return cached.document;
  }

  void write(Uri uri, String document) {
    if (document.length > maxDocumentCharacters) {
      return;
    }
    final key = uri.removeFragment();
    _documents.remove(key);
    while (_documents.length >= maxDocuments) {
      _documents.remove(_documents.keys.first);
    }
    _documents[key] = _CachedPodcastChapterDocument(
      document: document,
      cachedAt: _clock(),
    );
  }
}

final class _CachedPodcastChapterDocument {
  const _CachedPodcastChapterDocument({
    required this.document,
    required this.cachedAt,
  });

  final String document;
  final DateTime cachedAt;
}

class PodcastRssProvider implements MusicSourceProvider {
  static const maxExternalChapterDocumentsPerFeed = 20;
  static const maxUnapprovedExternalChapterHostsPerFeed = 8;
  static final PodcastExternalChapterDocumentCache _defaultChapterCache =
      PodcastExternalChapterDocumentCache();

  PodcastRssProvider({
    required this.feedUri,
    String? id,
    PodcastFeedLoader? feedLoader,
    PodcastChapterLoader? chapterLoader,
    ExternalPodcastChapterUriApproval? isExternalChapterUriApproved,
    PodcastExternalChapterDocumentCache? externalChapterDocumentCache,
  })  : id = id ?? 'podcast-${Track.stableLocalId(feedUri.toString())}',
        _feedLoader = feedLoader ?? _loadPodcastFeed,
        _chapterLoader = chapterLoader ?? _loadPodcastChapters,
        _isExternalChapterUriApproved =
            isExternalChapterUriApproved ?? _denyExternalChapterUri,
        _externalChapterDocumentCache =
            externalChapterDocumentCache ?? _defaultChapterCache;

  final Uri feedUri;
  final PodcastFeedLoader _feedLoader;
  final PodcastChapterLoader _chapterLoader;
  final ExternalPodcastChapterUriApproval _isExternalChapterUriApproved;
  final PodcastExternalChapterDocumentCache _externalChapterDocumentCache;

  @override
  final String id;

  @override
  String get name => 'Podcast RSS';

  @override
  String get description =>
      'RSS feed adapter for legal podcast and open audio feeds.';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.directPlayback,
        MusicSourceCapability.offlineCache,
        MusicSourceCapability.downloads,
        MusicSourceCapability.subscriptions,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => ProviderPrivacyDisclosure(
        networkDomains: feedUri.host.isEmpty ? const <String>[] : <String>[
          feedUri.host,
        ],
        dataSent: const <String>['feed request'],
        cachesMedia: true,
        supportsDownloads: true,
      );

  @override
  Future<List<Track>> search(String query) async {
    final feed = await fetchFeed();
    final normalized = query.trim().toLowerCase();
    final tracks = feed.episodes
        .map((episode) => episode.toTrack(sourceId: id, feed: feed))
        .where((track) {
      if (normalized.isEmpty) {
        return true;
      }

      return track.title.toLowerCase().contains(normalized) ||
          track.artist.toLowerCase().contains(normalized) ||
          track.album.toLowerCase().contains(normalized) ||
          track.genre.toLowerCase().contains(normalized);
    }).toList(growable: false);

    return tracks;
  }

  Future<PodcastRssFeed> fetchFeed() async {
    final xml = await _feedLoader(feedUri);
    final feed = parsePodcastRssFeed(xml, feedUri: feedUri);
    return _loadExternalChapters(feed);
  }

  Future<PodcastRssFeed> _loadExternalChapters(PodcastRssFeed feed) async {
    var remaining = maxExternalChapterDocumentsPerFeed;
    final episodes = <PodcastEpisode>[];
    final unapprovedHosts = <String>{};
    for (final episode in feed.episodes) {
      final chapterUri = episode.chapterUri;
      if (chapterUri == null || remaining <= 0) {
        episodes.add(episode);
        continue;
      }
      if (!_isApprovedChapterUri(chapterUri)) {
        final host = _unapprovedExternalChapterHost(chapterUri);
        if (host != null &&
            unapprovedHosts.length < maxUnapprovedExternalChapterHostsPerFeed) {
          unapprovedHosts.add(host);
        }
        episodes.add(episode);
        continue;
      }

      remaining -= 1;
      try {
        final cacheable = _isApprovedExternalChapterUri(chapterUri);
        final cachedDocument = cacheable
            ? _externalChapterDocumentCache.read(chapterUri)
            : null;
        final document = cachedDocument ?? await _chapterLoader(chapterUri);
        final chapters = parsePodcastingChapterDocument(
          document,
          maximum: episode.duration,
        );
        if (cacheable && cachedDocument == null) {
          _externalChapterDocumentCache.write(chapterUri, document);
        }
        episodes.add(
          episode.withChapters(
            TrackChapter.normalize(
              <TrackChapter>[...episode.chapters, ...chapters],
              maximum: episode.duration,
            ),
          ),
        );
      } on Object {
        episodes.add(episode);
      }
    }
    return feed.copyWith(
      episodes: episodes,
      unapprovedExternalChapterHosts: unapprovedHosts.toList()..sort(),
    );
  }

  bool _isApprovedChapterUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (uri.origin == feedUri.origin &&
        (scheme == 'http' || scheme == 'https')) {
      return true;
    }
    return _isApprovedExternalChapterUri(uri);
  }

  bool _isApprovedExternalChapterUri(Uri uri) =>
      uri.origin != feedUri.origin &&
      uri.scheme.toLowerCase() == 'https' &&
      _isExternalChapterUriApproved(uri);

  static bool _denyExternalChapterUri(Uri _) => false;

  String? _unapprovedExternalChapterHost(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.origin == feedUri.origin) {
      return null;
    }
    return uri.host.toLowerCase();
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    if (track.sourceId != id || track.streamUrl == null) {
      return null;
    }

    return Uri.tryParse(track.streamUrl!);
  }
}

final class PodcastRssFeed {
  const PodcastRssFeed({
    required this.feedUri,
    required this.title,
    required this.description,
    required this.author,
    required this.episodes,
    this.artworkUri,
    this.unapprovedExternalChapterHosts = const <String>[],
  });

  final Uri feedUri;
  final String title;
  final String description;
  final String author;
  final Uri? artworkUri;
  final List<PodcastEpisode> episodes;
  final List<String> unapprovedExternalChapterHosts;

  PodcastRssFeed copyWith({
    List<PodcastEpisode>? episodes,
    List<String>? unapprovedExternalChapterHosts,
  }) {
    return PodcastRssFeed(
      feedUri: feedUri,
      title: title,
      description: description,
      author: author,
      episodes: episodes ?? this.episodes,
      artworkUri: artworkUri,
      unapprovedExternalChapterHosts:
          unapprovedExternalChapterHosts ?? this.unapprovedExternalChapterHosts,
    );
  }
}

final class PodcastEpisode {
  const PodcastEpisode({
    required this.id,
    required this.title,
    required this.description,
    required this.author,
    required this.streamUri,
    required this.duration,
    this.chapters = const <TrackChapter>[],
    this.chapterUri,
    this.transcriptUri,
    this.transcriptType,
    this.transcriptLanguage,
    this.artworkUri,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String description;
  final String author;
  final Uri streamUri;
  final Duration duration;
  final List<TrackChapter> chapters;
  final Uri? chapterUri;
  final Uri? transcriptUri;
  final String? transcriptType;
  final String? transcriptLanguage;
  final Uri? artworkUri;
  final DateTime? publishedAt;

  Track toTrack({
    required String sourceId,
    required PodcastRssFeed feed,
  }) {
    return Track(
      id: Track.stableLocalId('$sourceId|$id|$streamUri'),
      title: title,
      artist: author.isEmpty ? feed.author : author,
      album: feed.title,
      genre: 'Podcast',
      duration: duration,
      chapters: chapters,
      transcriptUri: transcriptUri,
      transcriptType: transcriptType,
      transcriptLanguage: transcriptLanguage,
      artworkUri: artworkUri ?? feed.artworkUri,
      streamUrl: streamUri.toString(),
      sourceId: sourceId,
      addedAt: publishedAt,
    );
  }

  PodcastEpisode withChapters(List<TrackChapter> updatedChapters) {
    return PodcastEpisode(
      id: id,
      title: title,
      description: description,
      author: author,
      streamUri: streamUri,
      duration: duration,
      chapters: updatedChapters,
      chapterUri: chapterUri,
      transcriptUri: transcriptUri,
      transcriptType: transcriptType,
      transcriptLanguage: transcriptLanguage,
      artworkUri: artworkUri,
      publishedAt: publishedAt,
    );
  }
}

PodcastRssFeed parsePodcastRssFeed(
  String xml, {
  required Uri feedUri,
}) {
  try {
    final document = XmlDocument.parse(xml);
    final channel = _firstDescendant(document.rootElement, 'channel');
    if (channel == null) {
      throw const FormatException('Podcast RSS feed is missing a channel.');
    }

    final feedTitle = _childText(channel, 'title', fallback: 'Untitled feed');
    final feedAuthor = _childText(channel, 'author');
    final feed = PodcastRssFeed(
      feedUri: feedUri,
      title: feedTitle,
      description: _childText(channel, 'description'),
      author: feedAuthor,
      artworkUri: _imageUri(channel),
      episodes: _itemElements(channel)
          .map(
            (item) => _episodeFromItem(
              item,
              feedAuthor: feedAuthor,
            ),
          )
          .whereType<PodcastEpisode>()
          .toList(growable: false),
    );

    return feed;
  } on XmlParserException catch (error) {
    throw FormatException('Invalid podcast RSS XML: ${error.message}');
  }
}

Duration parsePodcastDuration(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return Duration.zero;
  }

  final parts = normalized.split(':');
  final values = parts.map(int.tryParse).toList(growable: false);
  if (values.any((value) => value == null)) {
    return Duration.zero;
  }

  if (values.length == 1) {
    return Duration(seconds: values[0]!);
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

PodcastEpisode? _episodeFromItem(
  XmlElement item, {
  required String feedAuthor,
}) {
  final enclosure = _firstChild(item, 'enclosure');
  final enclosureUrl = enclosure?.getAttribute('url')?.trim();
  final enclosureType = enclosure?.getAttribute('type')?.toLowerCase() ?? '';
  if (enclosureUrl == null ||
      enclosureUrl.isEmpty ||
      (enclosureType.isNotEmpty && !enclosureType.startsWith('audio/'))) {
    return null;
  }

  final streamUri = Uri.tryParse(enclosureUrl);
  if (streamUri == null) {
    return null;
  }

  final title = _childText(item, 'title', fallback: 'Untitled episode');
  final guid = _childText(item, 'guid', fallback: enclosureUrl);

  final duration = parsePodcastDuration(_childText(item, 'duration'));
  final transcript = _transcriptFromItem(item);
  return PodcastEpisode(
    id: guid,
    title: title,
    description: _childText(
      item,
      'description',
      fallback: _childText(item, 'summary'),
    ),
    author: _childText(item, 'author', fallback: feedAuthor),
    streamUri: streamUri,
    duration: duration,
    chapters: _inlineChapters(item, maximum: duration),
    chapterUri: _chapterDocumentUri(item),
    transcriptUri: transcript?.uri,
    transcriptType: transcript?.type,
    transcriptLanguage: transcript?.language,
    artworkUri: _imageUri(item),
    publishedAt: _parseRssDate(_childText(item, 'pubDate')),
  );
}

_PodcastTranscript? _transcriptFromItem(XmlElement item) {
  final transcript = _firstChild(item, 'transcript');
  final rawUri = transcript?.getAttribute('url')?.trim();
  final uri = rawUri == null || rawUri.isEmpty ? null : Uri.tryParse(rawUri);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https')) {
    return null;
  }
  final type = transcript?.getAttribute('type')?.trim();
  final language = transcript?.getAttribute('language')?.trim();
  return _PodcastTranscript(
    uri: uri,
    type: type == null || type.isEmpty ? null : type,
    language: language == null || language.isEmpty ? null : language,
  );
}

final class _PodcastTranscript {
  const _PodcastTranscript({
    required this.uri,
    this.type,
    this.language,
  });

  final Uri uri;
  final String? type;
  final String? language;
}

Uri? _chapterDocumentUri(XmlElement item) {
  final chapters = _firstChild(item, 'chapters');
  final value = chapters?.getAttribute('url')?.trim();
  final uri = value == null || value.isEmpty ? null : Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme.toLowerCase() != 'http' && uri.scheme.toLowerCase() != 'https')) {
    return null;
  }
  return uri;
}

List<TrackChapter> parsePodcastingChapterDocument(
  String document, {
  Duration maximum = Duration.zero,
}) {
  final decoded = jsonDecode(document);
  if (decoded is! Map || decoded['chapters'] is! List) {
    throw const FormatException('Podcast chapter document must contain chapters.');
  }

  final chapters = <TrackChapter>[];
  for (final value in decoded['chapters'] as List) {
    if (value is! Map) {
      continue;
    }
    final rawStart = value['startTime'];
    final seconds = rawStart is num
        ? rawStart.toDouble()
        : rawStart is String
            ? double.tryParse(rawStart.trim())
            : null;
    final title = value['title'];
    if (seconds == null || !seconds.isFinite || seconds < 0 || title is! String) {
      continue;
    }

    try {
      chapters.add(
        TrackChapter(
          start: Duration(
            microseconds: (seconds * Duration.microsecondsPerSecond).round(),
          ),
          title: title,
        ),
      );
    } on ArgumentError {
      continue;
    }
  }

  return TrackChapter.normalize(chapters, maximum: maximum);
}

List<TrackChapter> _inlineChapters(
  XmlElement item, {
  required Duration maximum,
}) {
  final chapters = <TrackChapter>[];
  for (final container in item.descendants.whereType<XmlElement>()) {
    if (container.name.local != 'chapters') {
      continue;
    }
    for (final chapter in container.childElements) {
      if (chapter.name.local != 'chapter') {
        continue;
      }

      final start = _parseChapterStart(chapter.getAttribute('start'));
      final title = (chapter.getAttribute('title') ??
              chapter.getAttribute('name') ??
              chapter.innerText)
          .trim();
      if (start == null || title.isEmpty) {
        continue;
      }

      try {
        chapters.add(TrackChapter(start: start, title: title));
      } on ArgumentError {
        continue;
      }
    }
  }

  return TrackChapter.normalize(chapters, maximum: maximum);
}

Duration? _parseChapterStart(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  final parts = normalized.split(':');
  if (parts.length < 2 || parts.length > 3) {
    return null;
  }

  final seconds = double.tryParse(parts.removeLast());
  final minutes = int.tryParse(parts.removeLast());
  final hours = parts.isEmpty ? 0 : int.tryParse(parts.single);
  if (seconds == null ||
      minutes == null ||
      hours == null ||
      seconds < 0 ||
      seconds >= 60 ||
      minutes < 0 ||
      minutes >= 60 ||
      hours < 0) {
    return null;
  }

  return Duration(
    microseconds:
        ((hours * Duration.microsecondsPerHour) +
                (minutes * Duration.microsecondsPerMinute) +
                (seconds * Duration.microsecondsPerSecond))
            .round(),
  );
}

Future<String> _loadPodcastFeed(Uri feedUri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(feedUri);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Podcast feed request failed with HTTP ${response.statusCode}.',
        uri: feedUri,
      );
    }

    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}

Future<String> _loadPodcastChapters(Uri chapterUri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(chapterUri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Podcast chapter request failed with HTTP ${response.statusCode}.',
        uri: chapterUri,
      );
    }

    return utf8.decodeStream(response);
  } finally {
    client.close(force: true);
  }
}

DateTime? _parseRssDate(String value) {
  if (value.trim().isEmpty) {
    return null;
  }

  try {
    return HttpDate.parse(value);
  } on FormatException {
    return DateTime.tryParse(value);
  }
}

Uri? _imageUri(XmlElement element) {
  final image = _firstChild(element, 'image');
  final href = image?.getAttribute('href') ?? _childText(image, 'url');
  if (href.trim().isEmpty) {
    return null;
  }

  return Uri.tryParse(href.trim());
}

Iterable<XmlElement> _itemElements(XmlElement channel) {
  return channel.childElements.where((element) => element.name.local == 'item');
}

XmlElement? _firstChild(XmlElement? element, String localName) {
  if (element == null) {
    return null;
  }

  for (final child in element.childElements) {
    if (child.name.local == localName) {
      return child;
    }
  }

  return null;
}

XmlElement? _firstDescendant(XmlElement element, String localName) {
  if (element.name.local == localName) {
    return element;
  }

  for (final child in element.childElements) {
    final match = _firstDescendant(child, localName);
    if (match != null) {
      return match;
    }
  }

  return null;
}

String _childText(
  XmlElement? element,
  String localName, {
  String fallback = '',
}) {
  final child = _firstChild(element, localName);
  final text = child?.innerText.trim() ?? '';
  return text.isEmpty ? fallback : text;
}
