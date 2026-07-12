import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/playlist.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/playlist_artwork.dart';
import 'package:aethertune/src/ui/widgets/track_artwork.dart';

void main() {
  testWidgets('generates a bounded collage from playlist tracks', (
    tester,
  ) async {
    final playlist = Playlist(id: 'mix', name: 'Morning mix');
    final tracks = <Track>[
      _track('one'),
      _track('two'),
      _track('three'),
      _track('four'),
      _track('five'),
    ];

    await tester.pumpWidget(
      _host(PlaylistArtwork(playlist: playlist, tracks: tracks, size: 96)),
    );

    expect(
      find.byKey(const Key('playlist-artwork-collage-mix')),
      findsOneWidget,
    );
    expect(find.byType(TrackArtwork), findsNWidgets(4));
    expect(
      find.bySemanticsLabel('Generated artwork collage for Morning mix'),
      findsOneWidget,
    );
  });

  testWidgets('uses explicit playlist artwork instead of generated collage', (
    tester,
  ) async {
    final playlist = Playlist(
      id: 'custom',
      name: 'Custom mix',
      artworkUri: Uri.parse('https://media.example.test/cover.png'),
    );

    await tester.pumpWidget(
      _host(
        PlaylistArtwork(playlist: playlist, tracks: <Track>[_track('one')]),
      ),
    );

    expect(
      find.byKey(const Key('playlist-artwork-collage-custom')),
      findsNothing,
    );
    expect(find.byType(TrackArtwork), findsOneWidget);
  });

  testWidgets('uses the queue fallback for an empty artwork-free playlist', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PlaylistArtwork(
          playlist: Playlist(id: 'empty', name: 'Empty'),
        ),
      ),
    );

    expect(find.byIcon(Icons.queue_music), findsOneWidget);
  });
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

Track _track(String id) {
  return Track(
    id: id,
    title: id,
    artworkUri: Uri.parse('https://media.example.test/$id.png'),
  );
}
