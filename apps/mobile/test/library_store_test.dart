import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/internet_archive_provider.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/radio_browser_provider.dart';
import 'package:aethertune/src/domain/artwork_crop.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/offline_cache_entry.dart';
import 'package:aethertune/src/domain/podcast_subscription.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_chapter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists onboarding completion without adding it to library data',
      () async {
    final store = LibraryStore();
    await store.load();

    expect(store.onboardingCompleted, isFalse);

    await store.setOnboardingCompleted(true);

    final restored = LibraryStore();
    await restored.load();

    expect(restored.onboardingCompleted, isTrue);
    expect(restored.tracks, isEmpty);
    expect(restored.playlists, isEmpty);
  });

  test('merges sync snapshots without dropping independent tracks or playlists',
      () async {
    final now = DateTime.utc(2026, 2, 1);
    final local = LibraryStore(clock: () => now);
    final remote = LibraryStore(clock: () => now);
    await local.load();
    await remote.load();
    await local.addTracks(<Track>[_track('local'), _track('shared')]);
    await remote.addTracks(<Track>[_track('remote'), _track('shared')]);
    await remote.toggleFavorite('shared');
    final localPlaylist = await local.createPlaylist(
      'Merged',
      trackIds: <String>['local'],
    );
    await remote.createPlaylist('Merged', trackIds: <String>['remote']);
    final localSubscription = await local.savePodcastSubscription(
      PodcastSubscription(
        id: 'podcast',
        feedUrl: 'https://feeds.example.test/aether.xml',
        title: 'Aether Radio',
        episodes: <Track>[_track('local-episode', sourceId: 'podcast-rss')],
      ),
    );
    await remote.savePodcastSubscription(
      PodcastSubscription(
        id: 'podcast',
        feedUrl: 'https://feeds.example.test/aether.xml',
        title: 'Aether Radio Remote',
        episodes: <Track>[_track('remote-episode', sourceId: 'podcast-rss')],
      ),
    );
    await local.setArtistFollowed('Mira', true);
    await remote.setArtistFollowed('Orion', true);

    await local.mergeSyncSnapshotJson(remote.exportSyncSnapshotJson());

    expect(local.tracks.map((track) => track.id), containsAll(<String>[
      'local',
      'remote',
    ]));
    expect(local.playlistById(localPlaylist.id)!.trackIds, <String>[
      'local',
      'remote',
    ]);
    expect(
      local.tracks.singleWhere((track) => track.id == 'shared').isFavorite,
      isTrue,
    );
    expect(
      local
          .podcastSubscriptionById(localSubscription.id)!
          .episodes
          .map((track) => track.id),
      <String>['local-episode', 'remote-episode'],
    );
    expect(local.followedArtists, <String>['Mira', 'Orion']);
  });

  test('persists local artist follows and builds the newest follow feed',
      () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'mira-old',
        artist: 'Mira',
        addedAt: DateTime.utc(2026, 1, 1),
      ),
      _track(
        'mira-new',
        artist: ' mira ',
        addedAt: DateTime.utc(2026, 1, 4),
      ),
      _track(
        'orion-new',
        artist: 'Orion',
        addedAt: DateTime.utc(2026, 1, 5),
      ),
      _track(
        'other-new',
        artist: 'Ari',
        addedAt: DateTime.utc(2026, 1, 6),
      ),
    ]);

    expect(store.canFollowArtist('Unknown Artist'), isFalse);
    expect(await store.setArtistFollowed(' Mira ', true), isTrue);
    expect(await store.setArtistFollowed('mira', true), isFalse);
    expect(await store.setArtistFollowed('Orion', true), isTrue);
    expect(store.followedArtists, <String>['Mira', 'Orion']);
    expect(store.isArtistFollowed('  MIRA'), isTrue);

    final section = store.homeFeedSections(limit: 3).firstWhere(
          (section) => section.type == LibraryHomeSectionType.followedArtists,
        );
    expect(
      section.tracks.map((track) => track.id),
      <String>['orion-new', 'mira-new', 'mira-old'],
    );

    final backup = store.exportBackupJson();
    final restored = LibraryStore();
    await restored.load();
    await restored.restoreBackupJson(backup);

    expect(restored.followedArtists, <String>['Mira', 'Orion']);
    expect(await restored.setArtistFollowed('Mira', false), isTrue);
    expect(restored.isArtistFollowed('mira'), isFalse);
  });

  test('filters custom smart playlists by exact source artist album and genre', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'local-rock',
        artist: 'Mira',
        album: 'Vault',
        genre: 'Rock',
        sourceId: 'local',
      ),
      _track(
        'archive-rock',
        artist: 'Mira',
        album: 'Vault',
        genre: 'Rock',
        sourceId: 'archive',
      ),
      _track(
        'archive-jazz',
        artist: 'Mira',
        album: 'Vault',
        genre: 'Jazz',
        sourceId: 'archive',
      ),
    ]);
    final rule = await store.createCustomSmartPlaylist(
      name: 'Archive rock',
      sourceId: 'ARCHIVE',
      artist: 'mira',
      album: 'vault',
      genre: 'rock',
    );

    expect(
      store.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['archive-rock'],
    );
  });

  test('matches any custom smart playlist criterion and persists the mode', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'mira-ambient',
        title: 'Alpha',
        artist: 'Mira',
        genre: 'Ambient',
      ),
      _track(
        'other-jazz',
        title: 'Bravo',
        artist: 'Other',
        genre: 'Jazz',
      ),
      _track(
        'mira-jazz',
        title: 'Delta',
        artist: 'Mira',
        genre: 'Jazz',
      ),
      _track(
        'other-rock',
        title: 'Charlie',
        artist: 'Other',
        genre: 'Rock',
      ),
    ]);
    final rule = await store.createCustomSmartPlaylist(
      name: 'Mira or jazz',
      artist: 'Mira',
      genre: 'Jazz',
      matchMode: CustomSmartPlaylistMatchMode.any,
      sortMode: CustomSmartPlaylistSortMode.title,
    );

    expect(
      store.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['mira-ambient', 'other-jazz', 'mira-jazz'],
    );

    final persisted = LibraryStore();
    await persisted.load();
    expect(
      persisted.customSmartPlaylists.single.matchMode,
      CustomSmartPlaylistMatchMode.any,
    );

    await persisted.updateCustomSmartPlaylist(
      rule.id,
      name: rule.name,
      query: rule.query,
      artist: rule.artist,
      genre: rule.genre,
      favoritesOnly: rule.favoritesOnly,
      minimumPlayCount: rule.minimumPlayCount,
      matchMode: CustomSmartPlaylistMatchMode.all,
      sortMode: rule.sortMode,
      limit: rule.limit,
    );
    expect(
      persisted.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['mira-jazz'],
    );
  });

  test('evaluates and persists nested custom smart playlist rule groups',
      () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'mira-jazz',
        title: 'Alpha',
        artist: 'Mira',
        genre: 'Jazz',
        duration: const Duration(seconds: 60),
      ),
      _track(
        'mira-rock-long',
        title: 'Beta',
        artist: 'Mira',
        genre: 'Rock',
        duration: const Duration(seconds: 180),
      ),
      _track(
        'mira-rock-short',
        title: 'Charlie',
        artist: 'Mira',
        genre: 'Rock',
        duration: const Duration(seconds: 30),
      ),
      _track(
        'other-rock-long',
        title: 'Delta',
        artist: 'Other',
        genre: 'Rock',
        duration: const Duration(seconds: 180),
      ),
    ]);
    final rule = await store.createCustomSmartPlaylist(
      name: 'Mira jazz or long rock',
      artist: 'Mira',
      sortMode: CustomSmartPlaylistSortMode.title,
      ruleGroups: <CustomSmartPlaylistRuleGroup>[
        CustomSmartPlaylistRuleGroup(
          matchMode: CustomSmartPlaylistMatchMode.any,
          rules: const <CustomSmartPlaylistRule>[
            CustomSmartPlaylistRule(
              field: CustomSmartPlaylistRuleField.genre,
              value: 'Jazz',
            ),
          ],
          groups: <CustomSmartPlaylistRuleGroup>[
            CustomSmartPlaylistRuleGroup(
              rules: const <CustomSmartPlaylistRule>[
                CustomSmartPlaylistRule(
                  field: CustomSmartPlaylistRuleField.genre,
                  value: 'Rock',
                ),
                CustomSmartPlaylistRule(
                  field:
                      CustomSmartPlaylistRuleField.minimumDurationSeconds,
                  value: '120',
                ),
              ],
            ),
          ],
        ),
      ],
    );

    expect(
      store.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['mira-jazz', 'mira-rock-long'],
    );

    final persisted = LibraryStore();
    await persisted.load();
    final restored = persisted.customSmartPlaylists.single;
    expect(restored.ruleGroups, hasLength(1));
    expect(restored.ruleGroups.single.groups, hasLength(1));
    expect(
      persisted.tracksForCustomSmartPlaylist(restored.id)
          .map((track) => track.id),
      <String>['mira-jazz', 'mira-rock-long'],
    );
  });

  test('ignores malformed nested custom smart playlist rules from storage', () {
    final rule = CustomSmartPlaylist.fromJson(<String, Object?>{
      'id': 'nested-rules',
      'name': 'Nested rules',
      'ruleGroups': <Object?>[
        <String, Object?>{
          'matchMode': 'any',
          'rules': <Object?>[
            <String, Object?>{'field': 'genre', 'value': 'Rock'},
            <String, Object?>{'field': 'minimumPlayCount', 'value': 'nope'},
          ],
          'groups': <Object?>['invalid'],
        },
        'invalid',
      ],
    });

    expect(rule.ruleGroups, hasLength(1));
    expect(rule.ruleGroups.single.rules, hasLength(1));
    expect(
      rule.ruleGroups.single.rules.single.field,
      CustomSmartPlaylistRuleField.genre,
    );
  });

  test('persists smart playlist artwork and keeps local files private',
      () async {
    var now = DateTime.utc(2026, 7, 14, 5);
    DateTime clock() => now;
    final store = LibraryStore(clock: clock);
    await store.load();
    final rule = await store.createCustomSmartPlaylist(name: 'Artwork rules');
    final webArtwork = Uri.parse('https://media.example.test/rules.jpg');

    now = now.add(const Duration(minutes: 1));
    final updated = await store.updateCustomSmartPlaylistArtwork(
      rule.id,
      webArtwork,
    );
    expect(updated!.artworkUri, webArtwork);
    expect(updated.updatedAt, now);

    final persisted = LibraryStore(clock: clock);
    await persisted.load();
    expect(persisted.customSmartPlaylists.single.artworkUri, webArtwork);

    final privateArtwork = Uri.file('/private/smart-playlist-artwork.png');
    await persisted.updateCustomSmartPlaylistArtwork(rule.id, privateArtwork);
    expect(
      persisted.customSmartPlaylists.single.artworkUri,
      privateArtwork,
    );

    final backup = jsonDecode(persisted.exportBackupJson())
        as Map<String, dynamic>;
    final backupRule = (backup['customSmartPlaylists'] as List<dynamic>).single
        as Map<String, dynamic>;
    expect(backupRule['artworkUri'], isNull);

    final snapshot = jsonDecode(persisted.exportSyncSnapshotJson())
        as Map<String, dynamic>;
    final snapshotRule =
        (snapshot['customSmartPlaylists'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(snapshotRule['artworkUri'], isNull);

    final cleared = await persisted.updateCustomSmartPlaylistArtwork(
      rule.id,
      null,
    );
    expect(cleared!.artworkUri, isNull);
    expect(
      await persisted.updateCustomSmartPlaylistArtwork('missing', webArtwork),
      isNull,
    );
  });

  test('shares and imports nested smart playlist links without local artwork',
      () async {
    final store = LibraryStore();
    await store.load();
    final rule = await store.createCustomSmartPlaylist(
      name: 'Shared Mira rules',
      artist: 'Mira',
      sortMode: CustomSmartPlaylistSortMode.title,
      limit: 20,
      ruleGroups: <CustomSmartPlaylistRuleGroup>[
        CustomSmartPlaylistRuleGroup(
          matchMode: CustomSmartPlaylistMatchMode.any,
          rules: const <CustomSmartPlaylistRule>[
            CustomSmartPlaylistRule(
              field: CustomSmartPlaylistRuleField.genre,
              value: 'Jazz',
            ),
          ],
          groups: <CustomSmartPlaylistRuleGroup>[
            CustomSmartPlaylistRuleGroup(
              rules: const <CustomSmartPlaylistRule>[
                CustomSmartPlaylistRule(
                  field: CustomSmartPlaylistRuleField.minimumPlayCount,
                  value: '2',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    await store.updateCustomSmartPlaylistArtwork(
      rule.id,
      Uri.file('/private/shared-rules.png'),
    );

    final link = store.customSmartPlaylistImportLink(rule.id);
    expect(link, startsWith('aethertune://smart-playlist?data='));

    final uri = Uri.parse(link!);
    final document = jsonDecode(
      utf8.decode(base64Url.decode(uri.queryParameters['data']!)),
    ) as Map<String, dynamic>;
    final exportedRule = document['rule'] as Map<String, dynamic>;
    expect(exportedRule['artworkUri'], isNull);
    expect(exportedRule['ruleGroups'], isA<List<dynamic>>());

    final imported = await store.importCustomSmartPlaylistLink(link);
    expect(imported.id, isNot(rule.id));
    expect(imported.name, rule.name);
    expect(imported.artist, rule.artist);
    expect(imported.sortMode, rule.sortMode);
    expect(imported.limit, rule.limit);
    expect(imported.artworkUri, isNull);
    expect(imported.ruleGroups, hasLength(1));
    expect(imported.ruleGroups.single.groups, hasLength(1));
    expect(
      imported.ruleGroups.single.groups.single.rules.single.field,
      CustomSmartPlaylistRuleField.minimumPlayCount,
    );

    await expectLater(
      store.importCustomSmartPlaylistLink('https://example.test/not-a-link'),
      throwsFormatException,
    );
  });

  test('filters custom smart playlists by duration bounds', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track('short', duration: const Duration(seconds: 30)),
      _track('target', duration: const Duration(seconds: 120)),
      _track('long', duration: const Duration(seconds: 600)),
    ]);
    final rule = await store.createCustomSmartPlaylist(
      name: 'Two minute tracks',
      minimumDurationSeconds: 60,
      maximumDurationSeconds: 300,
    );

    expect(
      store.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['target'],
    );
  });

  test('filters smart playlists by time since last play', () async {
    var now = DateTime.utc(2026, 7, 10, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track('recent', title: 'Recent'),
      _track('stale', title: 'Stale'),
      _track('never', title: 'Never'),
    ]);

    now = DateTime.utc(2026, 7, 1, 12);
    await store.recordPlayback('stale');
    now = DateTime.utc(2026, 7, 9, 12);
    await store.recordPlayback('recent');
    now = DateTime.utc(2026, 7, 10, 12);

    final rule = await store.createCustomSmartPlaylist(
      name: 'Rediscover',
      minimumDaysSinceLastPlayed: 7,
      sortMode: CustomSmartPlaylistSortMode.title,
    );

    expect(
      store.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['never', 'stale'],
    );
  });

  test('creates manual playlists with existing tracks only', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 1),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);

    final playlist = await store.createPlaylist(
      '  Road Mix  ',
      trackIds: <String>['1', 'missing', '2', '1'],
    );

    expect(playlist.name, 'Road Mix');
    expect(store.playlists, hasLength(1));
    expect(store.playlists.single.trackIds, <String>['1', '2']);
    expect(
      store
          .tracksForPlaylist(playlist.id)
          .map((track) => track.id)
          .toList(growable: false),
      <String>['1', '2'],
    );
  });

  test('adds and removes tracks without duplicating playlist entries', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 2),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);
    final playlist = await store.createPlaylist('Favorites');

    await store.addTrackToPlaylist(playlist.id, '1');
    await store.addTrackToPlaylist(playlist.id, '1');
    await store.addTrackToPlaylist(playlist.id, '2');
    await store.removeTrackFromPlaylist(playlist.id, '1');

    expect(store.playlistById(playlist.id)!.trackIds, <String>['2']);
  });

  test('reorders playlist tracks by index', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 2, 12),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2'), _track('3')]);
    final playlist = await store.createPlaylist(
      'Ordered',
      trackIds: <String>['1', '2', '3'],
    );

    await store.moveTrackInPlaylist(playlist.id, 2, 0);

    expect(store.playlistById(playlist.id)!.trackIds, <String>['3', '1', '2']);

    await store.moveTrackInPlaylist(playlist.id, 0, 2);
    await store.moveTrackInPlaylist(playlist.id, -1, 2);
    await store.moveTrackInPlaylist(playlist.id, 0, 99);

    expect(store.playlistById(playlist.id)!.trackIds, <String>['1', '2', '3']);
  });

  test('saves queue track order as a playlist', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 2, 18),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2'), _track('3')]);

    final playlist = await store.createPlaylist(
      'Queue Save',
      trackIds: <String>['3', 'missing', '1', '2'],
    );

    expect(playlist.name, 'Queue Save');
    expect(playlist.trackIds, <String>['3', '1', '2']);
    expect(
      store.tracksForPlaylist(playlist.id).map((track) => track.id),
      <String>['3', '1', '2'],
    );
  });

  test('filters playlist tracks without changing playlist order', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 2, 20),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Road One',
        artist: 'Ari',
        album: 'Home',
      ),
      _track(
        '2',
        title: 'Night Ride',
        artist: 'Road Crew',
        album: 'City',
      ),
      _track(
        '3',
        title: 'Archive Theme',
        artist: 'Orion',
        album: 'Road Album',
      ),
      _track(
        '4',
        title: 'Other Track',
        artist: 'Mia',
        album: 'Elsewhere',
      ),
    ]);
    final playlist = await store.createPlaylist(
      'Searchable',
      trackIds: <String>['3', '1', '2', '4'],
    );

    expect(
      store.tracksForPlaylist(playlist.id, query: '  road  ').map(
            (track) => track.id,
          ),
      <String>['3', '1', '2'],
    );
    expect(
      store.tracksForPlaylist(playlist.id, query: 'night').map(
            (track) => track.id,
          ),
      <String>['2'],
    );
    expect(
      store.tracksForPlaylist(playlist.id, query: 'orion').map(
            (track) => track.id,
          ),
      <String>['3'],
    );
    expect(store.tracksForPlaylist(playlist.id, query: 'missing'), isEmpty);
  });

  test('removing a library track removes it from playlists', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 3),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);
    final playlist = await store.createPlaylist(
      'Cleanup',
      trackIds: <String>['1', '2'],
    );

    await store.removeTrack('1');

    expect(store.playlistById(playlist.id)!.trackIds, <String>['2']);
  });

  test(
    'detects duplicate tracks by path hash provider stream and metadata',
    () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'path-a',
        title: 'Path A',
        localPath: '/music/shared.mp3',
      ),
      _track(
        'path-b',
        title: 'Path B',
        localPath: '/music/shared.mp3',
      ),
      _track(
        'hash-a',
        title: 'Hash A',
        localPath: '/music/hash-a.mp3',
        contentHash: 'fnv64-1111222233334444',
      ),
      _track(
        'hash-b',
        title: 'Hash B',
        localPath: '/music/hash-b.mp3',
        contentHash: 'fnv64-1111222233334444',
      ),
      _track(
        'provider-a',
        title: 'Provider A',
        sourceId: 'archive',
        externalId: 'item-1',
        localPath: null,
      ),
      _track(
        'provider-b',
        title: 'Provider B',
        sourceId: 'archive',
        externalId: 'item-1',
        localPath: null,
      ),
      _track(
        'stream-a',
        title: 'Stream A',
        streamUrl: 'https://media.example.test/song.mp3',
        localPath: null,
      ),
      _track(
        'stream-b',
        title: 'Stream B',
        streamUrl: 'https://media.example.test/song.mp3',
        localPath: null,
      ),
      _track(
        'meta-a',
        title: 'Same Song',
        artist: 'Mira',
        album: 'Dawn',
        duration: const Duration(minutes: 3),
      ),
      _track(
        'meta-b',
        title: ' same song ',
        artist: ' mira ',
        album: ' dawn ',
        duration: const Duration(minutes: 3),
      ),
    ]);

    final groups = store.duplicateTrackGroups();

    expect(
      groups.map((group) => group.type),
      containsAll(<DuplicateMatchType>[
        DuplicateMatchType.localPath,
        DuplicateMatchType.contentHash,
        DuplicateMatchType.sourceExternalId,
        DuplicateMatchType.streamUrl,
        DuplicateMatchType.metadata,
      ]),
    );
    expect(
      groups
          .firstWhere((group) => group.type == DuplicateMatchType.localPath)
          .tracks
          .map((track) => track.id),
      containsAll(<String>['path-a', 'path-b']),
    );
    expect(
      groups
          .firstWhere((group) => group.type == DuplicateMatchType.contentHash)
          .tracks
          .map((track) => track.id),
      containsAll(<String>['hash-a', 'hash-b']),
    );
  });

  test('resolves duplicates while preserving attached library state', () async {
    var now = DateTime.utc(2026, 1, 4, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'keep',
        title: 'Aether Bloom',
        artist: 'Mira',
        album: 'Dawn',
        duration: const Duration(minutes: 3),
        addedAt: DateTime.utc(2026, 1, 1),
      ),
      _track(
        'duplicate',
        title: 'Aether Bloom',
        artist: 'Mira',
        album: 'Dawn',
        duration: const Duration(minutes: 3),
        addedAt: DateTime.utc(2026, 1, 2),
      ),
      _track(
        'other',
        title: 'Other',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
    ]);
    final playlist = await store.createPlaylist(
      'Merge',
      trackIds: <String>['duplicate', 'other', 'keep'],
    );
    await store.setLyrics('keep', 'old lyrics');
    now = DateTime.utc(2026, 1, 4, 12, 1);
    await store.setLyrics(
      'duplicate',
      'new lyrics',
      sourceId: 'lrclib',
      sourceName: 'LRCLIB',
      sourceExternalId: '42',
      sourceUri: Uri.parse('https://lrclib.net/api/get/42'),
    );
    await store.recordPlayback('keep');
    now = DateTime.utc(2026, 1, 4, 12, 2);
    await store.recordPlayback('duplicate');
    await store.recordPlaybackProgress(
      'duplicate',
      const Duration(minutes: 10),
      const Duration(minutes: 30),
    );
    await store.toggleFavorite('duplicate');

    final removed = await store.resolveDuplicateTracks(
      keepTrackId: 'keep',
      duplicateTrackIds: <String>['duplicate'],
    );

    expect(removed, 1);
    expect(store.tracks.map((track) => track.id), isNot(contains('duplicate')));
    expect(
      store.playlistById(playlist.id)!.trackIds,
      <String>['keep', 'other'],
    );
    expect(
      store.playbackHistory.map((entry) => entry.trackId),
      <String>['keep', 'keep'],
    );
    expect(store.playCountForTrack('keep'), 2);
    expect(
      store.tracks.firstWhere((track) => track.id == 'keep').isFavorite,
      isTrue,
    );
    expect(store.lyricsForTrack('keep')!.plainText, 'new lyrics');
    expect(store.lyricsForTrack('keep')!.sourceName, 'LRCLIB');
    expect(store.lyricsForTrack('keep')!.sourceExternalId, '42');
    expect(store.lyricsForTrack('duplicate'), isNull);
    expect(
      store.playbackProgressForTrack('keep')!.position,
      const Duration(minutes: 10),
    );
    expect(store.playbackProgressForTrack('duplicate'), isNull);
    expect(store.duplicateTrackGroups(), isEmpty);

    final secondStore = LibraryStore(clock: () => now);
    await secondStore.load();

    expect(
      secondStore.tracks.map((track) => track.id),
      isNot(contains('duplicate')),
    );
    expect(secondStore.playlistById(playlist.id)!.trackIds, <String>[
      'keep',
      'other',
    ]);
    expect(secondStore.lyricsForTrack('keep')!.plainText, 'new lyrics');
    expect(secondStore.lyricsForTrack('keep')!.sourceName, 'LRCLIB');
    expect(secondStore.playCountForTrack('keep'), 2);
  });

  test('undoes the last duplicate merge with all rewritten state restored',
      () async {
    var now = DateTime.utc(2026, 7, 14, 6);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'keep',
        title: 'Undo me',
        artist: 'Mira',
        duration: const Duration(minutes: 3),
      ),
      _track(
        'duplicate',
        title: 'Undo me',
        artist: 'Mira',
        duration: const Duration(minutes: 3),
      ),
    ]);
    final playlist = await store.createPlaylist(
      'Undo merge',
      trackIds: <String>['duplicate', 'keep'],
    );
    await store.setLyrics('keep', 'keeper lyrics');
    now = now.add(const Duration(minutes: 1));
    await store.setLyrics('duplicate', 'duplicate lyrics');
    await store.recordPlayback('duplicate');
    await store.recordPlaybackProgress(
      'duplicate',
      const Duration(minutes: 2),
      const Duration(minutes: 3),
    );
    await store.setTrackPlaybackSpeed('duplicate', 1.5);
    await store.toggleFavorite('duplicate');

    expect(
      await store.resolveDuplicateTracks(
        keepTrackId: 'keep',
        duplicateTrackIds: <String>['duplicate'],
      ),
      1,
    );
    expect(store.canUndoDuplicateResolution, isTrue);
    expect(store.playbackSpeedForTrack('keep'), 1.5);
    expect(store.playbackSpeedForTrack('duplicate'), isNull);

    expect(await store.undoLastDuplicateResolution(), isTrue);
    expect(store.canUndoDuplicateResolution, isFalse);
    expect(store.tracks.map((track) => track.id), containsAll(<String>[
      'keep',
      'duplicate',
    ]));
    expect(store.playlistById(playlist.id)!.trackIds, <String>[
      'duplicate',
      'keep',
    ]);
    expect(
      store.playbackHistory.map((entry) => entry.trackId),
      <String>['duplicate'],
    );
    expect(store.lyricsForTrack('keep')!.plainText, 'keeper lyrics');
    expect(store.lyricsForTrack('duplicate')!.plainText, 'duplicate lyrics');
    expect(store.playbackProgressForTrack('keep'), isNull);
    expect(
      store.playbackProgressForTrack('duplicate')!.position,
      const Duration(minutes: 2),
    );
    expect(store.playbackSpeedForTrack('keep'), isNull);
    expect(store.playbackSpeedForTrack('duplicate'), 1.5);
    expect(
      store.tracks.firstWhere((track) => track.id == 'keep').isFavorite,
      isFalse,
    );
    expect(
      store.tracks.firstWhere((track) => track.id == 'duplicate').isFavorite,
      isTrue,
    );
    expect(store.duplicateTrackGroups(), isNotEmpty);
    expect(await store.undoLastDuplicateResolution(), isFalse);

    final restored = LibraryStore(clock: () => now);
    await restored.load();
    expect(restored.playlistById(playlist.id)!.trackIds, <String>[
      'duplicate',
      'keep',
    ]);
    expect(restored.playbackSpeedForTrack('duplicate'), 1.5);
  });

  test('expires duplicate merge undo after a later library change', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track('keep', title: 'Same', duration: const Duration(minutes: 1)),
      _track(
        'duplicate',
        title: 'Same',
        duration: const Duration(minutes: 1),
      ),
    ]);

    await store.resolveDuplicateTracks(
      keepTrackId: 'keep',
      duplicateTrackIds: <String>['duplicate'],
    );
    expect(store.canUndoDuplicateResolution, isTrue);

    await store.addTracks(<Track>[_track('later')]);
    expect(store.canUndoDuplicateResolution, isFalse);
    expect(await store.undoLastDuplicateResolution(), isFalse);
    expect(store.tracks.map((track) => track.id), containsAll(<String>[
      'keep',
      'later',
    ]));
    expect(store.tracks.map((track) => track.id), isNot(contains('duplicate')));
  });

  test('merges disjoint duplicate groups as one undoable batch', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track('keep-a', title: 'A', duration: const Duration(minutes: 1)),
      _track('duplicate-a', title: 'A', duration: const Duration(minutes: 1)),
      _track('keep-b', title: 'B', duration: const Duration(minutes: 2)),
      _track('duplicate-b', title: 'B', duration: const Duration(minutes: 2)),
    ]);
    final playlist = await store.createPlaylist(
      'Batch merge',
      trackIds: <String>[
        'duplicate-a',
        'duplicate-b',
        'keep-a',
        'keep-b',
      ],
    );

    final removed = await store.resolveDuplicateTrackBatch(
      <DuplicateTrackResolution>[
        DuplicateTrackResolution(
          keepTrackId: 'keep-a',
          duplicateTrackIds: <String>['duplicate-a'],
        ),
        DuplicateTrackResolution(
          keepTrackId: 'keep-b',
          duplicateTrackIds: <String>['duplicate-b'],
        ),
      ],
    );

    expect(removed, 2);
    expect(store.canUndoDuplicateResolution, isTrue);
    expect(store.tracks.map((track) => track.id), containsAll(<String>[
      'keep-a',
      'keep-b',
    ]));
    expect(store.tracks.map((track) => track.id), isNot(contains('duplicate-a')));
    expect(store.tracks.map((track) => track.id), isNot(contains('duplicate-b')));
    expect(store.playlistById(playlist.id)!.trackIds, <String>[
      'keep-a',
      'keep-b',
    ]);

    expect(await store.undoLastDuplicateResolution(), isTrue);
    expect(store.playlistById(playlist.id)!.trackIds, <String>[
      'duplicate-a',
      'duplicate-b',
      'keep-a',
      'keep-b',
    ]);
    expect(store.tracks.map((track) => track.id), containsAll(<String>[
      'keep-a',
      'duplicate-a',
      'keep-b',
      'duplicate-b',
    ]));
  });

  test('skips overlapping duplicate resolutions in a batch', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track('a', title: 'A', duration: const Duration(minutes: 1)),
      _track('b', title: 'B', duration: const Duration(minutes: 1)),
      _track('c', title: 'C', duration: const Duration(minutes: 1)),
    ]);

    final removed = await store.resolveDuplicateTrackBatch(
      <DuplicateTrackResolution>[
        DuplicateTrackResolution(
          keepTrackId: 'a',
          duplicateTrackIds: <String>['b'],
        ),
        DuplicateTrackResolution(
          keepTrackId: 'b',
          duplicateTrackIds: <String>['c'],
        ),
      ],
    );

    expect(removed, 1);
    expect(store.tracks.map((track) => track.id), containsAll(<String>['a', 'c']));
    expect(store.tracks.map((track) => track.id), isNot(contains('b')));
  });

  test('persists playlists across store instances', () async {
    DateTime clock() => DateTime.utc(2026, 1, 4);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1')]);
    final playlist = await firstStore.createPlaylist(
      'Saved',
      trackIds: <String>['1'],
    );

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.playlists, hasLength(1));
    expect(secondStore.playlistById(playlist.id)!.name, 'Saved');
    expect(secondStore.tracksForPlaylist(playlist.id).single.id, '1');
  });

  test('organizes playlists in persisted folders', () async {
    var now = DateTime.utc(2026, 1, 4);
    final firstStore = LibraryStore(clock: () => now);
    await firstStore.load();
    final playlist = await firstStore.createPlaylist(
      'Late night',
      folder: 'Chill',
    );

    expect(firstStore.playlistFolders, <String>['Chill']);
    now = now.add(const Duration(minutes: 1));
    final updated = await firstStore.updatePlaylistFolder(
      playlist.id,
      'Evening',
    );

    expect(updated!.folder, 'Evening');
    expect(updated.updatedAt, now);
    expect(firstStore.playlistFolders, <String>['Evening']);

    final secondStore = LibraryStore(clock: () => now);
    await secondStore.load();

    expect(secondStore.playlistById(playlist.id)!.folder, 'Evening');
    expect(secondStore.playlistFolders, <String>['Evening']);

    final document = jsonDecode(firstStore.exportPlaylistJson(playlist.id))
        as Map<String, dynamic>;
    expect((document['playlist'] as Map<String, dynamic>)['folder'], 'Evening');

    final restoredStore = LibraryStore(clock: () => now);
    await restoredStore.load();
    await restoredStore.restoreBackupJson(firstStore.exportBackupJson());
    expect(restoredStore.playlistById(playlist.id)!.folder, 'Evening');
  });

  test('edits persists exports imports and clears playlist artwork', () async {
    var now = DateTime.utc(2026, 1, 4, 5);
    DateTime clock() => now;
    final artworkUri = Uri.parse('https://media.example.test/road.jpg');
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1'), _track('2')]);
    final playlist = await firstStore.createPlaylist(
      'Artwork Mix',
      trackIds: <String>['1', '2'],
    );

    now = DateTime.utc(2026, 1, 4, 5, 1);
    final updated = await firstStore.updatePlaylistArtwork(
      playlist.id,
      artworkUri,
    );

    expect(updated!.artworkUri, artworkUri);
    expect(updated.updatedAt, now);
    expect(firstStore.playlistById(playlist.id)!.artworkUri, artworkUri);

    final crop = ArtworkCrop.normalized(
      alignmentX: 0.4,
      alignmentY: -0.25,
      zoom: 1.8,
    );
    now = DateTime.utc(2026, 1, 4, 5, 1, 30);
    final cropped = await firstStore.updatePlaylistArtworkCrop(
      playlist.id,
      crop,
    );
    expect(cropped!.artworkCrop.alignmentX, 0.4);
    expect(cropped.artworkCrop.alignmentY, -0.25);
    expect(cropped.artworkCrop.zoom, 1.8);
    expect(cropped.updatedAt, now);

    final playlistDocument = firstStore.exportPlaylistJson(playlist.id);
    final decoded = jsonDecode(playlistDocument) as Map<String, dynamic>;

    expect(
      (decoded['playlist'] as Map<String, dynamic>)['artworkUri'],
      artworkUri.toString(),
    );
    expect(
      ((decoded['playlist'] as Map<String, dynamic>)['artworkCrop']
          as Map<String, dynamic>)['zoom'],
      1.8,
    );

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.playlistById(playlist.id)!.artworkUri, artworkUri);
    expect(secondStore.playlistById(playlist.id)!.artworkCrop.zoom, 1.8);

    await secondStore.deletePlaylist(playlist.id);
    final imported = await secondStore.importPlaylistJson(playlistDocument);

    expect(imported.artworkUri, artworkUri);
    expect(imported.artworkCrop.alignmentX, 0.4);

    now = DateTime.utc(2026, 1, 4, 5, 1, 45);
    final replacement = await secondStore.updatePlaylistArtwork(
      imported.id,
      Uri.parse('https://media.example.test/replacement.jpg'),
    );
    expect(replacement!.artworkCrop.isCentered, isTrue);

    now = DateTime.utc(2026, 1, 4, 5, 2);
    final cleared = await secondStore.updatePlaylistArtwork(imported.id, null);

    expect(cleared!.artworkUri, isNull);
    expect(cleared.artworkCrop.isCentered, isTrue);
    expect(cleared.updatedAt, now);
    expect(secondStore.playlistById(imported.id)!.artworkUri, isNull);
    expect(
      await secondStore.updatePlaylistArtwork('missing', artworkUri),
      isNull,
    );
  });

  test('keeps local playlist artwork private to the current device', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[_track('1')]);
    final playlist = await store.createPlaylist('Private artwork');
    final localArtwork = Uri.file('/private/playlist-artwork.png');
    await store.updatePlaylistArtwork(playlist.id, localArtwork);

    expect(store.playlistById(playlist.id)!.artworkUri, localArtwork);

    final backup = jsonDecode(store.exportBackupJson()) as Map<String, dynamic>;
    final backupPlaylist = (backup['playlists'] as List<dynamic>).single
        as Map<String, dynamic>;
    expect(backupPlaylist['artworkUri'], isNull);

    final document = jsonDecode(store.exportPlaylistJson(playlist.id))
        as Map<String, dynamic>;
    expect(
      (document['playlist'] as Map<String, dynamic>)['artworkUri'],
      isNull,
    );

    final snapshot = jsonDecode(store.exportSyncSnapshotJson())
        as Map<String, dynamic>;
    final snapshotPlaylist = (snapshot['playlists'] as List<dynamic>).single
        as Map<String, dynamic>;
    expect(snapshotPlaylist['artworkUri'], isNull);
  });

  test('shares and imports portable playlist links without local paths',
      () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track('one', title: 'One', artist: 'Mira', album: 'Dawn'),
      _track('two', title: 'Two', artist: 'Mira', album: 'Dawn'),
    ]);
    final playlist = await store.createPlaylist(
      'Link mix',
      trackIds: const <String>['one', 'two'],
    );

    final link = store.playlistImportLink(playlist.id);
    expect(link, startsWith('aethertune://playlist?data='));

    final uri = Uri.parse(link!);
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(uri.queryParameters['data']!)),
    ) as Map<String, dynamic>;
    final sharedTrack = (payload['tracks'] as List<dynamic>).first
        as Map<String, dynamic>;
    expect(sharedTrack['localPath'], isNull);
    expect(sharedTrack['streamUrl'], isNull);

    final imported = await store.importPlaylistLink(link);
    expect(imported.name, 'Link mix');
    expect(imported.trackIds, const <String>['one', 'two']);

    expect(store.playlistImportLink('missing'), isNull);
    await expectLater(
      store.importPlaylistLink('https://example.test/playlist'),
      throwsFormatException,
    );
  });

  test('keeps private user track artwork on-device and restores source artwork',
      () async {
    final store = LibraryStore();
    await store.load();
    final scannedArtwork = Uri.parse('data:image/png;base64,c2Nhbm5lZA==');
    final privateArtwork = Uri.file('/private/track-artwork.png');
    await store.addTracks(<Track>[
      _track('1', artworkUri: scannedArtwork),
    ]);

    final updated = await store.updateTrackArtwork('1', privateArtwork);
    expect(updated!.artworkUri, privateArtwork);
    expect(updated.artworkSourceUri, scannedArtwork);
    expect(updated.artworkIsUserManaged, isTrue);

    final backup = jsonDecode(store.exportBackupJson()) as Map<String, dynamic>;
    final backupTrack = (backup['tracks'] as List<dynamic>).single
        as Map<String, dynamic>;
    expect(backupTrack['artworkUri'], scannedArtwork.toString());
    expect(backupTrack['artworkSourceUri'], isNull);
    expect(backupTrack['artworkIsUserManaged'], isFalse);

    final playlist = await store.createPlaylist('Private track cover',
        trackIds: <String>['1']);
    final document = jsonDecode(store.exportPlaylistJson(playlist.id))
        as Map<String, dynamic>;
    final documentTrack = (document['tracks'] as List<dynamic>).single
        as Map<String, dynamic>;
    expect(documentTrack['artworkUri'], scannedArtwork.toString());

    final snapshot = jsonDecode(store.exportSyncSnapshotJson())
        as Map<String, dynamic>;
    final snapshotTrack = (snapshot['tracks'] as List<dynamic>).single
        as Map<String, dynamic>;
    expect(snapshotTrack['artworkUri'], scannedArtwork.toString());
    expect(snapshotTrack['artworkSourceUri'], isNull);
    expect(snapshotTrack['artworkIsUserManaged'], isFalse);

    final remote = LibraryStore();
    await remote.load();
    await store.mergeSyncSnapshotJson(remote.exportSyncSnapshotJson());
    expect(store.tracks.single.artworkUri, privateArtwork);
    expect(store.tracks.single.artworkSourceUri, scannedArtwork);
    expect(store.tracks.single.artworkIsUserManaged, isTrue);

    final restored = await store.updateTrackArtwork('1', null);
    expect(restored!.artworkUri, scannedArtwork);
    expect(restored.artworkSourceUri, isNull);
    expect(restored.artworkIsUserManaged, isFalse);
  });

  test('updates scanned embedded artwork without replacing a private cover',
      () async {
    final store = LibraryStore();
    await store.load();
    final originalArtwork = Uri.parse('data:image/png;base64,b3JpZ2luYWw=');
    final replacementArtwork = Uri.parse('data:image/jpeg;base64,cmVwbGFjZWQ=');
    final privateArtwork = Uri.file('/private/track-artwork.png');
    await store.addTracks(<Track>[
      _track('1', artworkUri: originalArtwork),
    ]);

    final scannedUpdate = await store.updateEmbeddedTrackArtwork(
      '1',
      replacementArtwork,
    );
    expect(scannedUpdate!.artworkUri, replacementArtwork);
    expect(scannedUpdate.artworkSourceUri, replacementArtwork);
    expect(scannedUpdate.artworkIsUserManaged, isFalse);

    await store.updateTrackArtwork('1', privateArtwork);
    final preservedPrivateArtwork = await store.updateEmbeddedTrackArtwork(
      '1',
      originalArtwork,
    );
    expect(preservedPrivateArtwork!.artworkUri, privateArtwork);
    expect(preservedPrivateArtwork.artworkSourceUri, originalArtwork);
    expect(preservedPrivateArtwork.artworkIsUserManaged, isTrue);

    await expectLater(
      store.updateEmbeddedTrackArtwork('1', Uri.parse('https://example.com/cover.png')),
      throwsArgumentError,
    );
  });

  test('exports and imports playlist JSON documents', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 4, 1),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track('1', title: 'First'),
      _track('2', title: 'Second'),
      _track('3', title: 'Third'),
    ]);
    final playlist = await store.createPlaylist(
      'Road JSON',
      trackIds: <String>['2', '1', '3'],
    );

    final document = store.exportPlaylistDocument(
      playlist.id,
      format: PlaylistDocumentFormat.json,
    );
    final decoded = jsonDecode(document) as Map<String, dynamic>;

    expect(decoded['type'], 'aethertune.playlist');
    expect((decoded['tracks'] as List<dynamic>), hasLength(3));

    await store.deletePlaylist(playlist.id);
    final imported = await store.importPlaylistDocument(
      document,
      format: PlaylistDocumentFormat.json,
    );

    expect(imported.name, 'Road JSON');
    expect(imported.trackIds, <String>['2', '1', '3']);
  });

  test('exports and imports M3U playlists by track path', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 4, 2),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track('1', title: 'Path One', artist: 'Ari'),
      _track('2', title: 'Path Two', artist: 'Mia'),
    ]);
    final playlist = await store.createPlaylist(
      'Road M3U',
      trackIds: <String>['2', '1'],
    );

    final document = store.exportPlaylistDocument(
      playlist.id,
      format: PlaylistDocumentFormat.m3u,
    );

    expect(document, contains('#EXTM3U'));
    expect(document, contains('#PLAYLIST:Road M3U'));
    expect(document, contains('/music/2.mp3'));

    await store.deletePlaylist(playlist.id);
    final imported = await store.importPlaylistDocument(
      document,
      format: PlaylistDocumentFormat.m3u,
    );

    expect(imported.name, 'Road M3U');
    expect(imported.trackIds, <String>['2', '1']);
  });

  test('exports and imports CSV playlists with quoted fields', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 4, 3),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Road, Theme',
        artist: 'Ari "Sky"',
        album: 'Comma Album',
      ),
      _track('2', title: 'Plain Track'),
    ]);
    final playlist = await store.createPlaylist(
      'Road CSV',
      trackIds: <String>['1', '2'],
    );

    final document = store.exportPlaylistDocument(
      playlist.id,
      format: PlaylistDocumentFormat.csv,
    );

    expect(document, contains('"Road, Theme"'));
    expect(document, contains('"Ari ""Sky"""'));

    await store.deletePlaylist(playlist.id);
    final imported = await store.importPlaylistDocument(
      document,
      format: PlaylistDocumentFormat.csv,
    );

    expect(imported.name, 'Road CSV');
    expect(imported.trackIds, <String>['1', '2']);
  });

  test('builds privacy-safe local share text', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 4, 4),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Local Signal',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 3, seconds: 5),
        localPath: r'C:\Users\Yunus\Music\Dawn\local-signal.mp3',
      ),
      _track(
        '2',
        title: 'Web Current',
        artist: 'Ari',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 4, seconds: 10),
        localPath: '',
        streamUrl: 'https://example.com/web-current.mp3',
      ),
    ]);
    final playlist = await store.createPlaylist(
      'Road Share',
      trackIds: <String>['2', '1'],
    );

    final trackShare = store.shareTrackText('1')!;
    expect(trackShare, contains('AetherTune track'));
    expect(trackShare, contains('Title: Local Signal'));
    expect(trackShare, contains('Duration: 3:05'));
    expect(trackShare, contains('Availability: Local file'));
    expect(trackShare, isNot(contains(r'C:\Users')));
    expect(store.shareTrackText('missing'), isNull);

    final streamShare = store.shareTrackText('2')!;
    expect(streamShare, contains('Link: https://example.com/web-current.mp3'));

    final groupShare = store.shareBrowseGroupText(
      LibraryBrowseType.album,
      'Dawn',
    )!;
    expect(groupShare, contains('AetherTune album'));
    expect(groupShare, contains('Name: Dawn'));
    expect(groupShare, contains('Tracks: 2'));
    expect(groupShare, contains('Duration: 7:15'));
    expect(groupShare, contains('1. Mira - Local Signal (Dawn)'));

    final folderShare = store.shareBrowseGroupText(
      LibraryBrowseType.folder,
      r'C:\Users\Yunus\Music\Dawn',
    )!;
    expect(folderShare, contains('Name: Dawn'));
    expect(folderShare, isNot(contains(r'C:\Users')));

    final playlistShare = store.sharePlaylistText(playlist.id)!;
    expect(playlistShare, contains('AetherTune playlist'));
    expect(playlistShare, contains('Name: Road Share'));
    expect(playlistShare, contains('Tracks: 2'));
    expect(playlistShare, contains('Duration: 7:15'));
    expect(playlistShare, contains('1. Ari - Web Current (Dawn)'));
    expect(playlistShare, contains('2. Mira - Local Signal (Dawn)'));
    expect(store.sharePlaylistText('missing'), isNull);
  });

  test('rejects playlist imports that do not match library tracks', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 4, 4),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);

    expect(
      store.importPlaylistDocument(
        '#EXTM3U\n#PLAYLIST:Missing\n/missing/file.mp3\n',
        format: PlaylistDocumentFormat.m3u,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(store.playlists, isEmpty);
  });

  test('saves and deletes plain lyrics for library tracks', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 5),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);

    await store.setLyrics('1', '  first line\nsecond line  ');

    expect(store.lyricsForTrack('1')!.plainText, 'first line\nsecond line');
    expect(store.lyricsForTrack('1')!.updatedAt, DateTime.utc(2026, 1, 5));

    await store.setLyrics('1', '   ');

    expect(store.lyricsForTrack('1'), isNull);
  });

  test('sets sidecar lyrics only when a track has no saved lyrics', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 6),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);
    await store.setLyrics('1', 'user edited lyrics');

    await store.setLyricsIfAbsent('1', 'sidecar lyrics');
    await store.setLyricsIfAbsent('2', 'new sidecar lyrics');

    expect(store.lyricsForTrack('1')!.plainText, 'user edited lyrics');
    expect(store.lyricsForTrack('2')!.plainText, 'new sidecar lyrics');
  });

  test('removing a library track removes its lyrics', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 6),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);
    await store.setLyrics('1', 'lyrics');

    await store.removeTrack('1');

    expect(store.lyricsForTrack('1'), isNull);
  });

  test('persists lyrics across store instances', () async {
    DateTime clock() => DateTime.utc(2026, 1, 7);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1')]);
    await firstStore.setLyrics('1', 'saved lyrics');

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.lyricsForTrack('1')!.plainText, 'saved lyrics');
  });

  test('persists and shares selected lyrics provider attribution', () async {
    DateTime clock() => DateTime.utc(2026, 1, 7);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[
      _track('1', title: 'Signal', artist: 'Mira', album: 'Dawn'),
    ]);
    await firstStore.setLyrics(
      '1',
      '[00:01.00]First line',
      sourceId: 'lrclib',
      sourceName: 'LRCLIB',
      sourceExternalId: '42',
      sourceUri: Uri.parse('https://lrclib.net/api/get/42'),
    );

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();
    final restored = secondStore.lyricsForTrack('1')!;
    final shareText = secondStore.shareLyricsText('1')!;
    final backup = secondStore.exportBackupJson();
    final backupStore = LibraryStore(clock: clock);
    await backupStore.load();
    await backupStore.restoreBackupJson(backup);

    expect(restored.sourceId, 'lrclib');
    expect(restored.sourceName, 'LRCLIB');
    expect(restored.sourceExternalId, '42');
    expect(restored.sourceUri, Uri.parse('https://lrclib.net/api/get/42'));
    expect(shareText, contains('Source: LRCLIB #42'));
    expect(shareText, contains('Source URL: https://lrclib.net/api/get/42'));
    expect(backupStore.lyricsForTrack('1')!.sourceName, 'LRCLIB');
    expect(backupStore.lyricsForTrack('1')!.sourceExternalId, '42');
  });

  test('builds limited lyrics share text from plain and synced lyrics', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 7, 1),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track('1', title: 'Plain Song', artist: 'Mira', album: 'Dawn'),
      _track('2', title: 'Synced Song', artist: 'Ari', album: 'Night'),
    ]);
    await store.setLyrics(
      '1',
      'first line\n\nsecond line\nthird line\nfourth line',
    );
    await store.setLyrics(
      '2',
      '[00:01.00]First synced\n[00:04.20]Second synced\nuntimed note',
    );

    final plainShare = store.shareLyricsText('1', maxLines: 3)!;
    expect(plainShare, contains('AetherTune lyrics'));
    expect(plainShare, contains('Track: Plain Song'));
    expect(plainShare, contains('Artist: Mira'));
    expect(plainShare, contains('Format: Plain text'));
    expect(plainShare, contains('Lines: 3 of 4'));
    expect(plainShare, contains('first line'));
    expect(plainShare, contains('third line'));
    expect(plainShare, contains('...'));
    expect(plainShare, isNot(contains('fourth line')));

    final selectedPlainShare = store.shareLyricsText(
      '1',
      startLine: 1,
      endLine: 3,
    )!;
    expect(selectedPlainShare, contains('Lines: 3 of 4 (selected 2-4)'));
    expect(selectedPlainShare, contains('second line'));
    expect(selectedPlainShare, contains('fourth line'));
    expect(selectedPlainShare, isNot(contains('first line')));

    final clampedRangeShare = store.shareLyricsText(
      '1',
      startLine: -2,
      endLine: 100,
      maxLines: 2,
    )!;
    expect(clampedRangeShare, contains('Lines: 2 of 4 (selected 1-4)'));
    expect(clampedRangeShare, contains('first line'));
    expect(clampedRangeShare, contains('second line'));
    expect(clampedRangeShare, isNot(contains('third line')));
    expect(clampedRangeShare, contains('...'));

    final syncedShare = store.shareLyricsText('2')!;
    expect(syncedShare, contains('Format: Synced LRC'));
    expect(syncedShare, contains('First synced'));
    expect(syncedShare, contains('Second synced'));
    expect(syncedShare, isNot(contains('[00:01.00]')));
    expect(syncedShare, isNot(contains('untimed note')));
    expect(
      store.lyricsShareLines('2'),
      <String>['First synced', 'Second synced'],
    );

    final draftShare = store.shareLyricsText(
      '1',
      plainText: '[00:02.00]Draft synced',
    )!;
    expect(draftShare, contains('Draft synced'));
    expect(draftShare, contains('Format: Synced LRC'));

    expect(store.shareLyricsText('missing'), isNull);
    expect(store.shareLyricsText('1', plainText: '   '), isNull);
  });

  test('exports saved lyrics as txt or lrc documents', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 7, 2),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track('1', title: 'Plain / Song', artist: ''),
      _track('2', title: 'Synced:Song', artist: 'Mira*Vale'),
    ]);
    await store.setLyrics('1', 'First line\r\nSecond line');
    await store.setLyrics(
      '2',
      '[00:01.00]First synced\r\n[00:04.20]Second synced',
    );

    final plainExport = store.exportLyricsDocument('1')!;
    final syncedExport = store.exportLyricsDocument('2')!;

    expect(plainExport.fileName, 'Plain Song.txt');
    expect(plainExport.text, 'First line\nSecond line');
    expect(syncedExport.fileName, 'Mira Vale - Synced Song.lrc');
    expect(syncedExport.text, contains('[00:01.00]First synced'));
    expect(syncedExport.text, contains('[00:04.20]Second synced'));
    expect(store.exportLyricsDocument('missing'), isNull);

    await store.setLyrics('1', '   ');

    expect(store.exportLyricsDocument('1'), isNull);
  });

  test(
    'records recently played tracks with counts and last played time',
    () async {
      var now = DateTime.utc(2026, 1, 8, 12);
      final store = LibraryStore(clock: () => now);
      await store.load();
      await store.addTracks(<Track>[_track('1'), _track('2'), _track('3')]);

      await store.recordPlayback('1');
      now = DateTime.utc(2026, 1, 8, 12, 1);
      await store.recordPlayback('2');
      now = DateTime.utc(2026, 1, 8, 12, 2);
      await store.recordPlayback('1');
      await store.recordPlayback('missing');

      expect(
        store.playbackHistory.map((entry) => entry.trackId),
        <String>['1', '2', '1'],
      );
      expect(
        store.recentlyPlayedTracks().map((track) => track.id),
        <String>['1', '2'],
      );
      expect(
        store.recentlyPlayedTracks(limit: 1).map((track) => track.id),
        <String>['1'],
      );
      expect(store.playCountForTrack('1'), 2);
      expect(store.playCountForTrack('2'), 1);
      expect(store.lastPlayedAt('1'), DateTime.utc(2026, 1, 8, 12, 2));

      await store.clearPlaybackHistory();

      expect(store.playbackHistory, isEmpty);
    },
  );

  test('builds library listening stats from playback history', () async {
    var now = DateTime.utc(2026, 1, 8, 13);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Aether One',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 3),
      ),
      _track(
        '2',
        title: 'Aether Two',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 4),
      ),
      _track(
        '3',
        title: 'Night Three',
        artist: 'Orion',
        album: 'Night',
        genre: 'Jazz',
        duration: const Duration(minutes: 5),
      ),
    ]);
    await store.toggleFavorite('2');
    await store.recordPlayback('1');
    now = DateTime.utc(2026, 1, 8, 13, 1);
    await store.recordPlayback('2');
    now = DateTime.utc(2026, 1, 8, 13, 2);
    await store.recordPlayback('1');
    now = DateTime.utc(2026, 1, 8, 13, 3);
    await store.recordPlayback('3');

    final stats = store.libraryStats(limit: 2);

    expect(stats.trackCount, 3);
    expect(stats.libraryDuration, const Duration(minutes: 12));
    expect(stats.favoriteTrackCount, 1);
    expect(stats.playbackCount, 4);
    expect(stats.uniquePlayedTrackCount, 3);
    expect(stats.estimatedListeningDuration, const Duration(minutes: 15));
    expect(
      stats.topTracks.map((trackStats) => trackStats.track.id),
      <String>['1', '3'],
    );
    expect(stats.topTracks.first.playCount, 2);
    expect(
      stats.topTracks.first.estimatedListeningDuration,
      const Duration(minutes: 6),
    );
    expect(stats.topArtists.map((group) => group.label), <String>[
      'Mira',
      'Orion',
    ]);
    expect(stats.topArtists.first.playCount, 3);
    expect(stats.topArtists.first.trackCount, 2);
    expect(stats.topAlbums.first.label, 'Dawn');
    expect(stats.topGenres.first.label, 'Ambient');
    expect(store.libraryStats(limit: 0).topTracks, isEmpty);
  });

  test('filters and exports library stats by playback date range', () async {
    var now = DateTime.utc(2026, 1, 1, 9);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Aether One',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 3),
      ),
      _track(
        '2',
        title: 'Night Two',
        artist: 'Orion',
        album: 'Night',
        genre: 'Jazz',
        duration: const Duration(minutes: 4),
      ),
      _track(
        '3',
        title: 'Old Three',
        artist: 'Ari',
        album: 'Archive',
        genre: 'Folk',
        duration: const Duration(minutes: 5),
      ),
    ]);

    await store.recordPlayback('3');
    now = DateTime.utc(2026, 1, 10, 10);
    await store.recordPlayback('1');
    now = DateTime.utc(2026, 1, 11, 10);
    await store.recordPlayback('1');
    now = DateTime.utc(2026, 1, 12, 10);
    await store.recordPlayback('2');

    final from = DateTime.utc(2026, 1, 10);
    final to = DateTime.utc(2026, 1, 13);
    final stats = store.libraryStats(limit: 2, from: from, to: to);

    expect(stats.from, from);
    expect(stats.to, to);
    expect(stats.playbackCount, 3);
    expect(stats.uniquePlayedTrackCount, 2);
    expect(stats.estimatedListeningDuration, const Duration(minutes: 10));
    expect(
      stats.topTracks.map((trackStats) => trackStats.track.id),
      <String>['1', '2'],
    );
    expect(store.playCountForTrack('1', from: from, to: to), 2);
    expect(
      store.lastPlayedAt('1', from: from, to: to),
      DateTime.utc(2026, 1, 11, 10),
    );
    expect(
      store.recentlyPlayedTracks(from: from, to: to).map((track) => track.id),
      <String>['2', '1'],
    );
    expect(store.libraryStats(from: to).playbackCount, 0);

    final jsonDocument = store.exportLibraryStatsDocument(
      format: LibraryStatsExportFormat.json,
      limit: 1,
      from: from,
      to: to,
    );
    final decoded = jsonDecode(jsonDocument) as Map<String, dynamic>;

    expect(decoded['type'], 'aethertune.library_stats');
    expect(decoded['version'], 1);
    expect(decoded['from'], from.toIso8601String());
    expect(decoded['to'], to.toIso8601String());
    expect((decoded['summary'] as Map<String, dynamic>)['playbackCount'], 3);
    expect((decoded['topTracks'] as List<dynamic>), hasLength(1));
    expect(
      ((decoded['topTracks'] as List<dynamic>).single
          as Map<String, dynamic>)['trackId'],
      '1',
    );

    final csvDocument = store.exportLibraryStatsDocument(
      format: LibraryStatsExportFormat.csv,
      from: from,
      to: to,
    );

    expect(csvDocument, contains('summary,playbackCount,3'));
    expect(csvDocument, contains('top_track,Aether One'));
    expect(csvDocument, contains(from.toIso8601String()));
    expect(csvDocument, contains(to.toIso8601String()));
  });

  test('aggregates listening heatmap days within an exact range', () async {
    var now = DateTime.utc(2026, 7, 5, 9);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track('one', title: 'One', duration: const Duration(minutes: 4)),
      _track('two', title: 'Two', duration: const Duration(minutes: 6)),
    ]);

    await store.recordPlayback('one');
    now = DateTime.utc(2026, 7, 5, 18);
    await store.recordPlayback('two');
    now = DateTime.utc(2026, 7, 6, 8);
    await store.recordPlayback('one');

    final days = store.listeningHeatmap(
      from: DateTime.utc(2026, 7, 4),
      to: DateTime.utc(2026, 7, 7),
    );

    expect(days, hasLength(4));
    expect(days[0].playbackCount, 0);
    expect(days[1].playbackCount, 2);
    expect(days[1].estimatedListeningDuration, const Duration(minutes: 10));
    expect(days[2].playbackCount, 1);
    expect(days[2].estimatedListeningDuration, const Duration(minutes: 4));
    expect(days[3].playbackCount, 0);
  });

  test('builds local chart snapshots for selected ranges', () async {
    var now = DateTime.utc(2026, 2, 1, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'old',
        title: 'Old Signal',
        artist: 'Ari',
        album: 'Archive',
        genre: 'Folk',
        duration: const Duration(minutes: 5),
      ),
      _track(
        'recent',
        title: 'Recent Signal',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 3),
      ),
      _track(
        'newer',
        title: 'Newer Signal',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 4),
      ),
    ]);

    now = DateTime.utc(2025, 12, 1, 12);
    await store.recordPlayback('old');
    now = DateTime.utc(2026, 1, 20, 12);
    await store.recordPlayback('recent');
    now = DateTime.utc(2026, 1, 30, 12);
    await store.recordPlayback('newer');
    now = DateTime.utc(2026, 2, 1, 12);

    final monthly = store.localCharts(
      range: LibraryChartRange.thirtyDays,
      limit: 2,
    );
    final allTime = store.localCharts(range: LibraryChartRange.allTime);

    expect(monthly.range, LibraryChartRange.thirtyDays);
    expect(monthly.stats.from, DateTime.utc(2026, 1, 2, 12));
    expect(monthly.stats.to, now);
    expect(monthly.stats.playbackCount, 2);
    expect(
      monthly.stats.topTracks.map((trackStats) => trackStats.track.id),
      <String>['newer', 'recent'],
    );
    expect(monthly.stats.topArtists.single.label, 'Mira');
    expect(allTime.stats.playbackCount, 3);
    expect(
      allTime.stats.topTracks.map((trackStats) => trackStats.track.id),
      contains('old'),
    );
  });

  test('builds calendar monthly and yearly listening recaps', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'jan',
        title: 'January Song',
        artist: 'Mira',
        album: 'Winter',
        genre: 'Ambient',
        duration: const Duration(minutes: 3),
      ),
      _track(
        'feb',
        title: 'February Song',
        artist: 'Orion',
        album: 'Signals',
        genre: 'Electronic',
        duration: const Duration(minutes: 4),
      ),
      _track(
        'mar',
        title: 'March Song',
        artist: 'Mira',
        album: 'Spring',
        genre: 'Ambient',
        duration: const Duration(minutes: 5),
      ),
    ]);

    now = DateTime.utc(2025, 12, 31, 20);
    await store.recordPlayback('jan');
    now = DateTime.utc(2026, 1, 5, 9);
    await store.recordPlayback('jan');
    now = DateTime.utc(2026, 1, 7, 10);
    await store.recordPlayback('feb');
    now = DateTime.utc(2026, 2, 1, 8);
    await store.recordPlayback('feb');
    now = DateTime.utc(2026, 2, 15, 8);
    await store.recordPlayback('feb');
    now = DateTime.utc(2026, 3, 2, 8);
    await store.recordPlayback('mar');

    final monthly = store.listeningRecaps(
      period: LibraryRecapPeriod.month,
      limit: 2,
      statsLimit: 2,
    );

    expect(
      monthly.map((recap) => recap.start),
      <DateTime>[
        DateTime.utc(2026, 3),
        DateTime.utc(2026, 2),
      ],
    );
    expect(monthly.first.period, LibraryRecapPeriod.month);
    expect(monthly.first.end, DateTime.utc(2026, 4));
    expect(monthly.first.stats.playbackCount, 1);
    expect(monthly.first.stats.topTracks.single.track.id, 'mar');
    expect(monthly.last.stats.playbackCount, 2);
    expect(monthly.last.stats.topTracks.single.track.id, 'feb');
    expect(monthly.last.stats.topTracks.single.playCount, 2);
    expect(
      monthly.last.stats.estimatedListeningDuration,
      const Duration(minutes: 8),
    );

    final yearly = store.listeningRecaps(
      period: LibraryRecapPeriod.year,
      limit: 3,
      statsLimit: 1,
    );

    expect(
      yearly.map((recap) => recap.start),
      <DateTime>[
        DateTime.utc(2026),
        DateTime.utc(2025),
      ],
    );
    expect(yearly.first.period, LibraryRecapPeriod.year);
    expect(yearly.first.end, DateTime.utc(2027));
    expect(yearly.first.stats.playbackCount, 5);
    expect(yearly.first.stats.topTracks.single.track.id, 'feb');
    expect(yearly.last.stats.playbackCount, 1);
    expect(store.listeningRecaps(limit: 0), isEmpty);
  });

  test('builds local mood mixes from playable library metadata', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 2, 2, 12),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'focus-favorite',
        title: 'Piano Focus',
        artist: 'Mira',
        album: 'Study Room',
        genre: 'Classical',
        duration: const Duration(minutes: 3),
      ),
      _track(
        'focus-long',
        title: 'Study Drift',
        artist: 'Ari',
        album: 'Deep Work',
        genre: 'Ambient',
        duration: const Duration(minutes: 5),
      ),
      _track(
        'energy',
        title: 'Power Run',
        artist: 'Nova',
        album: 'Bright',
        genre: 'Rock',
      ),
      _track(
        'chill',
        title: 'Mellow Jazz',
        artist: 'Sol',
        album: 'Late Lounge',
        genre: 'Jazz',
      ),
      _track(
        'workout',
        title: 'Gym Cardio',
        artist: 'Pulse',
        album: 'Motion',
        genre: 'Hip Hop',
      ),
      _track(
        'sleep',
        title: 'Night Drone',
        artist: 'Luma',
        album: 'Rest',
        genre: 'Meditation',
      ),
      _track(
        'unmatched',
        title: 'Plain Signal',
        artist: 'Orion',
        album: 'Archive',
        genre: 'Folk',
      ),
      _track(
        'metadata-only',
        title: 'Ambient Preview',
        artist: 'Cloud',
        album: 'Draft',
        genre: 'Ambient',
        localPath: '',
      ),
    ]);
    await store.toggleFavorite('focus-favorite');
    await store.recordPlayback('focus-favorite');

    final mixes = store.localMoodMixes(limit: 2);

    expect(
      mixes.map((mix) => mix.type),
      <LibraryMoodMixType>[
        LibraryMoodMixType.focus,
        LibraryMoodMixType.energy,
        LibraryMoodMixType.chill,
        LibraryMoodMixType.workout,
        LibraryMoodMixType.sleep,
      ],
    );
    expect(mixes.first.name, 'Focus mix');
    expect(
      store
          .tracksForMoodMix(LibraryMoodMixType.focus, limit: 2)
          .map((track) => track.id),
      <String>['focus-favorite', 'focus-long'],
    );
    expect(
      store
          .tracksForMoodMix(LibraryMoodMixType.energy)
          .map((track) => track.id),
      contains('energy'),
    );
    expect(
      store
          .tracksForMoodMix(LibraryMoodMixType.focus)
          .map((track) => track.id),
      isNot(contains('metadata-only')),
    );
    expect(store.localMoodMixes(limit: 0), isEmpty);

    final playlist = await store.saveMoodMixAsPlaylist(
      LibraryMoodMixType.focus,
      limit: 2,
    );
    expect(playlist, isNotNull);
    expect(playlist!.name, 'Focus mix');
    expect(playlist.trackIds, <String>['focus-favorite', 'focus-long']);
    expect(store.playlistById(playlist.id), playlist);

    expect(
      await store.saveMoodMixAsPlaylist(
        LibraryMoodMixType.focus,
        limit: 0,
      ),
      isNull,
    );
  });

  test('builds personalized local recommendations from taste signals', () async {
    var now = DateTime.utc(2026, 2, 3, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'seed',
        title: 'Aether Seed',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
      ),
      _track(
        'same-artist',
        title: 'Morning Signal',
        artist: 'Mira',
        album: 'Elsewhere',
        genre: 'Ambient',
      ),
      _track(
        'same-genre',
        title: 'Soft Current',
        artist: 'Ari',
        album: 'Still',
        genre: 'Ambient',
      ),
      _track(
        'same-album',
        title: 'Dawn Echo',
        artist: 'Vera',
        album: 'Dawn',
        genre: 'Pop',
      ),
      _track(
        'unrelated',
        title: 'Late Train',
        artist: 'Sol',
        album: 'Lines',
        genre: 'Jazz',
      ),
    ]);

    final fallback = store.personalizedRecommendationMatches(limit: 1);
    expect(fallback, hasLength(1));
    expect(
      fallback.single.reasons,
      const <LibraryRecommendationReason>[
        LibraryRecommendationReason.recentlyAdded,
      ],
    );

    await store.toggleFavorite('seed');
    await store.recordPlayback('seed');
    now = DateTime.utc(2026, 2, 3, 12, 1);
    await store.recordPlayback('unrelated');

    final matches = store.personalizedRecommendationMatches(limit: 3);
    final recommendations = store.personalizedRecommendations(limit: 3);

    expect(
      recommendations.map((track) => track.id),
      <String>['same-artist', 'same-genre', 'same-album'],
    );
    expect(
      matches.map((match) => match.track.id),
      <String>['same-artist', 'same-genre', 'same-album'],
    );
    expect(
      matches.first.reasons,
      containsAll(<LibraryRecommendationReason>[
        LibraryRecommendationReason.favoriteArtist,
        LibraryRecommendationReason.favoriteGenre,
        LibraryRecommendationReason.recentlyPlayedArtist,
        LibraryRecommendationReason.recentlyPlayedGenre,
        LibraryRecommendationReason.unplayed,
      ]),
    );
    expect(
      matches.last.reasons,
      containsAll(<LibraryRecommendationReason>[
        LibraryRecommendationReason.favoriteAlbum,
        LibraryRecommendationReason.recentlyPlayedAlbum,
      ]),
    );
    expect(matches.first.score, greaterThan(matches.last.score));

    await store.setRecommendationFavoriteSignalsEnabled(false);
    final historyOnly = store.personalizedRecommendationMatches(limit: 3);
    final historyOnlyReasons = historyOnly.expand((match) => match.reasons);
    expect(
      historyOnlyReasons,
      contains(LibraryRecommendationReason.recentlyPlayedArtist),
    );
    expect(
      historyOnlyReasons,
      isNot(contains(LibraryRecommendationReason.favoriteArtist)),
    );
    expect(
      historyOnlyReasons,
      isNot(contains(LibraryRecommendationReason.favoriteAlbum)),
    );
    expect(
      historyOnlyReasons,
      isNot(contains(LibraryRecommendationReason.favoriteGenre)),
    );
    expect(
      historyOnlyReasons,
      isNot(contains(LibraryRecommendationReason.favoriteTrack)),
    );

    await store.setRecommendationFavoriteSignalsEnabled(true);
    await store.setRecommendationHistorySignalsEnabled(false);
    final favoritesOnly = store.personalizedRecommendationMatches(limit: 3);
    final favoriteOnlyReasons = favoritesOnly.expand(
      (match) => match.reasons,
    );
    expect(
      favoriteOnlyReasons,
      contains(LibraryRecommendationReason.favoriteArtist),
    );
    expect(
      favoriteOnlyReasons,
      isNot(contains(LibraryRecommendationReason.recentlyPlayedArtist)),
    );
    expect(
      favoriteOnlyReasons,
      isNot(contains(LibraryRecommendationReason.recentlyPlayedAlbum)),
    );
    expect(
      favoriteOnlyReasons,
      isNot(contains(LibraryRecommendationReason.recentlyPlayedGenre)),
    );
    expect(
      favoriteOnlyReasons,
      isNot(contains(LibraryRecommendationReason.unplayed)),
    );

    await store.setRecommendationFavoriteSignalsEnabled(false);
    final fallbackWithoutTasteSignals = store
        .personalizedRecommendationMatches(limit: 3);
    expect(
      fallbackWithoutTasteSignals.map((match) => match.reasons),
      everyElement(const <LibraryRecommendationReason>[
        LibraryRecommendationReason.recentlyAdded,
      ]),
    );
    expect(
      fallbackWithoutTasteSignals.map((match) => match.score),
      everyElement(0),
    );
    expect(store.personalizedRecommendations(limit: 0), isEmpty);
    expect(store.personalizedRecommendationMatches(limit: 0), isEmpty);
  });

  test('builds similar local tracks from artist album and genre', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 2, 4, 12),
    );
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'seed',
        title: 'Seed Signal',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        localPath: '/music/Mira/Dawn/seed.mp3',
      ),
      _track(
        'same-artist',
        title: 'Mira Field',
        artist: 'Mira',
        album: 'Elsewhere',
        genre: 'Folk',
        localPath: '/music/Mira/Elsewhere/field.mp3',
      ),
      _track(
        'same-album',
        title: 'Dawn Echo',
        artist: 'Vera',
        album: 'Dawn',
        genre: 'Pop',
        localPath: '/music/Vera/Dawn/echo.mp3',
      ),
      _track(
        'same-genre',
        title: 'Soft Current',
        artist: 'Ari',
        album: 'Still',
        genre: 'Ambient',
        localPath: '/music/Ari/Still/current.mp3',
      ),
      _track(
        'same-folder-only',
        title: 'Folder Neighbor',
        artist: 'Orion',
        album: 'Night',
        genre: 'Jazz',
        localPath: '/music/Mira/Dawn/neighbor.mp3',
      ),
      _track(
        'metadata-only',
        title: 'Mira Preview',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        localPath: '',
      ),
    ]);
    await store.toggleFavorite('same-genre');
    await store.recordPlayback('same-genre');
    await store.recordPlayback('same-genre');

    final matches = store.similarTracksForTrack('seed');

    expect(
      matches.map((match) => match.track.id),
      <String>['same-artist', 'same-album', 'same-genre'],
    );
    expect(
      matches.first.reasons,
      contains(LibrarySimilarityReason.artist),
    );
    expect(
      matches.first.reasons,
      isNot(contains(LibrarySimilarityReason.album)),
    );
    final limitedMatches = store.similarTracksForTrack('seed', limit: 2);
    expect(
      limitedMatches.map((match) => match.track.id),
      <String>['same-artist', 'same-album'],
    );
    expect(store.similarTracksForTrack('missing'), isEmpty);
    expect(store.similarTracksForTrack('seed', limit: 0), isEmpty);
  });

  test('removing a library track removes its playback history', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 9),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);
    await store.recordPlayback('1');
    await store.recordPlayback('2');

    await store.removeTrack('1');

    expect(
      store.playbackHistory.map((entry) => entry.trackId),
      <String>['2'],
    );
  });

  test('persists playback history across store instances', () async {
    DateTime clock() => DateTime.utc(2026, 1, 10);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1')]);
    await firstStore.recordPlayback('1');

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.playbackHistory.single.trackId, '1');
    expect(secondStore.recentlyPlayedTracks().single.id, '1');
  });

  test('removes individual playback history entries', () async {
    var now = DateTime.utc(2026, 1, 10, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[_track('1'), _track('2')]);

    await store.recordPlayback('1');
    final olderPlay = store.playbackHistory.single;
    now = DateTime.utc(2026, 1, 10, 12, 1);
    await store.recordPlayback('1');
    final newerPlay = store.playbackHistory.first;
    now = DateTime.utc(2026, 1, 10, 12, 2);
    await store.recordPlayback('2');

    expect(
      store.playbackHistoryEntries(limit: 2).map((entry) => entry.trackId),
      <String>['2', '1'],
    );
    expect(
      store
          .playbackHistoryEntries(from: DateTime.utc(2026, 1, 10, 12, 1))
          .map((entry) => entry.trackId),
      <String>['2', '1'],
    );

    await store.removePlaybackHistoryEntry(newerPlay);

    expect(store.playCountForTrack('1'), 1);
    expect(store.lastPlayedAt('1'), olderPlay.playedAt);
    expect(
      store.playbackHistory.map((entry) => entry.trackId),
      <String>['2', '1'],
    );

    await store.removePlaybackHistoryEntry(newerPlay);
    expect(store.playbackHistory, hasLength(2));

    final secondStore = LibraryStore(clock: () => now);
    await secondStore.load();
    expect(secondStore.playbackHistory, hasLength(2));
    expect(secondStore.playCountForTrack('1'), 1);
  });

  test('searches playback history by played track metadata', () async {
    var now = DateTime.utc(2026, 1, 10, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'ambient',
        title: 'Aether Drift',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
      ),
      _track(
        'rock',
        title: 'Night Spark',
        artist: 'Orion',
        album: 'Voltage',
        genre: 'Rock',
      ),
    ]);

    await store.recordPlayback('ambient');
    now = DateTime.utc(2026, 1, 10, 12, 1);
    await store.recordPlayback('rock');
    now = DateTime.utc(2026, 1, 10, 12, 2);
    await store.recordPlayback('ambient');

    expect(
      store.recentlyPlayedTracks(query: 'mira').map((track) => track.id),
      <String>['ambient'],
    );
    expect(
      store.playbackHistoryEntries(query: 'mira').map((entry) => entry.trackId),
      <String>['ambient', 'ambient'],
    );
    expect(
      store
          .playbackHistoryEntries(limit: 1, query: 'ambient')
          .map((entry) => entry.trackId),
      <String>['ambient'],
    );
    expect(
      store.playbackHistoryEntries(query: 'voltage').map(
            (entry) => entry.trackId,
          ),
      <String>['rock'],
    );
    expect(store.recentlyPlayedTracks(query: 'missing'), isEmpty);
    expect(store.playbackHistoryEntries(query: 'missing'), isEmpty);
  });

  test('creates updates persists backs up and deletes saved history views',
      () async {
    var now = DateTime.utc(2026, 1, 10, 13);
    final firstStore = LibraryStore(clock: () => now);
    await firstStore.load();

    final created = await firstStore.createSavedHistoryView(
      name: '  Recent Mira  ',
      query: '  mira  ',
      range: ListeningHistoryRange.sevenDays,
    );

    expect(created.name, 'Recent Mira');
    expect(created.query, 'mira');
    expect(created.range, ListeningHistoryRange.sevenDays);
    expect(firstStore.savedHistoryViews.single.id, created.id);
    await expectLater(
      firstStore.createSavedHistoryView(name: '   '),
      throwsArgumentError,
    );

    now = DateTime.utc(2026, 1, 10, 14);
    final updated = await firstStore.updateSavedHistoryView(
      created.id,
      name: 'Mira month',
      query: '  ambient  ',
      range: ListeningHistoryRange.thirtyDays,
    );

    expect(updated, isNotNull);
    final updatedView = updated!;
    expect(updatedView.name, 'Mira month');
    expect(updatedView.query, 'ambient');
    expect(updatedView.range, ListeningHistoryRange.thirtyDays);
    expect(updatedView.updatedAt, now);
    expect(
      await firstStore.updateSavedHistoryView(
        'missing',
        name: 'Missing',
        query: '',
        range: ListeningHistoryRange.all,
      ),
      isNull,
    );

    final secondStore = LibraryStore(clock: () => now);
    await secondStore.load();
    expect(
      secondStore.savedHistoryViews.single.toJson(),
      updatedView.toJson(),
    );

    final backup = jsonDecode(secondStore.exportBackupJson())
        as Map<String, dynamic>;
    expect(backup['savedHistoryViews'], hasLength(1));

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final restoredStore = LibraryStore(clock: () => now);
    await restoredStore.load();
    await restoredStore.restoreBackupJson(jsonEncode(backup));
    expect(
      restoredStore.savedHistoryViews.single.toJson(),
      updatedView.toJson(),
    );

    await restoredStore.deleteSavedHistoryView(created.id);
    expect(restoredStore.savedHistoryViews, isEmpty);
    await restoredStore.deleteSavedHistoryView(created.id);
    expect(restoredStore.savedHistoryViews, isEmpty);

    backup.remove('savedHistoryViews');
    await restoredStore.restoreBackupJson(jsonEncode(backup));
    expect(restoredStore.savedHistoryViews, isEmpty);
  });

  test('pauses playback history and resume progress recording', () async {
    var now = DateTime.utc(2026, 1, 10, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[_track('private')]);

    await store.setPauseListeningHistory(true);
    await store.recordPlayback('private');
    await store.recordPlaybackProgress(
      'private',
      const Duration(minutes: 2),
      const Duration(minutes: 5),
    );

    expect(store.pauseListeningHistory, isTrue);
    expect(store.playbackHistory, isEmpty);
    expect(store.recentlyPlayedTracks(), isEmpty);
    expect(store.playCountForTrack('private'), 0);
    expect(store.playbackProgressForTrack('private'), isNull);

    now = DateTime.utc(2026, 1, 10, 12, 1);
    await store.setPauseListeningHistory(false);
    await store.recordPlayback('private');
    await store.recordPlaybackProgress(
      'private',
      const Duration(minutes: 3),
      const Duration(minutes: 5),
    );

    expect(store.pauseListeningHistory, isFalse);
    expect(store.playbackHistory.single.trackId, 'private');
    expect(store.playCountForTrack('private'), 1);
    expect(
      store.playbackProgressForTrack('private')!.position,
      const Duration(minutes: 3),
    );
  });

  test('records persists and clears playback progress', () async {
    DateTime clock() => DateTime.utc(2026, 1, 14, 14);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('podcast')]);

    await firstStore.recordPlaybackProgress(
      'podcast',
      const Duration(minutes: 3),
      const Duration(minutes: 30),
    );

    expect(
      firstStore.playbackProgressForTrack('podcast')!.position,
      const Duration(minutes: 3),
    );

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(
      secondStore.playbackProgressForTrack('podcast')!.duration,
      const Duration(minutes: 30),
    );

    await secondStore.recordPlaybackProgress(
      'podcast',
      const Duration(seconds: 2),
      const Duration(minutes: 30),
    );

    expect(secondStore.playbackProgressForTrack('podcast'), isNull);

    await secondStore.recordPlaybackProgress(
      'podcast',
      const Duration(minutes: 10),
      const Duration(minutes: 30),
    );

    expect(secondStore.playbackProgressForTrack('podcast'), isNotNull);

    await secondStore.recordPlaybackProgress(
      'podcast',
      const Duration(minutes: 29, seconds: 45),
      const Duration(minutes: 30),
    );

    expect(secondStore.playbackProgressForTrack('podcast'), isNull);
  });

  test('saves persists and deletes podcast feed subscriptions', () async {
    var now = DateTime.utc(2026, 1, 15);
    DateTime clock() => now;
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();

    final subscription = await firstStore.savePodcastSubscription(
      PodcastSubscription(
        id: 'ignored',
        feedUrl: ' https://feeds.example.test/aether.xml ',
        title: ' Aether Radio ',
        description: ' Open feed ',
        author: ' Aether Hosts ',
        artworkUri: Uri.parse('https://media.example.test/show.jpg'),
        episodes: <Track>[
          _track(
            'episode-1',
            sourceId: 'podcast-rss',
            addedAt: DateTime.utc(2026, 1, 14),
          ),
        ],
      ),
    );
    await firstStore.savePodcastSubscription(
      PodcastSubscription(
        id: 'ignored-again',
        feedUrl: 'https://feeds.example.test/aether.xml',
        title: 'Aether Radio Updated',
      ),
    );

    expect(firstStore.podcastSubscriptions, hasLength(1));
    expect(
      firstStore.podcastSubscriptions.single.id,
      stablePodcastSubscriptionId('https://feeds.example.test/aether.xml'),
    );
    expect(firstStore.podcastSubscriptions.single.title, 'Aether Radio Updated');
    expect(
      firstStore.podcastSubscriptions.single.episodes.map((track) => track.id),
      <String>['episode-1'],
    );
    expect(subscription.addedAt, DateTime.utc(2026, 1, 15));

    now = DateTime.utc(2026, 1, 15, 6);
    final refreshed = await firstStore.markPodcastSubscriptionFetched(
      subscription.id,
    );

    expect(refreshed!.lastFetchedAt, DateTime.utc(2026, 1, 15, 6));
    expect(
      refreshed.isRefreshDue(
        DateTime.utc(2026, 1, 15, 17, 59),
      ),
      isFalse,
    );
    expect(
      refreshed.isRefreshDue(
        DateTime.utc(2026, 1, 15, 18),
      ),
      isTrue,
    );

    final failed = await firstStore.markPodcastSubscriptionFetchFailed(
      subscription.id,
      'network down',
    );

    expect(failed!.lastFetchError, 'network down');

    now = DateTime.utc(2026, 1, 15, 8);
    final recovered = await firstStore.markPodcastSubscriptionFetched(
      subscription.id,
    );

    expect(recovered!.lastFetchedAt, DateTime.utc(2026, 1, 15, 8));
    expect(recovered.lastFetchError, isEmpty);

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();

    expect(secondStore.podcastSubscriptions, hasLength(1));
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.feedUrl,
      'https://feeds.example.test/aether.xml',
    );
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.lastFetchedAt,
      DateTime.utc(2026, 1, 15, 8),
    );
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.lastFetchError,
      isEmpty,
    );
    expect(
      secondStore
          .podcastSubscriptionById(subscription.id)!
          .episodes
          .map((track) => track.id),
      <String>['episode-1'],
    );

    await secondStore.deletePodcastSubscription(subscription.id);

    expect(secondStore.podcastSubscriptions, isEmpty);
  });

  test('sorts library searches and exposes recently added tracks', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'old',
        title: 'Gamma',
        artist: 'Zed',
        album: 'Third',
        addedAt: DateTime.utc(2026, 1, 1),
      ),
      _track(
        'middle',
        title: 'Alpha',
        artist: 'Mia',
        album: 'First',
        addedAt: DateTime.utc(2026, 1, 2),
      ),
      _track(
        'new',
        title: 'Beta',
        artist: 'Ari',
        album: 'Second',
        genre: 'Ambient',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
    ]);

    expect(
      store.recentlyAddedTracks().map((track) => track.id),
      <String>['new', 'middle', 'old'],
    );
    expect(
      store.recentlyAddedTracks(limit: 2).map((track) => track.id),
      <String>['new', 'middle'],
    );
    expect(
      store.search('').map((track) => track.id),
      <String>['new', 'middle', 'old'],
    );
    final titleSorted = store.search('', sortMode: LibrarySortMode.title);
    final artistSorted = store.search('', sortMode: LibrarySortMode.artist);
    final albumSorted = store.search('', sortMode: LibrarySortMode.album);

    expect(
      titleSorted.map((track) => track.title),
      <String>['Alpha', 'Beta', 'Gamma'],
    );
    expect(
      artistSorted.map((track) => track.artist),
      <String>['Ari', 'Mia', 'Zed'],
    );
    expect(
      albumSorted.map((track) => track.album),
      <String>['First', 'Second', 'Third'],
    );
    expect(store.search('ambient').single.id, 'new');
  });

  test(
    'searches saved plain and synced lyrics without timestamp matches',
    () async {
      final store = LibraryStore();
      await store.load();
      await store.addTracks(<Track>[
        _track(
          'plain',
          title: 'Plain Song',
          artist: 'Mira',
          addedAt: DateTime.utc(2026, 1, 1),
        ),
        _track(
          'synced',
          title: 'Synced Song',
          artist: 'Ari',
          addedAt: DateTime.utc(2026, 1, 2),
        ),
        _track(
          'other',
          title: 'Quiet Song',
          artist: 'Orion',
          addedAt: DateTime.utc(2026, 1, 3),
        ),
      ]);
      await store.setLyrics('plain', 'Hidden aurora line\nsecond line');
      await store.setLyrics(
        'synced',
        '[00:01.00]Silver chorus\n[00:05.25]Midnight bridge',
      );
      await store.setLyrics('other', 'different words');
      final playlist = await store.createPlaylist(
        'Lyric Search',
        trackIds: <String>['other', 'plain', 'synced'],
      );
      final smartRule = await store.createCustomSmartPlaylist(
        name: 'Aurora lyrics',
        query: 'aurora',
        sortMode: CustomSmartPlaylistSortMode.title,
        limit: 10,
      );

      expect(
        store.search('aurora').map((track) => track.id),
        <String>['plain'],
      );
      expect(
        store.search('silver chorus').map((track) => track.id),
        <String>['synced'],
      );
      expect(store.search('00:01'), isEmpty);
      expect(
        store.tracksForPlaylist(playlist.id, query: 'midnight').map(
              (track) => track.id,
            ),
        <String>['synced'],
      );
      expect(
        store.tracksForCustomSmartPlaylist(smartRule.id).map(
              (track) => track.id,
            ),
        <String>['plain'],
      );
    },
  );

  test('filters library searches to local offline-playable tracks', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      Track(
        id: 'local',
        title: 'Ambient Local',
        artist: 'Mia',
        album: 'Offline',
        genre: 'Ambient',
        localPath: '/music/ambient-local.mp3',
      ),
      Track(
        id: 'stream',
        title: 'Ambient Stream',
        artist: 'Mia',
        album: 'Archive',
        genre: 'Ambient',
        streamUrl: 'https://media.example.test/ambient.mp3',
        sourceId: 'archive',
      ),
    ]);

    expect(
      store.search('ambient').map((track) => track.id),
      containsAll(<String>['local', 'stream']),
    );
    expect(
      store.search('ambient', offlineOnly: true).map((track) => track.id),
      <String>['local'],
    );
  });

  test(
    'matches local searches suggestions playlists and lyrics with typos',
    () async {
      final store = LibraryStore();
      await store.load();
      await store.addTracks(<Track>[
        _track(
          'ambient',
          title: 'Ambient Signal',
          artist: 'Mira Vale',
          album: 'Dawn Archive',
          genre: 'Ambient',
        ),
        _track(
          'other',
          title: 'Night Drive',
          artist: 'Ari Vale',
          album: 'Road Mix',
          genre: 'Electronic',
        ),
      ]);
      await store.setLyrics('other', 'silver chorus on the open road');
      final playlist = await store.createPlaylist(
        'Typo Mix',
        trackIds: <String>['ambient', 'other'],
      );

      expect(store.search('ambent').single.id, 'ambient');
      expect(store.search('mria').single.id, 'ambient');
      expect(store.search('silvr choruz').single.id, 'other');
      expect(
        store.searchSuggestions('ambent').map((suggestion) => suggestion.value),
        contains('Ambient Signal'),
      );
      expect(
        store.tracksForPlaylist(playlist.id, query: 'ambent').single.id,
        'ambient',
      );
    },
  );

  test('builds local search suggestions from recent playback and metadata', () async {
    var now = DateTime.utc(2026, 1, 15, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'ambient',
        title: 'Ambient Signal',
        artist: 'Mia Nova',
        album: 'Dawn Archive',
        genre: 'Ambient',
        sourceId: 'archive',
        localPath: '/music/Mia/Dawn/ambient.mp3',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
      _track(
        'jazz',
        title: 'Late Train',
        artist: 'Ari Vale',
        album: 'Night Lines',
        genre: 'Jazz',
        sourceId: 'radio',
        localPath: '/music/Ari/Night/train.mp3',
        addedAt: DateTime.utc(2026, 1, 2),
      ),
    ]);

    await store.recordPlayback('jazz');
    now = DateTime.utc(2026, 1, 15, 12, 1);
    await store.recordPlayback('ambient');

    final suggestions = store.searchSuggestions('');

    expect(
      suggestions.take(2).map((suggestion) => suggestion.type),
      <SearchSuggestionType>[
        SearchSuggestionType.recent,
        SearchSuggestionType.recent,
      ],
    );
    expect(
      suggestions.take(2).map((suggestion) => suggestion.value),
      <String>['Ambient Signal', 'Late Train'],
    );
    expect(
      suggestions.map((suggestion) => suggestion.value),
      containsAll(<String>[
        'Mia Nova',
        'Dawn Archive',
        'Ambient',
        'archive',
        '/music/Mia/Dawn',
      ]),
    );
    expect(
      suggestions.map((suggestion) => suggestion.value).toSet(),
      hasLength(suggestions.length),
    );

    expect(
      store.searchSuggestions('dawn').map((suggestion) => suggestion.value),
      containsAll(<String>['Dawn Archive', '/music/Mia/Dawn']),
    );
    expect(
      store.search('/music/mia/dawn').map((track) => track.id),
      <String>['ambient'],
    );
    expect(store.searchSuggestions('ambient', limit: 1), hasLength(1));
  });

  test('persists submitted search query history for suggestions', () async {
    final store = LibraryStore();
    await store.load();

    for (var index = 0; index < 25; index += 1) {
      await store.recordSearchQuery('Query $index');
    }
    await store.recordSearchQuery(' query 20 ');
    await store.recordSearchQuery('');

    expect(store.searchQueryHistory, hasLength(20));
    expect(store.searchQueryHistory.first, 'query 20');
    expect(store.searchQueryHistory, isNot(contains('Query 4')));

    final suggestions = store.searchSuggestions('20');
    expect(suggestions.single.type, SearchSuggestionType.query);
    expect(suggestions.single.value, 'query 20');

    final secondStore = LibraryStore();
    await secondStore.load();

    expect(secondStore.searchQueryHistory.first, 'query 20');
    expect(
      secondStore.searchSuggestions('').first.type,
      SearchSuggestionType.query,
    );

    final backupJson = secondStore.exportBackupJson();
    final thirdStore = LibraryStore();
    await thirdStore.load();
    await thirdStore.restoreBackupJson(backupJson);

    expect(thirdStore.searchQueryHistory, secondStore.searchQueryHistory);
  });

  test('persists app settings and restores them from backups', () async {
    final firstStore = LibraryStore();
    await firstStore.load();

    expect(firstStore.offlineModeEnabled, isFalse);
    expect(firstStore.pauseListeningHistory, isFalse);
    expect(firstStore.recommendationFavoriteSignalsEnabled, isTrue);
    expect(firstStore.recommendationHistorySignalsEnabled, isTrue);
    expect(firstStore.themePreference, AppThemePreference.system);
    expect(firstStore.accentColor, AppAccentColor.system);
    expect(firstStore.languagePreference, AppLanguagePreference.system);
    expect(
      firstStore.desktopQueuePaneWidth,
      LibraryStore.defaultDesktopQueuePaneWidth,
    );
    expect(firstStore.desktopMinimizeToTray, isFalse);
    expect(
      firstStore.offlineCacheLimitMegabytes,
      LibraryStore.defaultOfflineCacheLimitMegabytes,
    );
    expect(firstStore.offlineCacheProviderLimitMegabytes, isEmpty);

    await firstStore.setOfflineModeEnabled(true);
    await firstStore.setPauseListeningHistory(true);
    await firstStore.setRecommendationFavoriteSignalsEnabled(false);
    await firstStore.setRecommendationHistorySignalsEnabled(false);
    await firstStore.setThemePreference(AppThemePreference.amoled);
    await firstStore.setAccentColor(AppAccentColor.rose);
    await firstStore.setLanguagePreference(AppLanguagePreference.arabic);
    await firstStore.setDesktopQueuePaneWidth(410);
    await firstStore.setDesktopMinimizeToTray(true);
    await firstStore.setOfflineCacheLimitMegabytes(2048);
    await firstStore.setOfflineCacheProviderLimitMegabytes(
      ' Internet-Archive ',
      256,
    );

    expect(firstStore.offlineModeEnabled, isTrue);
    expect(firstStore.pauseListeningHistory, isTrue);
    expect(firstStore.recommendationFavoriteSignalsEnabled, isFalse);
    expect(firstStore.recommendationHistorySignalsEnabled, isFalse);
    expect(firstStore.themePreference, AppThemePreference.amoled);
    expect(firstStore.accentColor, AppAccentColor.rose);
    expect(firstStore.languagePreference, AppLanguagePreference.arabic);
    expect(firstStore.desktopQueuePaneWidth, 410);
    expect(firstStore.desktopMinimizeToTray, isTrue);
    expect(firstStore.offlineCacheLimitMegabytes, 2048);
    expect(firstStore.offlineCacheLimitBytes, 2048 * 1024 * 1024);
    expect(
      firstStore.offlineCacheProviderLimitMegabytesFor('internet-archive'),
      256,
    );
    expect(
      firstStore.offlineCacheProviderLimitBytesFor('internet-archive'),
      256 * 1024 * 1024,
    );

    final secondStore = LibraryStore();
    await secondStore.load();

    expect(secondStore.offlineModeEnabled, isTrue);
    expect(secondStore.pauseListeningHistory, isTrue);
    expect(secondStore.recommendationFavoriteSignalsEnabled, isFalse);
    expect(secondStore.recommendationHistorySignalsEnabled, isFalse);
    expect(secondStore.themePreference, AppThemePreference.amoled);
    expect(secondStore.accentColor, AppAccentColor.rose);
    expect(secondStore.languagePreference, AppLanguagePreference.arabic);
    expect(secondStore.desktopQueuePaneWidth, 410);
    expect(secondStore.desktopMinimizeToTray, isTrue);
    expect(secondStore.offlineCacheLimitMegabytes, 2048);
    expect(
      secondStore.offlineCacheProviderLimitMegabytesFor('internet-archive'),
      256,
    );

    final backupJson = secondStore.exportBackupJson();
    final backup = jsonDecode(backupJson) as Map<String, dynamic>;
    expect(backup['offlineModeEnabled'], isTrue);
    expect(backup['pauseListeningHistory'], isTrue);
    expect(backup['recommendationFavoriteSignalsEnabled'], isFalse);
    expect(backup['recommendationHistorySignalsEnabled'], isFalse);
    expect(backup['themePreference'], AppThemePreference.amoled.name);
    expect(backup['accentColor'], AppAccentColor.rose.name);
    expect(backup['languagePreference'], AppLanguagePreference.arabic.name);
    expect(backup['offlineCacheLimitMegabytes'], 2048);
    expect(
      backup['offlineCacheProviderLimitMegabytes'],
      <String, dynamic>{'internet-archive': 256},
    );

    final legacyBackup = Map<String, dynamic>.from(backup)
      ..remove('offlineModeEnabled')
      ..remove('pauseListeningHistory')
      ..remove('recommendationFavoriteSignalsEnabled')
      ..remove('recommendationHistorySignalsEnabled')
      ..remove('themePreference')
      ..remove('accentColor')
      ..remove('languagePreference')
      ..remove('offlineCacheLimitMegabytes')
      ..remove('offlineCacheProviderLimitMegabytes');
    await secondStore.restoreBackupJson(jsonEncode(legacyBackup));

    expect(secondStore.offlineModeEnabled, isFalse);
    expect(secondStore.pauseListeningHistory, isFalse);
    expect(secondStore.recommendationFavoriteSignalsEnabled, isTrue);
    expect(secondStore.recommendationHistorySignalsEnabled, isTrue);
    expect(secondStore.themePreference, AppThemePreference.system);
    expect(secondStore.accentColor, AppAccentColor.system);
    expect(secondStore.languagePreference, AppLanguagePreference.system);
    expect(secondStore.desktopMinimizeToTray, isTrue);
    expect(
      secondStore.offlineCacheLimitMegabytes,
      LibraryStore.defaultOfflineCacheLimitMegabytes,
    );
    expect(secondStore.offlineCacheProviderLimitMegabytes, isEmpty);

    await secondStore.restoreBackupJson(backupJson);

    expect(secondStore.offlineModeEnabled, isTrue);
    expect(secondStore.pauseListeningHistory, isTrue);
    expect(secondStore.recommendationFavoriteSignalsEnabled, isFalse);
    expect(secondStore.recommendationHistorySignalsEnabled, isFalse);
    expect(secondStore.themePreference, AppThemePreference.amoled);
    expect(secondStore.accentColor, AppAccentColor.rose);
    expect(secondStore.languagePreference, AppLanguagePreference.arabic);
    expect(secondStore.offlineCacheLimitMegabytes, 2048);
    expect(
      secondStore.offlineCacheProviderLimitMegabytesFor('internet-archive'),
      256,
    );
  });

  test('persists returning from a named accent to System colors', () async {
    final firstStore = LibraryStore();
    await firstStore.load();

    await firstStore.setAccentColor(AppAccentColor.rose);
    await firstStore.setAccentColor(AppAccentColor.system);

    final restoredStore = LibraryStore();
    await restoredStore.load();

    expect(restoredStore.accentColor, AppAccentColor.system);
  });

  test('clamps offline cache limit setting and restored backups', () async {
    final store = LibraryStore();
    await store.load();

    await store.setOfflineCacheLimitMegabytes(1);
    expect(
      store.offlineCacheLimitMegabytes,
      LibraryStore.minOfflineCacheLimitMegabytes,
    );

    final persistedStore = LibraryStore();
    await persistedStore.load();
    expect(
      persistedStore.offlineCacheLimitMegabytes,
      LibraryStore.minOfflineCacheLimitMegabytes,
    );

    await persistedStore.setOfflineCacheLimitMegabytes(
      LibraryStore.maxOfflineCacheLimitMegabytes + 1,
    );
    expect(
      persistedStore.offlineCacheLimitMegabytes,
      LibraryStore.maxOfflineCacheLimitMegabytes,
    );
    await persistedStore.setOfflineCacheProviderLimitMegabytes(
      'podcast-rss',
      0,
    );
    expect(
      persistedStore.offlineCacheProviderLimitMegabytesFor('podcast-rss'),
      isNull,
    );
    await persistedStore.setOfflineCacheProviderLimitMegabytes(
      'podcast-rss',
      -5,
    );
    expect(
      persistedStore.offlineCacheProviderLimitMegabytesFor('podcast-rss'),
      isNull,
    );
    await persistedStore.setOfflineCacheProviderLimitMegabytes(
      'podcast-rss',
      LibraryStore.maxOfflineCacheLimitMegabytes + 1,
    );
    expect(
      persistedStore.offlineCacheProviderLimitMegabytesFor('podcast-rss'),
      LibraryStore.maxOfflineCacheLimitMegabytes,
    );
    await persistedStore.setOfflineCacheProviderLimitMegabytes(
      'podcast-rss',
      null,
    );
    expect(
      persistedStore.offlineCacheProviderLimitMegabytesFor('podcast-rss'),
      isNull,
    );

    final backup = jsonDecode(
      persistedStore.exportBackupJson(),
    ) as Map<String, dynamic>;
    backup['offlineCacheLimitMegabytes'] = 1;
    await persistedStore.restoreBackupJson(jsonEncode(backup));
    expect(
      persistedStore.offlineCacheLimitMegabytes,
      LibraryStore.minOfflineCacheLimitMegabytes,
    );

    backup['offlineCacheLimitMegabytes'] =
        LibraryStore.maxOfflineCacheLimitMegabytes + 1;
    await persistedStore.restoreBackupJson(jsonEncode(backup));
    expect(
      persistedStore.offlineCacheLimitMegabytes,
      LibraryStore.maxOfflineCacheLimitMegabytes,
    );
  });

  test('clamps the persisted desktop queue pane width', () async {
    final store = LibraryStore();
    await store.load();

    await store.setDesktopQueuePaneWidth(-1);
    expect(
      store.desktopQueuePaneWidth,
      LibraryStore.minDesktopQueuePaneWidth,
    );

    await store.setDesktopQueuePaneWidth(10000);
    expect(
      store.desktopQueuePaneWidth,
      LibraryStore.maxDesktopQueuePaneWidth,
    );
  });

  test('persists per-track playback speed overrides locally', () async {
    final firstStore = LibraryStore();
    await firstStore.load();
    await firstStore.setTrackPlaybackSpeed('podcast-episode', 1.5);

    expect(firstStore.playbackSpeedForTrack('podcast-episode'), 1.5);
    await expectLater(
      firstStore.setTrackPlaybackSpeed('podcast-episode', 1.1),
      throwsArgumentError,
    );

    final secondStore = LibraryStore();
    await secondStore.load();
    expect(secondStore.playbackSpeedForTrack('podcast-episode'), 1.5);

    await secondStore.clearTrackPlaybackSpeed('podcast-episode');
    expect(secondStore.playbackSpeedForTrack('podcast-episode'), isNull);
  });

  test(
    'queues policy approved offline cache entries and persists them',
    () async {
      var now = DateTime.utc(2026, 1, 16, 12);
      DateTime clock() => now;
      final provider = InternetArchiveProvider();
      final policy = OfflineMediaPolicy(<MusicSourceProvider>[provider]);
      final track = _track(
        'archive-1',
        title: 'Archive Field Recording',
        sourceId: provider.id,
        externalId: 'archive-item',
        localPath: '',
        streamUrl: 'https://archive.org/download/archive-item/audio.mp3',
      );
      final firstStore = LibraryStore(clock: clock);
      await firstStore.load();

      final decision = policy.evaluate(track, OfflineMediaAction.cache);
      expect(decision.isAllowed, isTrue);

      final entry = await firstStore.queueOfflineCache(
        track,
        OfflineMediaAction.cache,
        decision,
      );

      expect(entry.status, OfflineCacheEntryStatus.queued);
      expect(firstStore.offlineCacheQueue.single.id, entry.id);
      expect(firstStore.offlineCacheQueue.single.track.title, track.title);

      now = DateTime.utc(2026, 1, 16, 13);
      final updatedTrack = track.copyWith(title: 'Archive Field Recording II');
      await firstStore.queueOfflineCache(
        updatedTrack,
        OfflineMediaAction.cache,
        policy.evaluate(updatedTrack, OfflineMediaAction.cache),
      );

      expect(firstStore.offlineCacheQueue, hasLength(1));
      expect(firstStore.offlineCacheQueue.single.createdAt, entry.createdAt);
      expect(firstStore.offlineCacheQueue.single.updatedAt, now);
      expect(
        firstStore.offlineCacheQueue.single.track.title,
        'Archive Field Recording II',
      );

      final secondStore = LibraryStore(clock: clock);
      await secondStore.load();

      expect(secondStore.offlineCacheQueue.single.id, entry.id);
      expect(
        secondStore.offlineCacheQueue.single.action,
        OfflineMediaAction.cache,
      );

      final backupJson = secondStore.exportBackupJson();
      final backup = jsonDecode(backupJson) as Map<String, dynamic>;
      expect(backup['offlineCacheQueue'], hasLength(1));

      final thirdStore = LibraryStore(clock: clock);
      await thirdStore.load();
      await thirdStore.restoreBackupJson(backupJson);

      expect(thirdStore.offlineCacheQueue.single.id, entry.id);

      final legacyBackup = Map<String, dynamic>.from(backup);
      final legacyQueue =
          (legacyBackup['offlineCacheQueue'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
      legacyQueue.single
        ..remove('cachedByteCount')
        ..remove('cachedMediaChecksum');
      final legacyStore = LibraryStore(clock: clock);
      await legacyStore.load();
      await legacyStore.restoreBackupJson(jsonEncode(legacyBackup));
      expect(legacyStore.offlineCacheQueue.single.cachedByteCount, 0);
      expect(legacyStore.offlineCacheQueue.single.cachedMediaChecksum, '');

      await thirdStore.removeOfflineCacheEntry(entry.id);
      expect(thirdStore.offlineCacheQueue, isEmpty);

      await thirdStore.queueOfflineCache(
        track,
        OfflineMediaAction.download,
        policy.evaluate(track, OfflineMediaAction.download),
      );
      expect(
        thirdStore.offlineCacheQueue.single.action,
        OfflineMediaAction.download,
      );

      await thirdStore.clearOfflineCacheQueue();
      expect(thirdStore.offlineCacheQueue, isEmpty);
    },
  );

  test(
    'rejects offline cache queue entries denied by provider policy',
    () async {
      final provider = RadioBrowserProvider();
      final policy = OfflineMediaPolicy(<MusicSourceProvider>[provider]);
      final track = _track(
        'radio-1',
        title: 'Live Station',
        sourceId: provider.id,
        externalId: 'station-id',
        localPath: '',
        streamUrl: 'https://radio.example.test/live.mp3',
      );
      final store = LibraryStore();
      await store.load();

      final decision = policy.evaluate(track, OfflineMediaAction.cache);

      expect(decision.isAllowed, isFalse);
      expect(
        store.queueOfflineCache(track, OfflineMediaAction.cache, decision),
        throwsA(isA<StateError>()),
      );
      expect(store.offlineCacheQueue, isEmpty);
    },
  );

  test('marks offline cache entries and upserts cached tracks', () async {
    var now = DateTime.utc(2026, 1, 16, 14);
    DateTime clock() => now;
    final provider = InternetArchiveProvider();
    final policy = OfflineMediaPolicy(<MusicSourceProvider>[provider]);
    final track = _track(
      'archive-cache',
      title: 'Archive Cache',
      sourceId: provider.id,
      externalId: 'archive-cache',
      localPath: '',
      streamUrl: 'https://archive.org/download/archive-cache/audio.mp3',
    );
    final store = LibraryStore(clock: clock);
    await store.load();

    final queued = await store.queueOfflineCache(
      track,
      OfflineMediaAction.cache,
      policy.evaluate(track, OfflineMediaAction.cache),
    );

    now = DateTime.utc(2026, 1, 16, 15);
    final processing = await store.markOfflineCacheEntryProcessing(queued.id);

    expect(processing!.status, OfflineCacheEntryStatus.processing);
    expect(processing.reason, 'Caching media...');

    final processingPause = await store.pauseOfflineCacheEntry(queued.id);
    expect(processingPause!.status, OfflineCacheEntryStatus.paused);
    expect(processingPause.reason, 'Paused by user.');

    final resumedEntry = await store.resumeOfflineCacheEntry(queued.id);
    expect(resumedEntry!.status, OfflineCacheEntryStatus.queued);

    final resumedProcessing = await store.markOfflineCacheEntryProcessing(
      queued.id,
    );
    expect(resumedProcessing!.status, OfflineCacheEntryStatus.processing);

    now = DateTime.utc(2026, 1, 16, 16);
    final cachedTrack = track.copyWith(localPath: '/cache/audio.mp3');
    final cached = await store.markOfflineCacheEntryCached(
      queued.id,
      cachedTrack,
      reason: 'Cached 1.0 MB.',
      byteCount: 1024 * 1024,
      checksum: 'cache-checksum',
    );

    expect(cached!.status, OfflineCacheEntryStatus.cached);
    expect(cached.track.localPath, '/cache/audio.mp3');
    expect(cached.cachedByteCount, 1024 * 1024);
    expect(cached.cachedMediaChecksum, 'cache-checksum');
    expect(store.tracks.single.id, track.id);
    expect(store.tracks.single.localPath, '/cache/audio.mp3');
    expect(store.search('', offlineOnly: true).single.id, track.id);

    final persistedStore = LibraryStore(clock: clock);
    await persistedStore.load();
    final persistedCached = persistedStore.offlineCacheEntryById(queued.id)!;
    expect(persistedCached.cachedByteCount, 1024 * 1024);
    expect(persistedCached.cachedMediaChecksum, 'cache-checksum');

    now = DateTime.utc(2026, 1, 16, 16, 30);
    final evicted = await store.markOfflineCacheEntryEvicted(
      queued.id,
      reason: 'Evicted to keep cache under 500.0 MB.',
    );

    expect(evicted!.status, OfflineCacheEntryStatus.queued);
    expect(evicted.reason, 'Evicted to keep cache under 500.0 MB.');
    expect(evicted.track.localPath, '');
    expect(evicted.cachedByteCount, 0);
    expect(evicted.cachedMediaChecksum, '');
    expect(store.tracks.single.localPath, '');
    expect(store.search('', offlineOnly: true), isEmpty);

    now = DateTime.utc(2026, 1, 16, 17);
    final paused = await store.pauseOfflineCacheEntry(queued.id);
    expect(paused!.status, OfflineCacheEntryStatus.paused);
    expect(paused.reason, 'Paused by user.');

    final persistedPausedStore = LibraryStore(clock: clock);
    await persistedPausedStore.load();
    expect(
      persistedPausedStore.offlineCacheEntryById(queued.id)!.status,
      OfflineCacheEntryStatus.paused,
    );

    final pausedAgain = await store.pauseOfflineCacheEntry(queued.id);
    expect(pausedAgain!.status, OfflineCacheEntryStatus.paused);

    now = DateTime.utc(2026, 1, 16, 17, 30);
    final resumed = await store.resumeOfflineCacheEntry(queued.id);
    expect(resumed!.status, OfflineCacheEntryStatus.queued);
    expect(resumed.reason, 'Ready to cache media.');

    final resumedAgain = await store.resumeOfflineCacheEntry(queued.id);
    expect(resumedAgain!.status, OfflineCacheEntryStatus.queued);

    now = DateTime.utc(2026, 1, 16, 18);
    final failed = await store.markOfflineCacheEntryFailed(
      queued.id,
      reason: 'Network failed.',
    );

    expect(failed!.status, OfflineCacheEntryStatus.failed);
    expect(failed.reason, 'Network failed.');

    final failedPause = await store.pauseOfflineCacheEntry(queued.id);
    expect(failedPause!.status, OfflineCacheEntryStatus.paused);

    final failedResume = await store.resumeOfflineCacheEntry(queued.id);
    expect(failedResume!.status, OfflineCacheEntryStatus.queued);

    expect(await store.markOfflineCacheEntryProcessing('missing'), isNull);
    expect(
      await store.markOfflineCacheEntryEvicted('missing', reason: 'Missing.'),
      isNull,
    );
  });

  test('edits persisted track metadata for search browse and suggestions', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'Untitled Import',
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        genre: 'Unknown Genre',
      ),
    ]);

    final updated = await store.updateTrackMetadata(
      '1',
      title: '  Aether Bloom  ',
      artist: '  Mira Vale  ',
      album: '  Dawn Signals  ',
      genre: '  Synthwave  ',
    );

    expect(updated, isNotNull);
    expect(updated!.id, '1');
    expect(updated.title, 'Aether Bloom');
    expect(updated.artist, 'Mira Vale');
    expect(updated.album, 'Dawn Signals');
    expect(updated.genre, 'Synthwave');
    expect(store.search('untitled'), isEmpty);
    expect(store.search('synthwave').single.id, '1');
    expect(
      store.browseGroups(LibraryBrowseType.artist).single.label,
      'Mira Vale',
    );
    expect(
      store.searchSuggestions('dawn').map((suggestion) => suggestion.value),
      contains('Dawn Signals'),
    );

    final secondStore = LibraryStore();
    await secondStore.load();

    expect(secondStore.tracks.single.title, 'Aether Bloom');
    expect(secondStore.search('mira').single.id, '1');
  });

  test('track metadata edits require a title and normalize empty fields', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[_track('1', title: 'Original')]);

    expect(
      store.updateTrackMetadata(
        '1',
        title: '   ',
        artist: 'Artist',
        album: 'Album',
        genre: 'Genre',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      await store.updateTrackMetadata(
        'missing',
        title: 'Missing',
        artist: '',
        album: '',
        genre: '',
      ),
      isNull,
    );

    final updated = await store.updateTrackMetadata(
      '1',
      title: 'Original',
      artist: '',
      album: '',
      genre: '',
    );

    expect(updated!.artist, 'Unknown Artist');
    expect(updated.album, 'Unknown Album');
    expect(updated.genre, 'Unknown Genre');
  });

  test('persists validated track chapters across library reloads', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'chaptered',
        title: 'Chaptered',
        duration: const Duration(minutes: 3),
      ),
    ]);

    final updated = await store.updateTrackChapters(
      'chaptered',
      <TrackChapter>[
        TrackChapter(start: const Duration(minutes: 2), title: 'Second'),
        TrackChapter(start: Duration.zero, title: 'First'),
        TrackChapter(start: const Duration(minutes: 3), title: 'Too late'),
      ],
    );

    expect(updated!.chapters.map((chapter) => chapter.title), <String>[
      'First',
      'Second',
    ]);
    expect(await store.updateTrackChapters('missing', <TrackChapter>[]), isNull);

    final reloaded = LibraryStore();
    await reloaded.load();
    expect(reloaded.tracks.single.chapters.map((chapter) => chapter.title), <String>[
      'First',
      'Second',
    ]);
  });

  test('builds smart playlists from library and playback state', () async {
    var now = DateTime.utc(2026, 1, 14, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'old',
        title: 'Gamma',
        artist: 'Zed',
        addedAt: DateTime.utc(2026, 1, 1),
      ),
      _track(
        'middle',
        title: 'Alpha',
        artist: 'Ari',
        addedAt: DateTime.utc(2026, 1, 2),
      ),
      _track(
        'new',
        title: 'Beta',
        artist: 'Mia',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
    ]);

    await store.toggleFavorite('old');
    await store.toggleFavorite('middle');
    await store.recordPlayback('old');
    now = DateTime.utc(2026, 1, 14, 12, 1);
    await store.recordPlayback('new');
    now = DateTime.utc(2026, 1, 14, 12, 2);
    await store.recordPlayback('old');
    now = DateTime.utc(2026, 1, 14, 12, 3);
    await store.recordPlayback('middle');

    final smartPlaylists = store.smartPlaylists();

    expect(
      smartPlaylists.map((playlist) => playlist.type),
      SmartPlaylistType.values,
    );
    expect(
      smartPlaylists
          .firstWhere(
            (playlist) => playlist.type == SmartPlaylistType.favorites,
          )
          .trackCount,
      2,
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.favorites,
      ).map((track) => track.id),
      <String>['middle', 'old'],
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.recentlyAdded,
        limit: 2,
      ).map((track) => track.id),
      <String>['new', 'middle'],
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.recentlyPlayed,
      ).map((track) => track.id),
      <String>['middle', 'old', 'new'],
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.mostPlayed,
      ).map((track) => track.id),
      <String>['old', 'middle', 'new'],
    );
    expect(
      store.tracksForSmartPlaylist(
        SmartPlaylistType.mostPlayed,
        limit: 2,
      ).map((track) => track.id),
      <String>['old', 'middle'],
    );
    expect(
      store.tracksForSmartPlaylist(SmartPlaylistType.mostPlayed, limit: 0),
      isEmpty,
    );
  });

  test(
    'builds local track radio queues from seed metadata and history',
    () async {
      var now = DateTime.utc(2026, 1, 14, 13);
      final store = LibraryStore(clock: () => now);
      await store.load();
      await store.addTracks(<Track>[
        _track(
          'seed',
          title: 'Seed Signal',
          artist: 'Mira',
          album: 'Dawn',
          genre: 'Ambient',
        ),
        _track(
          'same-artist',
          title: 'Mira Echo',
          artist: 'Mira',
          album: 'Elsewhere',
          genre: 'Folk',
        ),
        _track(
          'same-genre',
          title: 'Ambient Field',
          artist: 'Ari',
          album: 'Clouds',
          genre: 'Ambient',
        ),
        _track(
          'same-album',
          title: 'Dawn Interlude',
          artist: 'Nova',
          album: 'Dawn',
          genre: 'Jazz',
        ),
        _track(
          'unplayable',
          title: 'Metadata Only',
          artist: 'Mira',
          album: 'Dawn',
          genre: 'Ambient',
          localPath: '',
        ),
        _track(
          'unrelated',
          title: 'Elsewhere',
          artist: 'Orion',
          album: 'Night',
          genre: 'Jazz',
        ),
      ]);
      await store.toggleFavorite('same-genre');
      await store.recordPlayback('same-album');
      now = DateTime.utc(2026, 1, 14, 13, 1);
      await store.recordPlayback('same-artist');

      final radioQueue = store.radioQueueForTrack('seed')!;

      expect(radioQueue.seedTrack.id, 'seed');
      expect(
        radioQueue.tracks.map((track) => track.id),
        <String>['seed', 'same-artist', 'same-genre', 'same-album'],
      );
      expect(store.radioQueueForTrack('seed', limit: 2)!.tracks, hasLength(2));
      expect(store.radioQueueForTrack('missing'), isNull);
      expect(store.radioQueueForTrack('unplayable'), isNull);
    },
  );

  test('saves generated track radio queues as editable playlists', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'seed',
        title: 'Seed Signal',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
      ),
      _track(
        'match',
        title: 'Ambient Field',
        artist: 'Ari',
        album: 'Clouds',
        genre: 'Ambient',
      ),
      _track('unrelated', genre: 'Jazz'),
    ]);

    final playlist = await store.saveTrackRadioPlaylist('seed');

    expect(playlist, isNotNull);
    expect(playlist!.name, 'Seed Signal Radio');
    expect(playlist.trackIds, <String>['seed', 'match']);
    expect(store.playlistById(playlist.id), playlist);
    expect(await store.saveTrackRadioPlaylist('missing'), isNull);
  });

  test('builds local home feed sections from library activity', () async {
    var now = DateTime.utc(2026, 1, 14, 14);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'continue',
        title: 'Long Signal',
        artist: 'Mira',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 30),
        addedAt: DateTime.utc(2026, 1, 1),
      ),
      _track(
        'same-artist',
        title: 'Mira Field',
        artist: 'Mira',
        album: 'Clouds',
        genre: 'Folk',
        addedAt: DateTime.utc(2026, 1, 2),
      ),
      _track(
        'favorite',
        title: 'Favorite Drift',
        artist: 'Ari',
        album: 'Night',
        genre: 'Jazz',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
      _track(
        'new',
        title: 'Newest',
        artist: 'Zed',
        album: 'Fresh',
        genre: 'Pop',
        addedAt: DateTime.utc(2026, 1, 4),
      ),
      _track(
        'episode',
        title: 'Feed episode',
        genre: 'Podcast',
        sourceId: 'podcast-example',
        addedAt: DateTime.utc(2026, 1, 5),
      ),
    ]);

    await store.recordPlaybackProgress(
      'continue',
      const Duration(minutes: 5),
      const Duration(minutes: 30),
    );
    await store.toggleFavorite('favorite');
    await store.recordPlayback('favorite');
    await store.savePodcastSubscription(
      PodcastSubscription(
        id: 'podcast-feed',
        feedUrl: 'https://feeds.example.test/aether.xml',
        title: 'Aether Radio',
        episodes: <Track>[
          _track(
            'cached-episode',
            title: 'Cached feed episode',
            genre: 'Podcast',
            sourceId: 'podcast-rss',
            addedAt: DateTime.utc(2026, 1, 6),
          ),
        ],
      ),
    );
    now = DateTime.utc(2026, 1, 14, 14, 1);
    await store.recordPlayback('continue');
    now = DateTime.utc(2026, 1, 14, 14, 2);
    await store.recordPlayback('continue');

    final sections = store.homeFeedSections(limit: 2);

    expect(
      sections.map((section) => section.type),
      <LibraryHomeSectionType>[
        LibraryHomeSectionType.continueListening,
        LibraryHomeSectionType.recentlyPlayed,
        LibraryHomeSectionType.radioSeeds,
        LibraryHomeSectionType.mostPlayed,
        LibraryHomeSectionType.favorites,
        LibraryHomeSectionType.subscribedEpisodes,
        LibraryHomeSectionType.recentlyAdded,
      ],
    );
    expect(
      sections
          .firstWhere(
            (section) =>
                section.type == LibraryHomeSectionType.subscribedEpisodes,
          )
          .tracks
          .map((track) => track.id),
      <String>['cached-episode', 'episode'],
    );
    expect(
      sections
          .firstWhere(
            (section) =>
                section.type == LibraryHomeSectionType.continueListening,
          )
          .tracks
          .map((track) => track.id),
      <String>['continue'],
    );
    expect(
      sections
          .firstWhere(
            (section) => section.type == LibraryHomeSectionType.recentlyPlayed,
          )
          .tracks
          .map((track) => track.id),
      <String>['continue', 'favorite'],
    );
    expect(
      sections
          .firstWhere(
            (section) => section.type == LibraryHomeSectionType.radioSeeds,
          )
          .tracks
          .map((track) => track.id),
      <String>['continue', 'same-artist'],
    );
    expect(
      sections
          .firstWhere(
            (section) => section.type == LibraryHomeSectionType.recentlyAdded,
          )
          .tracks
          .map((track) => track.id),
      <String>['episode', 'new'],
    );
    expect(store.homeFeedSections(limit: 0), isEmpty);
  });

  test('creates updates and persists custom smart playlist rules', () async {
    var now = DateTime.utc(2026, 1, 15, 12);
    final store = LibraryStore(clock: () => now);
    await store.load();
    await store.addTracks(<Track>[
      _track(
        'ari-old',
        title: 'Low Tide',
        artist: 'Ari',
        genre: 'Ambient',
        addedAt: DateTime.utc(2026, 1),
      ),
      _track(
        'ari-new',
        title: 'Dawn Tide',
        artist: 'Ari',
        genre: 'Ambient',
        addedAt: DateTime.utc(2026, 1, 2),
      ),
      _track(
        'ari-rock',
        title: 'Rock Sun',
        artist: 'Ari',
        genre: 'Rock',
        addedAt: DateTime.utc(2026, 1, 3),
      ),
      _track(
        'mia',
        title: 'Mia Drift',
        artist: 'Mia',
        genre: 'Ambient',
        addedAt: DateTime.utc(2026, 1, 4),
      ),
    ]);
    await store.toggleFavorite('ari-old');
    await store.toggleFavorite('ari-new');
    await store.toggleFavorite('ari-rock');
    await store.recordPlayback('ari-old');
    now = DateTime.utc(2026, 1, 15, 12, 1);
    await store.recordPlayback('ari-new');
    now = DateTime.utc(2026, 1, 15, 12, 2);
    await store.recordPlayback('ari-old');

    final rule = await store.createCustomSmartPlaylist(
      name: '  Ambient Ari  ',
      query: 'ambient',
      artist: 'Ari',
      album: 'Album',
      favoritesOnly: true,
      minimumPlayCount: 1,
      sortMode: CustomSmartPlaylistSortMode.mostPlayed,
      limit: 2,
    );

    expect(rule.name, 'Ambient Ari');
    expect(rule.query, 'ambient');
    expect(rule.artist, 'Ari');
    expect(rule.album, 'Album');
    expect(
      store.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['ari-old', 'ari-new'],
    );

    final secondStore = LibraryStore(clock: () => now);
    await secondStore.load();

    expect(secondStore.customSmartPlaylists.single.id, rule.id);
    expect(secondStore.customSmartPlaylists.single.artist, 'Ari');
    expect(secondStore.customSmartPlaylists.single.album, 'Album');
    expect(
      secondStore.tracksForCustomSmartPlaylist(rule.id).map((track) => track.id),
      <String>['ari-old', 'ari-new'],
    );

    final updated = await secondStore.updateCustomSmartPlaylist(
      rule.id,
      name: 'Ari Library',
      query: 'ari',
      artist: 'Ari',
      album: 'Album',
      favoritesOnly: false,
      minimumPlayCount: 0,
      matchMode: CustomSmartPlaylistMatchMode.all,
      sortMode: CustomSmartPlaylistSortMode.title,
      limit: 3,
    );

    expect(updated!.name, 'Ari Library');
    expect(
      secondStore
          .tracksForCustomSmartPlaylist(rule.id)
          .map((track) => track.id),
      <String>['ari-new', 'ari-old', 'ari-rock'],
    );

    await secondStore.deleteCustomSmartPlaylist(rule.id);

    expect(secondStore.customSmartPlaylists, isEmpty);
    expect(secondStore.tracksForCustomSmartPlaylist(rule.id), isEmpty);
  });

  test('groups library tracks by artist album genre source and folder', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'First',
        artist: 'Ari',
        album: 'Dawn',
        genre: 'Ambient',
        duration: const Duration(minutes: 2),
        localPath: '/music/Ari/Dawn/first.mp3',
      ),
      _track(
        '2',
        title: 'Second',
        artist: 'Ari',
        album: 'Dusk',
        genre: 'Ambient',
        duration: const Duration(minutes: 3),
        localPath: '/music/Ari/Dusk/second.mp3',
      ),
      _track(
        '3',
        title: 'Third',
        artist: 'Mia',
        album: 'Dawn',
        genre: 'Jazz',
        sourceId: 'demo',
        duration: const Duration(minutes: 4),
        localPath: r'C:\Music\Mia\Dawn\third.mp3',
      ),
    ]);

    final artistGroups = store.browseGroups(LibraryBrowseType.artist);
    final albumGroups = store.browseGroups(LibraryBrowseType.album);
    final genreGroups = store.browseGroups(LibraryBrowseType.genre);
    final sourceGroups = store.browseGroups(LibraryBrowseType.source);
    final folderGroups = store.browseGroups(LibraryBrowseType.folder);

    expect(artistGroups.map((group) => group.label), <String>['Ari', 'Mia']);
    expect(artistGroups.first.trackCount, 2);
    expect(artistGroups.first.totalDuration, const Duration(minutes: 5));
    expect(albumGroups.map((group) => group.label), <String>['Dawn', 'Dusk']);
    expect(
      genreGroups.map((group) => group.label),
      <String>['Ambient', 'Jazz'],
    );
    expect(
      sourceGroups.map((group) => group.label),
      <String>['demo', 'local'],
    );
    expect(
      folderGroups.map((group) => group.label),
      <String>[
        '/music/Ari/Dawn',
        '/music/Ari/Dusk',
        r'C:\Music\Mia\Dawn',
      ],
    );
    expect(
      store
          .browseGroups(LibraryBrowseType.genre, query: 'amb')
          .map((group) => group.label),
      <String>['Ambient'],
    );
    expect(
      store
          .tracksForBrowseGroup(
            LibraryBrowseType.folder,
            '/music/Ari/Dawn',
          )
          .map((track) => track.id),
      <String>['1'],
    );
    expect(
      store
          .tracksForBrowseGroup(
            LibraryBrowseType.genre,
            'ambient',
            sortMode: LibrarySortMode.title,
          )
          .map((track) => track.id),
      <String>['1', '2'],
    );
  });

  test('builds recursive folder tree and opens descendant tracks', () async {
    final store = LibraryStore();
    await store.load();
    await store.addTracks(<Track>[
      _track(
        '1',
        title: 'First',
        album: 'Dawn',
        duration: const Duration(minutes: 2),
        localPath: '/music/Ari/Dawn/first.mp3',
      ),
      _track(
        '2',
        title: 'Second',
        album: 'Dusk',
        duration: const Duration(minutes: 3),
        localPath: '/music/Ari/Dusk/second.mp3',
      ),
      _track(
        '3',
        title: 'Third',
        album: 'Dawn',
        duration: const Duration(minutes: 4),
        localPath: r'C:\Music\Mia\Dawn\third.mp3',
      ),
      _track(
        'stream',
        title: 'Remote',
        localPath: '',
        streamUrl: 'https://media.example.test/remote.mp3',
      ),
    ]);

    final tree = store.folderTree();
    final ariNode = tree.firstWhere((node) => node.label == 'Ari');
    final ariDawnNode = tree.firstWhere(
      (node) => node.label == 'Dawn' && node.path.contains('Ari'),
    );
    final windowsDawnNode = tree.firstWhere(
      (node) => node.label == 'Dawn' && node.path.contains('Mia'),
    );

    expect(ariNode.trackCount, 2);
    expect(ariNode.directTrackCount, 0);
    expect(ariNode.childCount, 2);
    expect(ariNode.totalDuration, const Duration(minutes: 5));
    expect(ariDawnNode.trackCount, 1);
    expect(windowsDawnNode.trackCount, 1);
    expect(tree.map((node) => node.label), isNot(contains('Remote Streams')));
    expect(
      store.tracksForFolderNode(ariNode.key).map((track) => track.id),
      <String>['1', '2'],
    );
    expect(
      store.tracksForFolderNode(ariDawnNode.key).map((track) => track.id),
      <String>['1'],
    );

    final shareText = store.shareFolderNodeText(ariNode.key)!;
    expect(shareText, contains('AetherTune folder'));
    expect(shareText, contains('Name: Ari'));
    expect(shareText, contains('Tracks: 2'));
    expect(shareText, isNot(contains('/music')));
  });

  test('exports and restores a full library backup', () async {
    DateTime clock() => DateTime.utc(2026, 1, 11);
    final firstStore = LibraryStore(clock: clock);
    await firstStore.load();
    await firstStore.addTracks(<Track>[_track('1'), _track('2')]);
    await firstStore.toggleFavorite('2');
    final playlist = await firstStore.createPlaylist(
      'Backup Mix',
      trackIds: <String>['1', '2'],
    );
    final playlistArtworkUri =
        Uri.parse('https://media.example.test/backup-mix.jpg');
    await firstStore.updatePlaylistArtwork(playlist.id, playlistArtworkUri);
    await firstStore.setLyrics('1', 'backup lyrics');
    await firstStore.recordPlayback('2');
    await firstStore.recordPlaybackProgress(
      '1',
      const Duration(minutes: 4),
      const Duration(minutes: 20),
    );
    await firstStore.setPauseListeningHistory(true);
    final smartRule = await firstStore.createCustomSmartPlaylist(
      name: 'Favorite plays',
      favoritesOnly: true,
      minimumPlayCount: 1,
      sortMode: CustomSmartPlaylistSortMode.mostPlayed,
      limit: 10,
    );
    final subscription = await firstStore.savePodcastSubscription(
      PodcastSubscription(
        id: 'podcast',
        feedUrl: 'https://feeds.example.test/aether.xml',
        title: 'Aether Radio',
      ),
    );
    await firstStore.markPodcastSubscriptionFetched(subscription.id);
    final archiveProvider = InternetArchiveProvider();
    final archiveTrack = _track(
      'archive-backup',
      title: 'Archive Backup',
      sourceId: archiveProvider.id,
      externalId: 'archive-backup',
      localPath: '',
      streamUrl: 'https://archive.org/download/archive-backup/audio.mp3',
    );
    final archivePolicy = OfflineMediaPolicy(
      <MusicSourceProvider>[archiveProvider],
    );
    final cacheEntry = await firstStore.queueOfflineCache(
      archiveTrack,
      OfflineMediaAction.cache,
      archivePolicy.evaluate(archiveTrack, OfflineMediaAction.cache),
    );

    final backupJson = firstStore.exportBackupJson();

    final secondStore = LibraryStore(clock: clock);
    await secondStore.load();
    await secondStore.addTracks(<Track>[_track('stale')]);
    await secondStore.restoreBackupJson(backupJson);

    expect(
      secondStore.tracks.map((track) => track.id),
      containsAll(<String>[
        '1',
        '2',
      ]),
    );
    expect(secondStore.tracks, hasLength(2));
    expect(
      secondStore.tracks.singleWhere((track) => track.id == '2').isFavorite,
      isTrue,
    );
    expect(secondStore.playlistById(playlist.id)!.name, 'Backup Mix');
    expect(
      secondStore.playlistById(playlist.id)!.trackIds,
      <String>[
        '1',
        '2',
      ],
    );
    expect(
      secondStore.playlistById(playlist.id)!.artworkUri,
      playlistArtworkUri,
    );
    expect(secondStore.lyricsForTrack('1')!.plainText, 'backup lyrics');
    expect(secondStore.playbackHistory.single.trackId, '2');
    expect(secondStore.pauseListeningHistory, isTrue);
    expect(secondStore.recentlyPlayedTracks().single.id, '2');
    expect(
      secondStore.playbackProgressForTrack('1')!.position,
      const Duration(minutes: 4),
    );
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.title,
      'Aether Radio',
    );
    expect(
      secondStore.podcastSubscriptionById(subscription.id)!.lastFetchedAt,
      DateTime.utc(2026, 1, 11),
    );
    expect(secondStore.customSmartPlaylists.single.name, 'Favorite plays');
    expect(
      secondStore
          .tracksForCustomSmartPlaylist(smartRule.id)
          .map((track) => track.id),
      <String>['2'],
    );
    expect(secondStore.offlineCacheQueue.single.id, cacheEntry.id);
    expect(secondStore.offlineCacheQueue.single.track.title, 'Archive Backup');
  });

  test('rejects invalid backup JSON without replacing the library', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 12),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);

    expect(
      store.restoreBackupJson('[]'),
      throwsA(isA<FormatException>()),
    );
    expect(store.tracks.single.id, '1');
  });

  test('rejects unsupported backup versions', () async {
    final store = LibraryStore(
      clock: () => DateTime.utc(2026, 1, 13),
    );
    await store.load();
    await store.addTracks(<Track>[_track('1')]);
    final backup = jsonDecode(store.exportBackupJson()) as Map<String, dynamic>;
    backup['version'] = 999;

    expect(
      store.restoreBackupJson(jsonEncode(backup)),
      throwsA(isA<FormatException>()),
    );
  });
}

Track _track(
  String id, {
  String? title,
  String artist = 'Artist',
  String album = 'Album',
  String genre = 'Unknown Genre',
  String sourceId = 'local',
  String? externalId,
  Duration duration = Duration.zero,
  DateTime? addedAt,
  String? localPath,
  String? contentHash,
  String? streamUrl,
  Uri? artworkUri,
}) {
  return Track(
    id: id,
    title: title ?? 'Track $id',
    artist: artist,
    album: album,
    genre: genre,
    duration: duration,
    artworkUri: artworkUri,
    localPath: localPath ?? '/music/$id.mp3',
    contentHash: contentHash,
    streamUrl: streamUrl,
    sourceId: sourceId,
    externalId: externalId,
    addedAt: addedAt ?? DateTime.utc(2026),
  );
}
