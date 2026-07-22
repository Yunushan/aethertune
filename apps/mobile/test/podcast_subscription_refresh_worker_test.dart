import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/offline_cache_background_runner.dart';
import 'package:aethertune/src/data/podcast_rss_provider.dart';
import 'package:aethertune/src/data/podcast_subscription_refresh_worker.dart';
import 'package:aethertune/src/domain/podcast_subscription.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/podcast_rss_refresh_worker.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'refreshes only due feeds and continues after individual failures',
    () async {
      final now = DateTime.utc(2026, 7, 16, 12);
      final library = LibraryStore(clock: () => now);
      await library.load();
      final due = await _saveSubscription(
        library,
        feedUrl: 'https://feeds.example.test/due.xml',
        lastFetchedAt: now.subtract(defaultPodcastRefreshInterval),
      );
      final fresh = await _saveSubscription(
        library,
        feedUrl: 'https://feeds.example.test/fresh.xml',
        lastFetchedAt: now.subtract(const Duration(hours: 1)),
      );
      final failing = await _saveSubscription(
        library,
        feedUrl: 'https://feeds.example.test/failing.xml',
      );
      final invalid = await _saveSubscription(
        library,
        feedUrl: 'file:///private/feed.xml',
      );

      final requestedUris = <Uri>[];
      final worker = PodcastSubscriptionRefreshWorker(
        clock: () => now,
        feedFetcher: (uri) async {
          requestedUris.add(uri);
          if (uri.path.endsWith('failing.xml')) {
            throw StateError('feed unavailable');
          }
          return _feed(uri);
        },
      );

      final report = await worker.refreshDue(library);

      expect(report.refreshedCount, 1);
      expect(report.failedCount, 2);
      expect(report.skippedCount, 1);
      expect(requestedUris.map((uri) => uri.path), <String>[
        '/due.xml',
        '/failing.xml',
      ]);
      expect(
        library.podcastSubscriptionById(due.id)!.episodes.single.title,
        'Fresh episode',
      );
      expect(library.podcastSubscriptionById(due.id)!.lastFetchedAt, now);
      expect(
        library.podcastSubscriptionById(fresh.id)!.lastFetchedAt,
        fresh.lastFetchedAt,
      );
      expect(
        library.podcastSubscriptionById(failing.id)!.lastFetchError,
        contains('feed unavailable'),
      );
      expect(
        library.podcastSubscriptionById(invalid.id)!.lastFetchError,
        'Saved feed URL is invalid.',
      );
    },
  );

  test('refreshes due feeds from an authorized background pass', () async {
    final now = DateTime.utc(2026, 7, 16, 12);
    final library = LibraryStore(clock: () => now);
    await library.load();
    final subscription = await _saveSubscription(
      library,
      feedUrl: 'https://feeds.example.test/background.xml',
      lastFetchedAt: now.subtract(defaultPodcastRefreshInterval),
    );
    final worker = PodcastSubscriptionRefreshWorker(
      clock: () => now,
      feedFetcher: _feed,
    );

    final report = await refreshDuePodcastSubscriptionsInBackground(
      library,
      worker: worker,
    );

    expect(report.refreshedCount, 1);
    expect(
      library.podcastSubscriptionById(subscription.id)!.episodes.single.title,
      'Fresh episode',
    );
  });

  testWidgets(
    'runs due refreshes on launch and resume but never in offline mode',
    (tester) async {
      final library = LibraryStore();
      await library.load();
      var calls = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryStore>.value(
          value: library,
          child: MaterialApp(
            home: PodcastRssRefreshWorker(
              runRefresh: (_) async {
                calls += 1;
                return const PodcastRefreshReport.empty();
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(calls, 1);

      await _sendLifecycleState(tester, AppLifecycleState.paused);
      await _sendLifecycleState(tester, AppLifecycleState.resumed);
      await tester.pump();

      expect(calls, 2);

      await tester.pumpWidget(const SizedBox());
      await library.setOfflineModeEnabled(true);
      calls = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryStore>.value(
          value: library,
          child: MaterialApp(
            home: PodcastRssRefreshWorker(
              runRefresh: (_) async {
                calls += 1;
                return const PodcastRefreshReport.empty();
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(calls, 0);
    },
  );
}

Future<PodcastSubscription> _saveSubscription(
  LibraryStore library, {
  required String feedUrl,
  DateTime? lastFetchedAt,
}) {
  return library.savePodcastSubscription(
    PodcastSubscription(
      id: 'ignored',
      feedUrl: feedUrl,
      title: 'Example podcast',
      lastFetchedAt: lastFetchedAt,
      episodes: <Track>[
        Track(
          id: 'old-$feedUrl',
          title: 'Old episode',
          artist: 'Host',
          album: 'Example podcast',
          streamUrl: 'https://media.example.test/old.mp3',
          sourceId: 'podcast-rss',
        ),
      ],
    ),
  );
}

PodcastRssFeed _feed(Uri feedUri) {
  return PodcastRssFeed(
    feedUri: feedUri,
    title: 'Example podcast',
    description: 'Updated RSS feed',
    author: 'Host',
    episodes: <PodcastEpisode>[
      PodcastEpisode(
        id: 'fresh-episode',
        title: 'Fresh episode',
        description: 'A newly refreshed episode.',
        author: 'Host',
        streamUri: Uri.parse('https://media.example.test/fresh.mp3'),
        duration: const Duration(minutes: 20),
      ),
    ],
  );
}

Future<void> _sendLifecycleState(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}
