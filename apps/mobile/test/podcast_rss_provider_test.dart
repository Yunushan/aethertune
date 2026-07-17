import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/podcast_rss_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';

void main() {
  test('parses podcast RSS episodes into playable tracks', () {
    final feed = parsePodcastRssFeed(
      _samplePodcastFeed,
      feedUri: Uri.parse('https://feeds.example.test/aether.xml'),
    );

    expect(feed.title, 'Aether Radio');
    expect(feed.author, 'Aether Hosts');
    expect(feed.artworkUri, Uri.parse('https://media.example.test/show.jpg'));
    expect(feed.episodes, hasLength(1));

    final episode = feed.episodes.single;
    expect(episode.title, 'Open Audio Episode');
    expect(episode.author, 'Guest Host');
    expect(episode.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(episode.chapters.map((chapter) => chapter.title), <String>[
      'Introduction',
      'Interview',
    ]);
    expect(
      episode.chapters[1].start,
      const Duration(minutes: 10, seconds: 30, milliseconds: 500),
    );
    expect(episode.publishedAt, DateTime.utc(2026, 7, 6, 10));

    final track = episode.toTrack(sourceId: 'podcast-test', feed: feed);
    expect(track.title, 'Open Audio Episode');
    expect(track.artist, 'Guest Host');
    expect(track.album, 'Aether Radio');
    expect(track.genre, 'Podcast');
    expect(track.isPlayable, isTrue);
    expect(track.streamUrl, 'https://media.example.test/episode-1.mp3');
    expect(track.chapters, episode.chapters);
  });

  test('search loads the feed locally and resolves episode streams', () async {
    final provider = PodcastRssProvider(
      feedUri: Uri.parse('https://feeds.example.test/aether.xml'),
      feedLoader: (_) async => _samplePodcastFeed,
    );

    expect(
      provider.capabilities,
      containsAll(const <MusicSourceCapability>[
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.directPlayback,
        MusicSourceCapability.offlineCache,
        MusicSourceCapability.downloads,
        MusicSourceCapability.subscriptions,
      ]),
    );
    expect(provider.disclosure.networkDomains, <String>['feeds.example.test']);
    expect(provider.disclosure.dataSent, <String>['feed request']);
    expect(provider.disclosure.cachesMedia, isTrue);
    expect(provider.disclosure.supportsDownloads, isTrue);

    final results = await provider.search('open audio');

    expect(results, hasLength(1));
    expect(
      await provider.resolveStream(results.single),
      Uri.parse('https://media.example.test/episode-1.mp3'),
    );
  });

  test('fetches feed metadata for subscription UI', () async {
    final provider = PodcastRssProvider(
      feedUri: Uri.parse('https://feeds.example.test/aether.xml'),
      feedLoader: (_) async => _samplePodcastFeed,
    );

    final feed = await provider.fetchFeed();

    expect(feed.title, 'Aether Radio');
    expect(feed.description, 'Open podcast feed.');
    expect(feed.episodes.single.title, 'Open Audio Episode');
  });

  test('loads same-origin Podcasting 2.0 chapter documents', () async {
    final requestedUris = <Uri>[];
    final provider = PodcastRssProvider(
      feedUri: Uri.parse('https://feeds.example.test/aether.xml'),
      feedLoader: (_) async => _externalChapterPodcastFeed,
      chapterLoader: (uri) async {
        requestedUris.add(uri);
        return '''
          {"version":"1.2.0","chapters":[
            {"startTime":0,"title":"Opening"},
            {"startTime":30.5,"title":"Topic"},
            {"startTime":120,"title":"Too late"},
            {"startTime":"bad","title":"Malformed"}
          ]}
        ''';
      },
    );

    final feed = await provider.fetchFeed();

    expect(requestedUris, <Uri>[Uri.parse('https://feeds.example.test/chapters.json')]);
    expect(feed.episodes.single.chapters.map((chapter) => chapter.title), <String>[
      'Opening',
      'Topic',
    ]);
    expect(
      feed.episodes.single.chapters[1].start,
      const Duration(seconds: 30, milliseconds: 500),
    );
  });

  test('does not request external chapter URLs outside the feed origin', () async {
    var chapterRequests = 0;
    final provider = PodcastRssProvider(
      feedUri: Uri.parse('https://feeds.example.test/aether.xml'),
      feedLoader: (_) async => _crossOriginChapterPodcastFeed,
      chapterLoader: (_) async {
        chapterRequests += 1;
        return '{}';
      },
    );

    final feed = await provider.fetchFeed();

    expect(chapterRequests, 0);
    expect(feed.episodes.single.chapters, isEmpty);
  });

  test('loads approved HTTPS external chapter URLs', () async {
    final requestedUris = <Uri>[];
    final provider = PodcastRssProvider(
      feedUri: Uri.parse('https://feeds.example.test/aether.xml'),
      feedLoader: (_) async => _crossOriginChapterPodcastFeed,
      chapterLoader: (uri) async {
        requestedUris.add(uri);
        return '''
          {"version":"1.2.0","chapters":[
            {"startTime":0,"title":"Approved opening"}
          ]}
        ''';
      },
      isExternalChapterUriApproved: (uri) =>
          uri.host == 'cdn.example.test' && uri.scheme == 'https',
    );

    final feed = await provider.fetchFeed();

    expect(requestedUris, <Uri>[Uri.parse('https://cdn.example.test/chapters.json')]);
    expect(
      feed.episodes.single.chapters.map((chapter) => chapter.title),
      <String>['Approved opening'],
    );
  });

  test('rejects malformed external chapter documents', () {
    expect(
      () => parsePodcastingChapterDocument('{"version":"1.2"}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('duration parser accepts common RSS formats', () {
    expect(parsePodcastDuration('3723'), const Duration(seconds: 3723));
    expect(parsePodcastDuration('02:03'), const Duration(minutes: 2, seconds: 3));
    expect(
      parsePodcastDuration('01:02:03'),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(parsePodcastDuration('not a duration'), Duration.zero);
  });
}

const _samplePodcastFeed = '''
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:psc="http://podlove.org/simple-chapters">
  <channel>
    <title>Aether Radio</title>
    <description>Open podcast feed.</description>
    <itunes:author>Aether Hosts</itunes:author>
    <itunes:image href="https://media.example.test/show.jpg" />
    <item>
      <guid>episode-1</guid>
      <title>Open Audio Episode</title>
      <description>Playable open audio.</description>
      <itunes:author>Guest Host</itunes:author>
      <itunes:duration>01:02:03</itunes:duration>
      <psc:chapters version="1.2">
        <psc:chapter start="00:00:00.000" title="Introduction" />
        <psc:chapter start="00:10:30.500" title="Interview" />
        <psc:chapter start="01:02:03.000" title="After the end" />
        <psc:chapter start="bad" title="Malformed" />
      </psc:chapters>
      <pubDate>Mon, 06 Jul 2026 10:00:00 GMT</pubDate>
      <enclosure
        url="https://media.example.test/episode-1.mp3"
        length="123"
        type="audio/mpeg" />
    </item>
    <item>
      <guid>video-1</guid>
      <title>Video Episode</title>
      <enclosure
        url="https://media.example.test/episode-2.mp4"
        length="456"
        type="video/mp4" />
    </item>
  </channel>
</rss>
''';

const _externalChapterPodcastFeed = '''
<rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0">
  <channel>
    <title>External chapters</title>
    <item>
      <guid>external-chapter-episode</guid>
      <title>External chapter episode</title>
      <itunes:duration xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">00:02:00</itunes:duration>
      <podcast:chapters url="https://feeds.example.test/chapters.json" type="application/json" />
      <enclosure url="https://media.example.test/episode.mp3" type="audio/mpeg" />
    </item>
  </channel>
</rss>
''';

const _crossOriginChapterPodcastFeed = '''
<rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0">
  <channel>
    <title>Cross origin chapters</title>
    <item>
      <guid>cross-origin-chapter-episode</guid>
      <title>Cross origin chapter episode</title>
      <itunes:duration xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">00:02:00</itunes:duration>
      <podcast:chapters url="https://cdn.example.test/chapters.json" type="application/json" />
      <enclosure url="https://media.example.test/episode.mp3" type="audio/mpeg" />
    </item>
  </channel>
</rss>
''';
