import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/aethertune_deep_link.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/aethertune_deep_link_listener.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('parses only supported AetherTune custom link hosts', () {
    expect(
      AetherTuneDeepLink.tryParse(
        Uri.parse('aethertune://playlist?data=abc'),
      )?.kind,
      AetherTuneDeepLinkKind.playlist,
    );
    expect(
      AetherTuneDeepLink.tryParse(
        Uri.parse('AETHERTUNE://smart-playlist?data=abc'),
      )?.kind,
      AetherTuneDeepLinkKind.smartPlaylist,
    );
    expect(
      AetherTuneDeepLink.tryParse(Uri.parse('https://example.test/playlist')),
      isNull,
    );
    expect(
      AetherTuneDeepLink.tryParse(Uri.parse('aethertune://track?data=abc')),
      isNull,
    );
  });

  testWidgets('imports a shared playlist link once and opens playlists', (
    tester,
  ) async {
    final source = LibraryStore();
    final target = LibraryStore();
    await source.load();
    await target.load();
    final track = const Track(
      id: 'shared-track',
      title: 'Shared track',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(minutes: 3),
      localPath: '/music/shared-track.mp3',
    );
    await source.addTracks(<Track>[track]);
    await target.addTracks(<Track>[track]);
    final playlist = await source.createPlaylist('Shared mix');
    await source.addTrackToPlaylist(playlist.id, track.id);
    final link = source.playlistImportLink(playlist.id)!;
    final incoming = StreamController<Uri>();
    addTearDown(incoming.close);
    var importedKind;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AetherTuneDeepLinkListener(
            library: target,
            incomingUriStream: incoming.stream,
            onImported: (kind) => importedKind = kind,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    incoming.add(Uri.parse(link));
    incoming.add(Uri.parse(link));
    await tester.pumpAndSettle();

    expect(importedKind, AetherTuneDeepLinkKind.playlist);
    expect(target.playlists.where((item) => item.name == 'Shared mix'), hasLength(1));
    expect(find.text('Imported Shared mix from shared link.'), findsOneWidget);
  });
}
