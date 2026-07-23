import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/musicbrainz_artist_release_provider.dart';
import 'package:aethertune/src/data/musicbrainz_metadata_provider.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/artist_release_updates_shelf.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('explicitly refreshes followed artist releases and opens details', (
    tester,
  ) async {
    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[_track('mira')]);
    await library.setArtistFollowed('Mira', true);
    var calls = 0;
    Uri? opened;
    final provider = MusicBrainzArtistReleaseProvider(
      limiter: _instantLimiter(),
      loader: (uri, _) async {
        calls += 1;
        if (uri.path.endsWith('/artist')) {
          return '{"artists":[{"id":"11111111-1111-1111-1111-111111111111","name":"Mira"}]}';
        }
        return '{"release-groups":[{"id":"33333333-3333-3333-3333-333333333333","title":"New single","first-release-date":"2026-03-01","primary-type":"Single"}]}';
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: Scaffold(
            body: ArtistReleaseUpdatesShelf(
              provider: provider,
              openDetails: (uri) async {
                opened = uri;
                return true;
              },
            ),
          ),
        ),
      ),
    );

    expect(calls, 0);
    await tester.tap(find.byKey(const Key('home-artist-releases-refresh')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('New single'), findsOneWidget);
    await tester.tap(find.text('New single'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open MusicBrainz'));
    await tester.pumpAndSettle();
    expect(
      opened,
      Uri.parse(
        'https://musicbrainz.org/release-group/33333333-3333-3333-3333-333333333333',
      ),
    );
  });

  testWidgets('does not request artist releases in offline mode', (
    tester,
  ) async {
    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[_track('mira')]);
    await library.setArtistFollowed('Mira', true);
    await library.setOfflineModeEnabled(true);
    await library.setDesktopArtistReleaseRefreshEnabled(true);
    var calls = 0;
    final provider = MusicBrainzArtistReleaseProvider(
      limiter: _instantLimiter(),
      loader: (_, _) async {
        calls += 1;
        return '{}';
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: Scaffold(
            body: ArtistReleaseUpdatesShelf(
              provider: provider,
              platform: TargetPlatform.windows,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Offline mode'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('home-artist-releases-refresh')),
          )
          .onPressed,
      isNull,
    );
    await _sendLifecycleState(tester, AppLifecycleState.hidden);
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('refreshes opted-in releases when a desktop enters the tray', (
    tester,
  ) async {
    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[_track('mira')]);
    await library.setArtistFollowed('Mira', true);
    await library.setDesktopArtistReleaseRefreshEnabled(true);
    var calls = 0;
    final provider = MusicBrainzArtistReleaseProvider(
      limiter: _instantLimiter(),
      loader: (uri, _) async {
        calls += 1;
        if (uri.path.endsWith('/artist')) {
          return '{"artists":[{"id":"11111111-1111-1111-1111-111111111111","name":"Mira"}]}';
        }
        return '{"release-groups":[]}';
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: Scaffold(
            body: ArtistReleaseUpdatesShelf(
              provider: provider,
              platform: TargetPlatform.windows,
            ),
          ),
        ),
      ),
    );

    expect(calls, 0);
    await _sendLifecycleState(tester, AppLifecycleState.hidden);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(
      find.text('No dated album, EP, or single updates found'),
      findsOneWidget,
    );

    await _sendLifecycleState(tester, AppLifecycleState.hidden);
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('does not refresh automatically on a mobile lifecycle change', (
    tester,
  ) async {
    final library = LibraryStore();
    await library.load();
    await library.addTracks(<Track>[_track('mira')]);
    await library.setArtistFollowed('Mira', true);
    await library.setDesktopArtistReleaseRefreshEnabled(true);
    var calls = 0;
    final provider = MusicBrainzArtistReleaseProvider(
      limiter: _instantLimiter(),
      loader: (_, _) async {
        calls += 1;
        return '{}';
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryStore>.value(
        value: library,
        child: MaterialApp(
          home: Scaffold(
            body: ArtistReleaseUpdatesShelf(
              provider: provider,
              platform: TargetPlatform.android,
            ),
          ),
        ),
      ),
    );

    await _sendLifecycleState(tester, AppLifecycleState.hidden);
    await tester.pump();

    expect(calls, 0);
  });
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

MusicBrainzRequestLimiter _instantLimiter() {
  return MusicBrainzRequestLimiter(
    clock: () => DateTime.utc(2026),
    delay: (_) async {},
  );
}

Track _track(String id) {
  return Track(
    id: id,
    title: 'Track',
    artist: 'Mira',
    album: 'Album',
    duration: const Duration(minutes: 3),
    sourceId: 'local',
    localPath: '/music/$id.mp3',
  );
}
