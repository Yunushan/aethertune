import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef PodcastFeedLoader = Future<String> Function(Uri feedUri);

class PodcastRssProvider implements MusicSourceProvider {
  PodcastRssProvider({
    required this.feedUri,
    String? id,
    PodcastFeedLoader? feedLoader,
  })  : id = id ?? 'podcast-${Track.stableLocalId(feedUri.toString())}',
        _feedLoader = feedLoader ?? _loadPodcastFeed;

  final Uri feedUri;
  final PodcastFeedLoader _feedLoader;

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

  Future<PodcastRssFeed> fetchFeed() {
    return _feedLoader(feedUri).then(
      (xml) => parsePodcastRssFeed(xml, feedUri: feedUri),
    );
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
  });

  final Uri feedUri;
  final String title;
  final String description;
  final String author;
  final Uri? artworkUri;
  final List<PodcastEpisode> episodes;
}

final class PodcastEpisode {
  const PodcastEpisode({
    required this.id,
    required this.title,
    required this.description,
    required this.author,
    required this.streamUri,
    required this.duration,
    this.artworkUri,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String description;
  final String author;
  final Uri streamUri;
  final Duration duration;
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
      artworkUri: artworkUri ?? feed.artworkUri,
      streamUrl: streamUri.toString(),
      sourceId: sourceId,
      addedAt: publishedAt,
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
    duration: parsePodcastDuration(_childText(item, 'duration')),
    artworkUri: _imageUri(item),
    publishedAt: _parseRssDate(_childText(item, 'pubDate')),
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
