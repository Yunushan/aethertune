import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/podcast_chapter_host_policy.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists approved HTTPS chapter hosts', () async {
    final policy = PodcastChapterHostPolicy();
    await policy.load();

    await policy.approveHost('Chapters.Example.Test');

    expect(policy.approvedHosts, <String>['chapters.example.test']);
    expect(
      policy.allows(Uri.parse('https://chapters.example.test/episode.json')),
      isTrue,
    );
    expect(
      policy.allows(Uri.parse('http://chapters.example.test/episode.json')),
      isFalse,
    );
    final restored = PodcastChapterHostPolicy();
    await restored.load();
    expect(restored.approvedHosts, <String>['chapters.example.test']);

    await restored.revokeHost('chapters.example.test');
    expect(restored.approvedHosts, isEmpty);
  });

  test('rejects URLs, ports, and invalid chapter hosts', () async {
    final policy = PodcastChapterHostPolicy();
    await policy.load();

    for (final value in <String>[
      '',
      'https://chapters.example.test',
      'chapters.example.test:8443',
      'user@chapters.example.test',
      'chapters.example.test/path',
    ]) {
      await expectLater(
        policy.approveHost(value),
        throwsA(isA<FormatException>()),
      );
    }
    expect(policy.approvedHosts, isEmpty);
  });

  test('records bounded approval history for each podcast subscription',
      () async {
    var now = DateTime.utc(2026, 7, 18, 12);
    final policy = PodcastChapterHostPolicy(clock: () => now);
    await policy.load();

    await policy.approveHostForSubscription(
      'feed-a',
      'chapters.example.test',
    );
    now = now.add(const Duration(minutes: 1));
    await policy.approveHostForSubscription('feed-b', 'other.example.test');
    await policy.approveHostForSubscription(
      'feed-a',
      'chapters.example.test',
    );

    expect(
      policy.approvalHistoryForSubscription('feed-a').single,
      isA<PodcastChapterHostApproval>()
          .having(
            (entry) => entry.host,
            'host',
            'chapters.example.test',
          )
          .having(
            (entry) => entry.approvedAt,
            'approvedAt',
            now,
          ),
    );
    expect(
      policy.approvalHistoryForSubscription('feed-b').single.host,
      'other.example.test',
    );

    final restored = PodcastChapterHostPolicy(clock: () => now);
    await restored.load();
    expect(
      restored.approvalHistoryForSubscription('feed-a').single.host,
      'chapters.example.test',
    );

    await restored.revokeHost('chapters.example.test');
    expect(restored.approvedHosts, <String>['other.example.test']);
    expect(
      restored.approvalHistoryForSubscription('feed-a').single.host,
      'chapters.example.test',
    );
  });

  test('migrates host-only preferences and bounds subscription history',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.podcast_chapter_hosts.v1': <String>[
        'legacy.example.test',
      ],
    });
    final policy = PodcastChapterHostPolicy();
    await policy.load();

    expect(policy.approvedHosts, <String>['legacy.example.test']);
    for (var index = 0; index < 10; index += 1) {
      await policy.approveHostForSubscription(
        'feed-a',
        'chapters-$index.example.test',
      );
    }

    expect(policy.approvalHistoryForSubscription('feed-a'), hasLength(8));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('aethertune.podcast_chapter_hosts.v2'), isNotNull);
  });
}
