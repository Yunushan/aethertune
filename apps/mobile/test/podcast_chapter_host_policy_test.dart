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
}
