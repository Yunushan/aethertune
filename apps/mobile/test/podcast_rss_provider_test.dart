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
    expect(episode.publishedAt, DateTime.utc(2026, 7, 6, 10));

    final track = episode.toTrack(sourceId: 'podcast-test', feed: feed);
    expect(track.title, 'Open Audio Episode');
    expect(track.artist, 'Guest Host');
    expect(track.album, 'Aether Radio');
    expect(track.genre, 'Podcast');
    expect(track.isPlayable, isTrue);
    expect(track.streamUrl, 'https://media.example.test/episode-1.mp3');
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
        MusicSourceCapability.subscriptions,
      ]),
    );
    expect(provider.disclosure.networkDomains, <String>['feeds.example.test']);
    expect(provider.disclosure.dataSent, <String>['feed request']);

    final results = await provider.search('open audio');

    expect(results, hasLength(1));
    expect(
      await provider.resolveStream(results.single),
      Uri.parse('https://media.example.test/episode-1.mp3'),
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
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
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
