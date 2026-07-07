import 'package:xml/xml.dart';

import 'podcast_subscription.dart';

List<PodcastSubscription> parsePodcastOpml(String document) {
  final parsed = XmlDocument.parse(document);
  final subscriptions = <PodcastSubscription>[];

  for (final outline in parsed.descendants.whereType<XmlElement>()) {
    if (outline.name.local != 'outline') {
      continue;
    }

    final feedUrl = outline.getAttribute('xmlUrl')?.trim();
    if (feedUrl == null || feedUrl.isEmpty) {
      continue;
    }

    final title = _firstNonEmpty(<String?>[
      outline.getAttribute('title'),
      outline.getAttribute('text'),
      feedUrl,
    ]);

    subscriptions.add(
      PodcastSubscription(
        id: stablePodcastSubscriptionId(feedUrl),
        feedUrl: feedUrl,
        title: title,
        description: outline.getAttribute('description')?.trim() ?? '',
        author: outline.getAttribute('ownerName')?.trim() ?? '',
      ),
    );
  }

  return _dedupeSubscriptions(subscriptions);
}

String exportPodcastOpml(
  Iterable<PodcastSubscription> subscriptions, {
  DateTime? exportedAt,
}) {
  final builder = XmlBuilder();
  builder.element(
    'opml',
    attributes: <String, String>{'version': '2.0'},
    nest: () {
      builder.element(
        'head',
        nest: () {
          builder.element('title', nest: 'AetherTune Podcast Subscriptions');
          builder.element(
            'dateCreated',
            nest: (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
          );
        },
      );
      builder.element(
        'body',
        nest: () {
          for (final subscription in subscriptions) {
            builder.element(
              'outline',
              attributes: <String, String>{
                'type': 'rss',
                'text': subscription.title,
                'title': subscription.title,
                'xmlUrl': subscription.feedUrl,
                if (subscription.description.isNotEmpty)
                  'description': subscription.description,
                if (subscription.author.isNotEmpty)
                  'ownerName': subscription.author,
              },
            );
          }
        },
      );
    },
  );

  return builder.buildDocument().toXmlString(pretty: true);
}

List<PodcastSubscription> _dedupeSubscriptions(
  Iterable<PodcastSubscription> subscriptions,
) {
  final byId = <String, PodcastSubscription>{};
  for (final subscription in subscriptions) {
    byId[stablePodcastSubscriptionId(subscription.feedUrl)] = subscription;
  }

  return byId.values.toList(growable: false);
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
  }

  return 'Untitled podcast';
}
