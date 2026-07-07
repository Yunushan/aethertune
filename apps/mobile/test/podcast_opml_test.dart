import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:aethertune/src/domain/podcast_opml.dart';
import 'package:aethertune/src/domain/podcast_subscription.dart';

void main() {
  test('parses podcast subscriptions from nested OPML outlines', () {
    final subscriptions = parsePodcastOpml('''
<opml version="2.0">
  <body>
    <outline text="Technology">
      <outline
        text="Aether Radio"
        title="Aether Radio"
        xmlUrl="https://feeds.example.test/aether.xml"
        description="Open audio feed"
        ownerName="Aether Hosts" />
      <outline text="Missing URL" />
    </outline>
    <outline
      text="Duplicate"
      xmlUrl="https://feeds.example.test/aether.xml" />
    <outline
      text="Second Feed"
      xmlUrl="https://feeds.example.test/second.xml" />
  </body>
</opml>
''');

    expect(subscriptions, hasLength(2));
    expect(subscriptions.first.title, 'Duplicate');
    expect(subscriptions.first.feedUrl, 'https://feeds.example.test/aether.xml');
    expect(subscriptions.last.title, 'Second Feed');
    expect(subscriptions.last.feedUrl, 'https://feeds.example.test/second.xml');
  });

  test('exports podcast subscriptions as OPML and parses them back', () {
    final opml = exportPodcastOpml(
      <PodcastSubscription>[
        PodcastSubscription(
          id: 'one',
          feedUrl: 'https://feeds.example.test/aether.xml',
          title: 'Aether & Radio',
          description: 'Open feed',
          author: 'Aether Hosts',
        ),
      ],
      exportedAt: DateTime.utc(2026, 7, 7),
    );

    expect(opml, contains('AetherTune Podcast Subscriptions'));
    expect(opml, contains('https://feeds.example.test/aether.xml'));

    final parsed = parsePodcastOpml(opml);

    expect(parsed.single.title, 'Aether & Radio');
    expect(parsed.single.description, 'Open feed');
    expect(parsed.single.author, 'Aether Hosts');
  });

  test('rejects invalid OPML XML', () {
    expect(
      () => parsePodcastOpml('<opml>'),
      throwsA(isA<XmlParserException>()),
    );
  });
}
