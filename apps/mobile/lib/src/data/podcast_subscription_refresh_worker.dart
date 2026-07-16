import '../domain/podcast_subscription.dart';
import 'library_store.dart';
import 'podcast_rss_provider.dart';

typedef PodcastFeedFetcher = Future<PodcastRssFeed> Function(Uri feedUri);

final class PodcastRefreshReport {
  const PodcastRefreshReport({
    required this.refreshedCount,
    required this.failedCount,
    required this.skippedCount,
  });

  const PodcastRefreshReport.empty()
    : refreshedCount = 0,
      failedCount = 0,
      skippedCount = 0;

  final int refreshedCount;
  final int failedCount;
  final int skippedCount;

  int get attemptedCount => refreshedCount + failedCount;
}

/// Refreshes persisted RSS subscriptions without allowing one bad feed to stop
/// the remaining eligible feeds.
final class PodcastSubscriptionRefreshWorker {
  PodcastSubscriptionRefreshWorker({
    PodcastFeedFetcher? feedFetcher,
    DateTime Function()? clock,
  }) : _feedFetcher = feedFetcher ?? _fetchFeed,
       _clock = clock ?? DateTime.now;

  final PodcastFeedFetcher _feedFetcher;
  final DateTime Function() _clock;

  Future<PodcastRefreshReport> refreshDue(LibraryStore library) {
    return refreshSubscriptions(
      library,
      subscriptions: library.podcastSubscriptions,
      dueOnly: true,
    );
  }

  Future<PodcastRefreshReport> refreshSubscriptions(
    LibraryStore library, {
    required Iterable<PodcastSubscription> subscriptions,
    bool dueOnly = false,
  }) async {
    if (!library.loaded || library.offlineModeEnabled) {
      return const PodcastRefreshReport.empty();
    }

    var refreshed = 0;
    var failed = 0;
    var skipped = 0;
    final now = _clock();

    for (final requestedSubscription in subscriptions) {
      final subscription = library.podcastSubscriptionById(
        requestedSubscription.id,
      );
      if (subscription == null ||
          (dueOnly && !subscription.isRefreshDue(now))) {
        skipped += 1;
        continue;
      }

      final feedUri = Uri.tryParse(subscription.feedUrl);
      if (feedUri == null ||
          feedUri.host.isEmpty ||
          (feedUri.scheme != 'http' && feedUri.scheme != 'https')) {
        failed += 1;
        await library.markPodcastSubscriptionFetchFailed(
          subscription.id,
          'Saved feed URL is invalid.',
        );
        continue;
      }

      try {
        final feed = await _feedFetcher(feedUri);
        if (library.podcastSubscriptionById(subscription.id) == null) {
          skipped += 1;
          continue;
        }
        final provider = PodcastRssProvider(feedUri: feedUri);
        final episodes = feed.episodes
            .map(
              (episode) => episode.toTrack(sourceId: provider.id, feed: feed),
            )
            .toList(growable: false);
        final saved = await library.savePodcastSubscription(
          PodcastSubscription(
            id: subscription.id,
            feedUrl: feed.feedUri.toString(),
            title: feed.title,
            description: feed.description,
            author: feed.author,
            artworkUri: feed.artworkUri,
            episodes: episodes,
          ),
        );
        await library.markPodcastSubscriptionFetched(saved.id);
        refreshed += 1;
      } catch (error) {
        failed += 1;
        await library.markPodcastSubscriptionFetchFailed(
          subscription.id,
          error,
        );
      }
    }

    return PodcastRefreshReport(
      refreshedCount: refreshed,
      failedCount: failed,
      skippedCount: skipped,
    );
  }

  static Future<PodcastRssFeed> _fetchFeed(Uri feedUri) {
    return PodcastRssProvider(feedUri: feedUri).fetchFeed();
  }
}
